defmodule Kino.ExRatatui.Telemetry do
  @moduledoc """
  `:telemetry` integration for `kino_ex_ratatui`.

  Mirrors the shape of [`ExRatatui.Telemetry`](`ExRatatui.Telemetry`)
  one layer up — events fire at the boundaries this package controls
  (Kino widget boot, ANSI broadcast, client input forward, widget
  shutdown) rather than at the runtime / session layer `ex_ratatui`
  already instruments. Both fire concurrently when a Livebook-driven
  TUI is running, and consumers attach handlers to whichever they
  need.

  ## Why a separate event tree

  `ex_ratatui` measures the App / runtime layer:
  `[:ex_ratatui, :runtime, :event]`, `[:ex_ratatui, :render, :frame]`,
  `[:ex_ratatui, :session, :lifecycle, *]`, and so on. Those events
  fire from inside the `ex_ratatui` runtime server regardless of transport.

  `kino_ex_ratatui` adds events for the Kino-side cost:

    * widget boot (lazy `Session` + runtime construction triggered by
      the first `"resize"` from xterm.js)
    * the per-frame work the widget itself does on top of the
      runtime: turning the runtime's iodata into a binary and pushing
      it over the Kino bridge to xterm.js
    * client input being forwarded from the iframe to the runtime
    * subsequent resize forwards (the first resize is rolled into the
      `:transport, :connect` span)
    * widget teardown

  Attaching handlers to BOTH event trees gives a complete profile of
  a Livebook-driven TUI without double-counting any single operation.

  ## Events

  All events are prefixed with `:kino_ex_ratatui`.

  ### Span events (`:start` / `:stop` / `:exception`)

  Each span emits three events with the suffix appended. Handlers
  typically attach to `:stop` for timing and `:exception` for
  failure tracking.

  | Event | Description | Metadata |
  | ----- | ----------- | -------- |
  | `[:kino_ex_ratatui, :transport, :connect]` | First `"resize"` event boots `ExRatatui.Session` + runtime server (`mount/1` runs inside the span). | `:mod`, `:width`, `:height` |
  | `[:kino_ex_ratatui, :render, :frame]` | Per-frame Kino-side work: `IO.iodata_to_binary/1` + the `broadcast_event/3` helper from `Kino.JS.Live` over the bridge. | `:mod`, `:byte_count` |

  `:start` events carry `%{monotonic_time: integer, system_time: integer}`
  as measurements. `:stop` events add `:duration` (native units). On
  exception the metadata gains `:kind`, `:reason`, and `:stacktrace`.

  ### Single events

  | Event | Description | Measurements | Metadata |
  | ----- | ----------- | ------------ | -------- |
  | `[:kino_ex_ratatui, :transport, :disconnect]` | Runtime server exited (`{:DOWN, _, _, _, _}`) or the Kino widget is terminating. Fires exactly once per session — when `:DOWN` clears the server refs, the widget's `terminate/2` becomes a no-op. | `%{system_time: integer}` | `:mod`, `:reason` |
  | `[:kino_ex_ratatui, :input, :forward]` | A keypress (or other byte payload) from xterm.js was forwarded to the runtime via `ExRatatui.Transport.ByteStream.forward_input/3`. | `%{system_time: integer}` | `:mod`, `:byte_count` |
  | `[:kino_ex_ratatui, :resize]` | A resize after the initial boot was forwarded to the runtime via `ExRatatui.Transport.ByteStream.forward_resize/4`. | `%{system_time: integer}` | `:mod`, `:width`, `:height` |

  ## Attaching a default logger

      # In a Livebook setup cell (or the application's start/2):
      Kino.ExRatatui.Telemetry.attach_default_logger()

  That attaches a handler logging every `:stop` and single event at
  `:debug` level. Pass `attach_default_logger(level: :info)` to bump
  the level. Detach with `detach_default_logger/0`.

  Real apps wire `Telemetry.Metrics` instead:

      defmodule MyApp.Telemetry do
        import Telemetry.Metrics

        def metrics do
          [
            summary("kino_ex_ratatui.transport.connect.stop.duration",
              unit: {:native, :millisecond}),
            counter("kino_ex_ratatui.transport.disconnect"),
            summary("kino_ex_ratatui.render.frame.stop.duration",
              unit: {:native, :microsecond}),
            counter("kino_ex_ratatui.input.forward")
          ]
        end
      end
  """

  require Logger

  @doc """
  Wraps `fun` in a `:telemetry` span rooted at
  `[:kino_ex_ratatui | event]`.

  The `fun`'s return value is returned unchanged. The given `meta`
  is forwarded to both the `:start` and `:stop` events.
  """
  @spec span([atom(), ...], map(), (-> term())) :: term()
  def span(event, meta, fun) when is_list(event) and is_map(meta) and is_function(fun, 0) do
    :telemetry.span([:kino_ex_ratatui | event], meta, fn -> {fun.(), meta} end)
  end

  @doc """
  Emits a single `:telemetry` event rooted at
  `[:kino_ex_ratatui | event]`.

  `:system_time` is added to the measurements automatically if not
  already present.
  """
  @spec execute([atom(), ...], map(), map()) :: :ok
  def execute(event, measurements, meta)
      when is_list(event) and is_map(measurements) and is_map(meta) do
    measurements = Map.put_new_lazy(measurements, :system_time, &System.system_time/0)
    :telemetry.execute([:kino_ex_ratatui | event], measurements, meta)
  end

  @doc """
  Attaches a logger that prints every `kino_ex_ratatui` telemetry
  event. Useful during development; detach with
  `detach_default_logger/0`.

  ## Options

    * `:level` — log level (default: `:debug`).
    * `:events` — list of event suffixes to attach (default: all
      `:stop` and single events).
  """
  @spec attach_default_logger(keyword()) :: :ok | {:error, :already_exists}
  def attach_default_logger(opts \\ []) do
    level = Keyword.get(opts, :level, :debug)
    events = Keyword.get(opts, :events, default_logger_events())

    :telemetry.attach_many(
      handler_id(),
      events,
      &__MODULE__.__default_logger_handler__/4,
      %{level: level}
    )
  end

  @doc """
  Detaches the default logger previously attached with
  `attach_default_logger/1`.
  """
  @spec detach_default_logger() :: :ok | {:error, :not_found}
  def detach_default_logger do
    :telemetry.detach(handler_id())
  end

  @doc false
  def __default_logger_handler__(event, measurements, metadata, %{level: level}) do
    Logger.log(level, fn ->
      [
        "[kino_ex_ratatui] ",
        Enum.map_join(event, ".", &to_string/1),
        " ",
        inspect(Map.merge(measurements, metadata),
          limit: :infinity,
          printable_limit: :infinity
        )
      ]
    end)
  end

  defp handler_id, do: "kino-ex-ratatui-default-logger"

  defp default_logger_events do
    [
      [:kino_ex_ratatui, :transport, :connect, :stop],
      [:kino_ex_ratatui, :transport, :connect, :exception],
      [:kino_ex_ratatui, :transport, :disconnect],
      [:kino_ex_ratatui, :render, :frame, :stop],
      [:kino_ex_ratatui, :render, :frame, :exception],
      [:kino_ex_ratatui, :input, :forward],
      [:kino_ex_ratatui, :resize]
    ]
  end
end
