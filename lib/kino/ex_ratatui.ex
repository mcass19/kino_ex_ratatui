defmodule Kino.ExRatatui do
  @moduledoc """
  Run an `ExRatatui.App` inside a Livebook notebook via xterm.js.

  `Kino.ExRatatui` is a byte-stream transport that pipes the runtime
  server's rendered ANSI through an xterm.js iframe and forwards
  keypresses + resize events back.

  ## Example

      defmodule Counter do
        use ExRatatui.App
        alias ExRatatui.Event.Key
        alias ExRatatui.Layout.Rect
        alias ExRatatui.Widgets.Paragraph

        def mount(_), do: {:ok, %{n: 0}}

        def render(state, frame) do
          [{%Paragraph{text: "Count: \#{state.n}"},
            %Rect{x: 0, y: 0, width: frame.width, height: frame.height}}]
        end

        def handle_event(%Key{code: "+"}, s), do: {:noreply, %{s | n: s.n + 1}}
        def handle_event(%Key{code: "q"}, s), do: {:stop, s}
        def handle_event(_, s),                do: {:noreply, s}
      end

      Kino.ExRatatui.new(Counter)

  ## Mount options

  The second argument to `new/2` is a keyword list. Any key not listed
  under [Display options](#module-display-options) below is forwarded
  verbatim to `c:ExRatatui.App.mount/1`. Use it for per-instance
  configuration the App reads from its mount opts.

  The keys `:mod`, `:name`, and `:transport` are reserved by the
  runtime and silently overwritten.

  ## Display options

  Reserved opts that configure the xterm.js iframe rather than the App.
  All are optional; defaults preserve the current widget look. Unknown
  values raise `ArgumentError` at the call site.

  | Option | Type | Default | Notes |
  | ------ | ---- | ------- | ----- |
  | `:theme` | `map()` or `:dark` / `:light` / `:livebook` | catppuccin-style dark theme | A map is forwarded to xterm.js's `Terminal({theme: ...})` verbatim — accepts the full xterm.js [`ITheme`](https://xtermjs.org/docs/api/terminal/interfaces/itheme/) object (`:background`, `:foreground`, `:cursor`, `:cursorAccent`, `:selectionBackground`, the 16-color ANSI palette, …). Atom keys are JSON-encoded as strings; use the camelCase xterm.js expects (`cursorAccent`, not `cursor_accent`). The atom shorthands resolve in the JS hook: `:dark` and `:light` pick a bundled palette, `:livebook` follows the user's `prefers-color-scheme` and live-switches when it changes. |
  | `:font_family` | `String.t()` | `"ui-monospace, SFMono-Regular, Menlo, Monaco, Consolas, monospace"` | CSS `font-family` value. Anything `xterm.js` can render. |
  | `:font_size` | `pos_integer()` | `13` | Cell font size in px. |
  | `:height` | `String.t()` | `"400px"` | CSS height applied to the xterm container. Accepts any valid CSS length (`"600px"`, `"60vh"`, …). |
  | `:cursor_blink` | `boolean()` | `true` | xterm.js cursor blink. |
  | `:scrollback` | `non_neg_integer()` | `1000` | xterm.js scrollback line limit. |
  | `:stopped_message` | `String.t()` | `"App stopped — re-evaluate the cell to start a new run."` | Shown in the iframe after the runtime exits (`{:stop, _}` or `mount/1` failure). |

  Example:

      Kino.ExRatatui.new(Counter,
        # mount opts → App.mount/1
        start: 10,
        # display opts → xterm.js
        theme: %{background: "#0d1117", foreground: "#c9d1d9"},
        font_size: 14,
        height: "600px"
      )

  ## Global configuration

  Set defaults that apply to every `new/2` and `frame/2` call in the
  current Livebook (or the application's runtime) with `configure/1`:

      # In a setup cell, or the application's start/2:
      Kino.ExRatatui.configure(
        theme: :livebook,
        font_family: "JetBrains Mono, ui-monospace, monospace",
        font_size: 14
      )

  Merge order is **per-instance opts > `configure/1` > module
  defaults**, key by key. Setting `theme:` globally and then passing
  `theme: %{background: "#000"}` per-instance overrides the theme
  alone — the global `font_size` still wins for that call. See
  `configure/1` for the full list and the
  [Configuration guide](configuration.md) for recipes.

  ## Lifecycle

  Each `new/2` call spawns a fresh `Kino.JS.Live` server. The runtime
  server and `ExRatatui.Session` are created lazily on the first
  `"resize"` event from the iframe so we always start at the correct
  cell dimensions reported by xterm.js's FitAddon. Re-evaluating the
  cell (or closing the notebook) tears the runtime server down and
  starts a new one — no state is preserved across re-evals.

  ## How it plugs into ExRatatui

  Implements `ExRatatui.Transport` as a byte-stream transport, using
  `ExRatatui.Transport.start_server/1` to boot the runtime and
  `ExRatatui.Transport.ByteStream` to pump input + resize events. See
  the [Custom Transports
  guide](https://hexdocs.pm/ex_ratatui/custom_transports.html) for the
  reference shape.

  ## Inline images

  The bundled JS hook loads `@xterm/addon-image`, so
  `ExRatatui.Widgets.Image` renders end-to-end in Livebook over Sixel
  and iTerm2 inline-image protocols. Build images with
  `ExRatatui.Image.new/2` and place them in the widget tree like any
  other widget — no kino-side configuration is needed. The protocol is
  picked explicitly at construction time; pass `:sixel` or `:iterm2`
  (xterm.js does not implement the Kitty graphics protocol). See the
  [Images guide](https://hexdocs.pm/ex_ratatui/images.html) for the
  full API.
  """

  use Kino.JS, assets_path: "lib/assets/kino_ex_ratatui"
  use Kino.JS.Live

  @behaviour ExRatatui.Transport

  alias ExRatatui.Session
  alias ExRatatui.Transport
  alias ExRatatui.Transport.ByteStream
  alias Kino.ExRatatui.Telemetry
  alias Kino.JS, as: KinoJS
  alias Kino.JS.Live, as: KinoLive

  # Display defaults. Kept in one map so the public moduledoc, the
  # validators, and the JS payload all read from the same source. JS
  # has its own copy of these (see `assets/js/main.js`) for the case
  # where Elixir didn't supply them — keep the two in sync.
  @default_display %{
    theme: %{background: "#1e1e2e", foreground: "#cdd6f4", cursor: "#f5e0dc"},
    font_family: "ui-monospace, SFMono-Regular, Menlo, Monaco, Consolas, monospace",
    font_size: 13,
    height: "400px",
    cursor_blink: true,
    scrollback: 1000,
    stopped_message: "App stopped — re-evaluate the cell to start a new run."
  }

  @display_keys Map.keys(@default_display)

  @reserved_runtime_keys [:mod, :name, :transport]

  # Defaults for `frame/2`. Mirrors the canonical 80×24 terminal so
  # callers who just want a screenshot of a few widgets don't have to
  # think about sizing.
  @default_cols 80
  @default_rows 24

  # Static frames support a subset of display opts — anything tied to
  # the live event loop (cursor blink, scrollback, stopped-state UI)
  # has nothing to apply against.
  @static_display_keys [:theme, :font_family, :font_size]

  @doc """
  Builds a new live kino that hosts `mod` (an `ExRatatui.App`).

  `opts` is split into [Display options](#module-display-options)
  consumed by the widget itself and [Mount options](#module-mount-options)
  forwarded verbatim to `c:ExRatatui.App.mount/1`. Reserved display
  keys never reach the App.

  ## Examples

      # Plain
      Kino.ExRatatui.new(Counter)

      # Mount opt forwarded to mount/1
      Kino.ExRatatui.new(Counter, start: 10)

      # Display opt + mount opt
      Kino.ExRatatui.new(Counter,
        start: 10,
        theme: %{background: "#0d1117", foreground: "#c9d1d9"},
        font_size: 14
      )
  """
  @spec new(module(), keyword()) :: KinoLive.t()
  def new(mod, opts \\ []) when is_atom(mod) and is_list(opts) do
    {display, mount_opts} = extract_display_opts(opts)
    KinoLive.new(__MODULE__, {mod, mount_opts, display})
  end

  @doc """
  Renders a one-shot static frame of widgets and returns a
  non-interactive `Kino.JS` widget that paints it once.

  Useful for documentation, screenshots in notebooks, or
  `Kino.Layout.grid([frame_a, frame_b, frame_c])` side-by-side
  comparisons. There is no event loop, no resize handling, and no
  runtime server — just an `ExRatatui.Session` rendered once and
  written to xterm.js.

  ## Options

    * `:cols` — terminal width in cells. Defaults to `#{@default_cols}`.
    * `:rows` — terminal height in cells. Defaults to `#{@default_rows}`.
    * `:theme` — see [Display options](#module-display-options). Same
      defaults as `new/2`.
    * `:font_family` — same.
    * `:font_size` — same.

  Live-only display opts (`:height`, `:cursor_blink`, `:scrollback`,
  `:stopped_message`) are not accepted here and will raise
  `ArgumentError` — they have nothing to apply against in a static
  one-shot frame.

  ## Examples

      iex> alias ExRatatui.Layout.Rect
      iex> alias ExRatatui.Widgets.{Block, Paragraph}
      iex> kino = Kino.ExRatatui.frame(
      ...>   [
      ...>     {%Paragraph{
      ...>        text: "Hello from a static frame!",
      ...>        block: %Block{title: "demo"}
      ...>      },
      ...>      %Rect{x: 0, y: 0, width: 40, height: 5}}
      ...>   ],
      ...>   cols: 40,
      ...>   rows: 5
      ...> )
      iex> kino.module
      Kino.ExRatatui
  """
  @spec frame([{ExRatatui.widget(), ExRatatui.Layout.Rect.t()}], keyword()) :: KinoJS.t()
  def frame(widgets, opts \\ []) when is_list(widgets) and is_list(opts) do
    {cols, rows, display} = extract_frame_opts(opts)

    session = Session.new(cols, rows)

    try do
      case Session.draw(session, widgets) do
        :ok ->
          bytes = Session.take_output(session)

          info =
            display
            |> Map.take(@static_display_keys)
            |> Map.merge(%{cols: cols, rows: rows, mode: "static"})

          KinoJS.new(__MODULE__, {:binary, info, bytes})

        {:error, reason} ->
          raise ArgumentError, "Kino.ExRatatui.frame/2: render failed — #{inspect(reason)}"
      end
    after
      :ok = Session.close(session)
    end
  end

  @doc """
  Sets global defaults applied to every subsequent `new/2` and
  `frame/2` call in the current runtime.

  Accepts the same keys as the [Display options](#module-display-options)
  on `new/2`. Each value is validated immediately (the same way it
  would be on `new/2`) — bad shapes raise `ArgumentError`.

  Per-instance opts on `new/2` / `frame/2` still win key-by-key.
  Calling `configure/1` again merges into the existing config rather
  than replacing it, so related settings can be split across cells.

  Returns `:ok`.

  ## Examples

      # Reactively follow Livebook's light/dark mode and bump the font.
      Kino.ExRatatui.configure(theme: :livebook, font_size: 14)

      # Per-instance overrides still apply. This call uses the configured
      # font_size: 14 but a custom theme.
      Kino.ExRatatui.new(Counter, theme: %{background: "#000"})

  Stored under the `:kino_ex_ratatui` Application environment, so the
  same value is also reachable via `Application.get_all_env(:kino_ex_ratatui)`
  when orchestrating from a release `config/runtime.exs` or any
  other `Config`-driven setup.
  """
  @spec configure(keyword()) :: :ok
  def configure(opts) when is_list(opts) do
    Enum.each(opts, fn {key, value} ->
      validated =
        if key in @display_keys do
          validate_display_opt!(key, value)
        else
          raise ArgumentError,
                "Kino.ExRatatui.configure/1: unknown option `#{inspect(key)}`. " <>
                  "Supported: #{inspect(@display_keys)}"
        end

      Application.put_env(:kino_ex_ratatui, key, validated)
    end)

    :ok
  end

  ## Kino.JS.Live callbacks

  @impl true
  def init({mod, mount_opts, display}, ctx) do
    {:ok,
     assign(ctx,
       mod: mod,
       mount_opts: mount_opts,
       display: display,
       session: nil,
       server: nil,
       server_ref: nil
     )}
  end

  @impl true
  def handle_connect(ctx) do
    # JS side drives initialization — it sends a "resize" event with the
    # cell dimensions reported by FitAddon as soon as it's mounted, and
    # that's what boots the Session + runtime server. The payload here
    # carries the display config so the JS hook can theme/size xterm.js
    # before that first resize fires.
    {:ok, ctx.assigns.display, ctx}
  end

  @impl true
  def handle_event("resize", %{"cols" => cols, "rows" => rows}, ctx)
      when is_integer(cols) and cols > 0 and is_integer(rows) and rows > 0 do
    case ctx.assigns.session do
      nil -> {:noreply, start_runtime(ctx, cols, rows)}
      session -> {:noreply, forward_resize(ctx, session, cols, rows)}
    end
  end

  def handle_event("input", {:binary, _info, bytes}, ctx) when is_binary(bytes) do
    case ctx.assigns do
      %{session: nil} ->
        # Input arrived before the first resize. Drop it — the Session
        # doesn't exist yet, and xterm.js will replay nothing.
        {:noreply, ctx}

      %{session: session, server: server, mod: mod} ->
        Telemetry.execute([:input, :forward], %{}, %{mod: mod, byte_count: byte_size(bytes)})
        _ = ByteStream.forward_input(session, server, bytes)
        {:noreply, ctx}
    end
  end

  @impl true
  def handle_info({:DOWN, ref, :process, _pid, reason}, ctx)
      when ref == ctx.assigns.server_ref do
    # App quit (`{:stop, state}`, `mount/1` failed, …). Tell the JS
    # hook to render an accessible DOM overlay over the xterm
    # container so the user sees a clean "re-evaluate the cell" hint
    # — and so screen readers announce it via aria-live — instead of
    # the frozen final frame with the cursor sitting on it. Then
    # drop the server refs so terminate/2 doesn't try to stop a dead
    # process.
    Telemetry.execute([:transport, :disconnect], %{}, %{mod: ctx.assigns.mod, reason: reason})

    broadcast_event(ctx, "stopped", %{message: ctx.assigns.display.stopped_message})

    {:noreply, assign(ctx, session: nil, server: nil, server_ref: nil)}
  end

  def handle_info(_msg, ctx), do: {:noreply, ctx}

  @impl true
  def terminate(reason, ctx) do
    # Only fire disconnect from terminate when the runtime hasn't
    # already exited via :DOWN — that handler clears `:server` to nil
    # and we'd double-emit otherwise.
    case ctx.assigns.server do
      nil ->
        :ok

      pid ->
        if Process.alive?(pid) do
          Telemetry.execute([:transport, :disconnect], %{}, %{
            mod: ctx.assigns.mod,
            reason: reason
          })

          GenServer.stop(pid, :shutdown)
        else
          :ok
        end
    end
  end

  ## Helpers

  defp start_runtime(ctx, cols, rows) do
    Telemetry.span(
      [:transport, :connect],
      %{mod: ctx.assigns.mod, width: cols, height: rows},
      fn -> do_start_runtime(ctx, cols, rows) end
    )
  end

  defp do_start_runtime(ctx, cols, rows) do
    session = Session.new(cols, rows)
    mod = ctx.assigns.mod

    writer = fn bytes ->
      binary = IO.iodata_to_binary(bytes)

      Telemetry.span(
        [:render, :frame],
        %{mod: mod, byte_count: byte_size(binary)},
        fn -> broadcast_event(ctx, "ansi", {:binary, %{}, binary}) end
      )
    end

    opts =
      ctx.assigns.mount_opts
      |> Keyword.put(:mod, mod)
      |> Keyword.put(:name, nil)
      |> Keyword.put(:transport, {:session, session, writer})

    {:ok, server} = Transport.start_server(opts)

    ref = Process.monitor(server)
    assign(ctx, session: session, server: server, server_ref: ref)
  end

  defp forward_resize(ctx, session, cols, rows) do
    Telemetry.execute([:resize], %{}, %{mod: ctx.assigns.mod, width: cols, height: rows})
    ByteStream.forward_resize(session, ctx.assigns.server, cols, rows)
    ctx
  end

  ## Display options

  # Splits user opts into {display_map, mount_opts_keyword}. Reserved
  # display + runtime keys are stripped from the keyword list before it
  # reaches `App.mount/1` — apps never see them as mount opts.
  defp extract_display_opts(opts) do
    display = build_display_map(opts)

    mount_opts =
      Enum.reject(opts, fn {k, _v} ->
        k in @display_keys or k in @reserved_runtime_keys
      end)

    {display, mount_opts}
  end

  # frame/2 is non-live, so it accepts only `:cols`, `:rows`, and the
  # static-mode-friendly subset of display opts. Anything else
  # (`:height`, `:cursor_blink`, `:scrollback`, `:stopped_message`,
  # plus arbitrary mount-opt-like keys) raises so callers don't
  # silently lose configuration. `:mode` is reserved for the JS payload
  # discriminator.
  defp extract_frame_opts(opts) do
    valid_keys = [:cols, :rows | @static_display_keys]

    case Enum.find(opts, fn {k, _v} -> k not in valid_keys end) do
      nil ->
        cols = validate_dim!(:cols, Keyword.get(opts, :cols, @default_cols))
        rows = validate_dim!(:rows, Keyword.get(opts, :rows, @default_rows))
        display = build_display_map(opts)
        {cols, rows, display}

      {bad_key, _} ->
        raise ArgumentError,
              "Kino.ExRatatui.frame/2: unknown option `#{inspect(bad_key)}`. " <>
                "Supported: #{inspect(valid_keys)}"
    end
  end

  defp validate_dim!(_key, value) when is_integer(value) and value > 0, do: value

  defp validate_dim!(key, value) do
    raise ArgumentError,
          "Kino.ExRatatui.frame/2: `#{inspect(key)}` must be a positive integer, " <>
            "got: #{inspect(value)}"
  end

  defp build_display_map(opts) do
    # Merge order, key-by-key: per-instance opts > Application env >
    # module defaults. Values from configure/1 are already validated
    # (configure/1 ran the validator before calling put_env), but
    # we re-validate per-instance values at the call site.
    app_env = Application.get_all_env(:kino_ex_ratatui)

    Enum.reduce(@display_keys, @default_display, fn key, acc ->
      cond do
        Keyword.has_key?(opts, key) ->
          Map.put(acc, key, validate_display_opt!(key, Keyword.fetch!(opts, key)))

        Keyword.has_key?(app_env, key) ->
          Map.put(acc, key, Keyword.fetch!(app_env, key))

        true ->
          acc
      end
    end)
  end

  # Per-key validation. Each clause raises ArgumentError with a clear
  # message naming the offending option — mirrors the per-widget
  # validation pattern used in ex_ratatui's bridge.
  defp validate_display_opt!(:theme, value) when is_map(value), do: value

  defp validate_display_opt!(:theme, value) when value in [:dark, :light, :livebook],
    do: value

  defp validate_display_opt!(:font_family, value) when is_binary(value) and byte_size(value) > 0,
    do: value

  defp validate_display_opt!(:font_size, value) when is_integer(value) and value > 0, do: value

  defp validate_display_opt!(:height, value) when is_binary(value) and byte_size(value) > 0,
    do: value

  defp validate_display_opt!(:cursor_blink, value) when is_boolean(value), do: value
  defp validate_display_opt!(:scrollback, value) when is_integer(value) and value >= 0, do: value
  defp validate_display_opt!(:stopped_message, value) when is_binary(value), do: value

  defp validate_display_opt!(key, value) do
    raise ArgumentError,
          "Kino.ExRatatui: invalid value for `#{inspect(key)}`: #{inspect(value)}. " <>
            "See the moduledoc for the expected shape."
  end
end
