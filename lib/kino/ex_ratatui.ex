defmodule Kino.ExRatatui do
  @moduledoc """
  Run an `ExRatatui.App` inside a Livebook notebook via xterm.js.

  Same `App` module runs unchanged over the local tty, SSH, BEAM
  distribution, and now Livebook — `Kino.ExRatatui` is a byte-stream
  transport that pipes the runtime server's rendered ANSI through an
  xterm.js iframe and forwards keypresses + resize events back.

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

  ## Options

  The second argument is a keyword list passed straight to
  `c:ExRatatui.App.mount/1`. Use it for any per-instance configuration
  your App reads from its mount opts. The keys `:mod`, `:name`, and
  `:transport` are reserved by the runtime and silently overwritten.

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
  reference shape — this module follows it almost line-for-line, swapping
  TCP callbacks for `Kino.JS.Live` callbacks.
  """

  use Kino.JS, assets_path: "lib/assets/kino_ex_ratatui"
  use Kino.JS.Live

  @behaviour ExRatatui.Transport

  alias ExRatatui.Session
  alias ExRatatui.Transport
  alias ExRatatui.Transport.ByteStream
  alias Kino.JS, as: KinoJS
  alias Kino.JS.Live, as: KinoLive

  # Same alt-screen pair `ExRatatui.SSH` emits on disconnect. Without
  # the leave sequence the xterm.js view would stay in the alt buffer
  # with the cursor hidden after the App quits.
  @leave_screen "\e[?1049l\e[?25h\e[0m"

  # Defaults for `frame/2`. Mirrors the canonical 80×24 terminal so
  # callers who just want a screenshot of a few widgets don't have to
  # think about sizing.
  @default_cols 80
  @default_rows 24

  @doc """
  Builds a new live kino that hosts `mod` (an `ExRatatui.App`).

  `mount_opts` is forwarded verbatim to `c:ExRatatui.App.mount/1`, so an
  App can do per-instance setup the same way it would over SSH.

  ## Examples

      Kino.ExRatatui.new(Counter)
      Kino.ExRatatui.new(Counter, start: 10, theme: :dark)
  """
  @spec new(module(), keyword()) :: KinoLive.t()
  def new(mod, mount_opts \\ []) when is_atom(mod) and is_list(mount_opts) do
    KinoLive.new(__MODULE__, {mod, mount_opts})
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

  ## Examples

      alias ExRatatui.Layout.Rect
      alias ExRatatui.Widgets.{Block, Paragraph}

      Kino.ExRatatui.frame(
        [
          {%Paragraph{
             text: "Hello from a static frame!",
             block: %Block{title: "demo"}
           },
           %Rect{x: 0, y: 0, width: 40, height: 5}}
        ],
        cols: 40,
        rows: 5
      )
  """
  @spec frame([{ExRatatui.widget(), ExRatatui.Layout.Rect.t()}], keyword()) :: KinoJS.t()
  def frame(widgets, opts \\ []) when is_list(widgets) and is_list(opts) do
    cols = Keyword.get(opts, :cols, @default_cols)
    rows = Keyword.get(opts, :rows, @default_rows)

    session = Session.new(cols, rows)

    try do
      case Session.draw(session, widgets) do
        :ok ->
          bytes = Session.take_output(session)
          KinoJS.new(__MODULE__, {:binary, %{cols: cols, rows: rows, mode: "static"}, bytes})

        {:error, reason} ->
          raise ArgumentError, "Kino.ExRatatui.frame/2: render failed — #{inspect(reason)}"
      end
    after
      :ok = Session.close(session)
    end
  end

  ## Kino.JS.Live callbacks

  @impl true
  def init({mod, mount_opts}, ctx) do
    {:ok,
     assign(ctx,
       mod: mod,
       mount_opts: mount_opts,
       session: nil,
       server: nil,
       server_ref: nil
     )}
  end

  @impl true
  def handle_connect(ctx) do
    # JS side drives initialization — it sends a "resize" event with the
    # cell dimensions reported by FitAddon as soon as it's mounted, and
    # that's what boots the Session + runtime server.
    {:ok, %{}, ctx}
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

      %{session: session, server: server} ->
        _ = ByteStream.forward_input(session, server, bytes)
        {:noreply, ctx}
    end
  end

  @impl true
  def handle_info({:DOWN, ref, :process, _pid, _reason}, ctx)
      when ref == ctx.assigns.server_ref do
    # App quit (`{:stop, state}`, `mount/1` failed, …). Flush the
    # leave-screen sequence so the iframe restores its cursor / main
    # buffer view, then drop the server refs so we don't try to stop a
    # dead process from terminate/2.
    broadcast_event(ctx, "ansi", {:binary, %{}, @leave_screen})
    {:noreply, assign(ctx, session: nil, server: nil, server_ref: nil)}
  end

  def handle_info(_msg, ctx), do: {:noreply, ctx}

  @impl true
  def terminate(_reason, ctx) do
    case ctx.assigns.server do
      nil -> :ok
      pid -> if Process.alive?(pid), do: GenServer.stop(pid, :shutdown), else: :ok
    end
  end

  ## Helpers

  defp start_runtime(ctx, cols, rows) do
    session = Session.new(cols, rows)

    writer = fn bytes ->
      broadcast_event(ctx, "ansi", {:binary, %{}, IO.iodata_to_binary(bytes)})
    end

    opts =
      ctx.assigns.mount_opts
      |> Keyword.put(:mod, ctx.assigns.mod)
      |> Keyword.put(:name, nil)
      |> Keyword.put(:transport, {:session, session, writer})

    {:ok, server} = Transport.start_server(opts)

    ref = Process.monitor(server)
    assign(ctx, session: session, server: server, server_ref: ref)
  end

  defp forward_resize(ctx, session, cols, rows) do
    ByteStream.forward_resize(session, ctx.assigns.server, cols, rows)
    ctx
  end
end
