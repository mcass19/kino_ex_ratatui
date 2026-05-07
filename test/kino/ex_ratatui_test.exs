defmodule Kino.ExRatatuiTest do
  use ExUnit.Case, async: true

  import ExUnit.CaptureLog
  import Kino.Test

  alias ExRatatui.Runtime
  alias Kino.JS.DataStore
  alias KinoExRatatui.Test.{Counter, CrashingMount}

  doctest Kino.ExRatatui

  setup :configure_livebook_bridge

  # Clean up the kino's GenServer at the end of each test so server pids
  # (and the Rust-side Sessions they own) don't leak across the suite.
  defp on_exit_stop(kino) do
    on_exit(fn ->
      if Process.alive?(kino.pid), do: GenServer.stop(kino.pid, :shutdown)
    end)
  end

  defp assigns(kino), do: :sys.get_state(kino.pid).ctx.assigns

  defp boot(mount_opts \\ [], cols \\ 80, rows \\ 24) do
    kino = Kino.ExRatatui.new(Counter, mount_opts)
    on_exit_stop(kino)
    push_event(kino, "resize", %{"cols" => cols, "rows" => rows})
    # Synchronize: ensure the resize has been processed before the test
    # inspects assigns. :sys.get_state flushes the mailbox by virtue of
    # being a synchronous call.
    _ = :sys.get_state(kino.pid)
    kino
  end

  describe "new/2 — initial state" do
    test "starts a Kino.JS.Live widget without booting the runtime server" do
      kino = Kino.ExRatatui.new(Counter)
      on_exit_stop(kino)

      assert %Kino.JS.Live{module: Kino.ExRatatui, pid: pid} = kino
      assert is_pid(pid) and Process.alive?(pid)

      assigns = assigns(kino)
      assert assigns.mod == Counter
      assert assigns.mount_opts == []
      assert assigns.session == nil
      assert assigns.server == nil
      assert assigns.server_ref == nil
    end

    test "stores caller-supplied mount_opts verbatim in assigns" do
      kino = Kino.ExRatatui.new(Counter, start: 10, label: "demo")
      on_exit_stop(kino)

      assert assigns(kino).mount_opts == [start: 10, label: "demo"]
    end

    test "strips reserved display + runtime keys from mount_opts" do
      kino =
        Kino.ExRatatui.new(Counter,
          start: 10,
          font_size: 14,
          height: "600px",
          theme: %{background: "#000"},
          name: :ignored,
          transport: :ignored
        )

      on_exit_stop(kino)

      # Only non-reserved keys reach the App's mount_opts.
      assert assigns(kino).mount_opts == [start: 10]
    end

    test "handle_connect returns the display payload" do
      kino = Kino.ExRatatui.new(Counter)
      on_exit_stop(kino)

      payload = connect(kino)

      assert is_map(payload)
      assert payload.font_size == 13
      assert payload.height == "400px"
      assert payload.cursor_blink == true
      assert is_binary(payload.font_family)
      assert is_map(payload.theme)
      assert is_binary(payload.stopped_message)
    end
  end

  describe "first resize event" do
    test "boots a Session at the reported dimensions and starts the runtime server" do
      kino = boot([], 100, 30)
      assigns = assigns(kino)

      assert %ExRatatui.Session{} = assigns.session
      assert is_pid(assigns.server)
      assert Process.alive?(assigns.server)
      assert is_reference(assigns.server_ref)
      assert ExRatatui.Session.size(assigns.session) == {100, 30}
    end

    test "runtime server reports matching dimensions via Runtime.snapshot/1" do
      kino = boot([], 80, 24)
      snapshot = Runtime.snapshot(assigns(kino).server)

      assert snapshot.mod == Counter
      assert snapshot.transport == :session
      assert snapshot.dimensions == {80, 24}
    end

    test "the runtime's writer_fn broadcasts the first frame as an ansi event" do
      kino = boot()

      assert_broadcast_event(kino, "ansi", {:binary, %{}, bytes})
      assert is_binary(bytes)
      assert byte_size(bytes) > 0
    end
  end

  describe "subsequent resize events" do
    test "forwards to ByteStream.forward_resize/4 without restarting the runtime" do
      kino = boot([], 80, 24)
      original_server = assigns(kino).server

      push_event(kino, "resize", %{"cols" => 120, "rows" => 40})
      _ = :sys.get_state(kino.pid)

      assigns = assigns(kino)
      assert assigns.server == original_server
      assert ExRatatui.Session.size(assigns.session) == {120, 40}
      assert Runtime.snapshot(assigns.server).dimensions == {120, 40}
    end
  end

  describe "input events" do
    test "forwards bytes to ByteStream.forward_input/3 and triggers a re-render" do
      kino = boot()

      assert_broadcast_event(kino, "ansi", {:binary, %{}, first_frame})

      push_event(kino, "input", {:binary, %{}, "+"})
      assert_broadcast_event(kino, "ansi", {:binary, %{}, second_frame})

      assert is_binary(second_frame)
      assert byte_size(second_frame) > 0
      # The frame after `+` reflects "Count: 1" instead of "Count: 0",
      # so the rendered byte payloads must differ.
      assert second_frame != first_frame
    end

    test "input arriving before the first resize is silently dropped" do
      kino = Kino.ExRatatui.new(Counter)
      on_exit_stop(kino)

      push_event(kino, "input", {:binary, %{}, "+"})
      _ = :sys.get_state(kino.pid)

      assert Process.alive?(kino.pid)
      assigns = assigns(kino)
      assert assigns.session == nil
      assert assigns.server == nil
    end
  end

  describe "server DOWN" do
    test "broadcasts a 'stopped' event with the configured message and clears server refs" do
      kino = boot()

      # Drain the initial render's broadcast so the stopped-state event
      # is the next one we capture.
      assert_broadcast_event(kino, "ansi", {:binary, %{}, _initial})

      push_event(kino, "input", {:binary, %{}, "q"})

      # The Counter App returns {:stop, state} on `q`, so the runtime
      # server exits :normal and handle_info/2 fires. The widget
      # broadcasts a structured "stopped" event with the configured
      # `:stopped_message`; the JS hook renders it as a `role="status"`
      # DOM overlay so screen readers announce it and sighted users
      # see a clean hint instead of the frozen final frame.
      assert_broadcast_event(kino, "stopped", payload, 500)
      assert is_map(payload)
      # The payload is a single-key map; the JS hook reads only :message
      # and feeds it to `textContent`. Pinning the shape keeps the wire
      # protocol stable across refactors of `handle_info(:DOWN)`.
      assert Map.keys(payload) == [:message]
      assert payload.message =~ "re-evaluate"

      _ = :sys.get_state(kino.pid)
      assigns = assigns(kino)
      assert assigns.session == nil
      assert assigns.server == nil
      assert assigns.server_ref == nil
    end

    test "the 'stopped' event is NOT a binary payload — it's a plain map for the JS hook" do
      # Defensive pin: the JS hook switched from rendering ANSI bytes
      # in the buffer to a DOM overlay reading payload.message. If a
      # future refactor sends bytes again, this assertion catches it
      # before the overlay silently breaks.
      kino = boot()
      assert_broadcast_event(kino, "ansi", {:binary, %{}, _initial})

      push_event(kino, "input", {:binary, %{}, "q"})
      assert_broadcast_event(kino, "stopped", payload, 500)

      refute match?({:binary, _, _}, payload)
    end
  end

  describe "terminate/2" do
    test "stops the runtime server when the live widget shuts down" do
      kino = boot()
      server = assigns(kino).server
      ref = Process.monitor(server)

      GenServer.stop(kino.pid, :shutdown)

      assert_receive {:DOWN, ^ref, :process, ^server, _reason}, 500
    end

    test "is a no-op when no runtime server was ever started" do
      kino = Kino.ExRatatui.new(Counter)
      ref = Process.monitor(kino.pid)
      GenServer.stop(kino.pid, :shutdown)

      assert_receive {:DOWN, ^ref, :process, _, _}, 500
    end
  end

  describe "unrelated handle_info messages" do
    test "are silently ignored without crashing the live widget" do
      kino = Kino.ExRatatui.new(Counter)
      on_exit_stop(kino)

      send(kino.pid, :some_unrelated_message)
      send(kino.pid, {:some, :other, :tuple})
      _ = :sys.get_state(kino.pid)

      assert Process.alive?(kino.pid)
    end
  end

  describe "Kino.JS asset info" do
    test "__assets_info__/0 returns the bundle metadata Kino renders with" do
      info = Kino.ExRatatui.__assets_info__()

      assert is_map(info)
      assert info.js_path == "main.js"
      assert is_binary(info.hash)
      assert is_binary(info.archive_path)
    end
  end

  describe "App.mount/1 failure" do
    test "the live widget exits when start_server/1 returns {:error, _}" do
      Process.flag(:trap_exit, true)

      # The runtime's internal Task.Supervisor dies via the linked
      # {:EXIT, _, :boom} signal and logs an error before going down.
      # Capture the log so the noise doesn't pollute the suite output.
      capture_log(fn ->
        kino = Kino.ExRatatui.new(CrashingMount)

        # Don't on_exit_stop — the resize we're about to push will
        # crash the live widget before the test body finishes.
        ref = Process.monitor(kino.pid)
        push_event(kino, "resize", %{"cols" => 80, "rows" => 24})

        assert_receive {:DOWN, ^ref, :process, _, _reason}, 500
      end)
    end
  end

  describe "display options" do
    test "defaults are applied when no display opts are given" do
      kino = Kino.ExRatatui.new(Counter)
      on_exit_stop(kino)

      display = assigns(kino).display

      assert display.font_size == 13
      assert display.height == "400px"
      assert display.cursor_blink == true
      assert display.scrollback == 1000
      assert String.contains?(display.font_family, "monospace")
      assert display.theme.background == "#1e1e2e"
      assert display.stopped_message =~ "re-evaluate"
    end

    test "user-supplied display opts override defaults and merge into the payload" do
      kino =
        Kino.ExRatatui.new(Counter,
          theme: %{background: "#0d1117", foreground: "#c9d1d9"},
          font_family: "Fira Code, monospace",
          font_size: 14,
          height: "600px",
          cursor_blink: false,
          scrollback: 5000,
          stopped_message: "Bye!"
        )

      on_exit_stop(kino)

      display = assigns(kino).display
      assert display.font_size == 14
      assert display.height == "600px"
      assert display.cursor_blink == false
      assert display.scrollback == 5000
      assert display.font_family == "Fira Code, monospace"
      assert display.theme == %{background: "#0d1117", foreground: "#c9d1d9"}
      assert display.stopped_message == "Bye!"

      # And the JS hook sees the same payload.
      assert connect(kino) == display
    end

    test "custom :stopped_message flows into the 'stopped' event payload on server :DOWN" do
      custom = "byebye-#{:rand.uniform(99_999)}"
      kino = Kino.ExRatatui.new(Counter, stopped_message: custom)
      on_exit_stop(kino)

      push_event(kino, "resize", %{"cols" => 80, "rows" => 24})
      assert_broadcast_event(kino, "ansi", {:binary, %{}, _initial})

      push_event(kino, "input", {:binary, %{}, "q"})

      assert_broadcast_event(kino, "stopped", %{message: ^custom}, 500)
      refute custom =~ "re-evaluate"
    end

    test "validation: :theme must be a map or :dark / :light / :livebook" do
      assert_raise ArgumentError, ~r/`:theme`: :neon/, fn ->
        Kino.ExRatatui.new(Counter, theme: :neon)
      end
    end

    test "validation: :font_family must be a non-empty binary" do
      assert_raise ArgumentError, ~r/`:font_family`/, fn ->
        Kino.ExRatatui.new(Counter, font_family: "")
      end
    end

    test "validation: :font_size must be a positive integer" do
      assert_raise ArgumentError, ~r/`:font_size`/, fn ->
        Kino.ExRatatui.new(Counter, font_size: 0)
      end
    end

    test "validation: :height must be a non-empty binary" do
      assert_raise ArgumentError, ~r/`:height`/, fn ->
        Kino.ExRatatui.new(Counter, height: 400)
      end
    end

    test "validation: :cursor_blink must be a boolean" do
      assert_raise ArgumentError, ~r/`:cursor_blink`/, fn ->
        Kino.ExRatatui.new(Counter, cursor_blink: "yes")
      end
    end

    test "validation: :scrollback must be a non-negative integer" do
      assert_raise ArgumentError, ~r/`:scrollback`/, fn ->
        Kino.ExRatatui.new(Counter, scrollback: -1)
      end
    end

    test "validation: :stopped_message must be a binary" do
      assert_raise ArgumentError, ~r/`:stopped_message`/, fn ->
        Kino.ExRatatui.new(Counter, stopped_message: nil)
      end
    end
  end

  describe "frame/2 display options" do
    defp simple_widgets do
      [
        {%ExRatatui.Widgets.Paragraph{text: "hi"},
         %ExRatatui.Layout.Rect{x: 0, y: 0, width: 10, height: 1}}
      ]
    end

    # Static `Kino.JS` widgets have no `:pid` field, so `Kino.Test.connect/2`
    # doesn't work. Roll our own: the payload lives in `Kino.JS.DataStore`,
    # which speaks the same `{:connect, _, %{ref, origin}}` protocol the live
    # widget speaks.
    defp connect_static(%Kino.JS{ref: ref}) do
      pid = DataStore.cross_node_name()
      send(pid, {:connect, self(), %{ref: ref, origin: inspect(self())}})
      assert_receive {:connect_reply, data, %{ref: ^ref}}, 200
      data
    end

    test "merges :theme / :font_family / :font_size into the static info map" do
      kino =
        Kino.ExRatatui.frame(simple_widgets(),
          cols: 40,
          rows: 5,
          theme: %{background: "#000"},
          font_family: "Fira Code, monospace",
          font_size: 16
        )

      assert {:binary, info, _bytes} = connect_static(kino)
      assert info.cols == 40
      assert info.rows == 5
      assert info.mode == "static"
      assert info.theme == %{background: "#000"}
      assert info.font_family == "Fira Code, monospace"
      assert info.font_size == 16
    end

    test "without display opts the info map carries only cols/rows/mode + defaults" do
      kino = Kino.ExRatatui.frame(simple_widgets(), cols: 40, rows: 5)

      assert {:binary, info, _bytes} = connect_static(kino)
      # The static-friendly subset of defaults always rides along so JS
      # doesn't have to special-case the absent-config path.
      assert info.cols == 40
      assert info.rows == 5
      assert info.mode == "static"
      assert is_map(info.theme)
      assert is_binary(info.font_family)
      assert is_integer(info.font_size)
    end

    test "rejects live-only display opts" do
      assert_raise ArgumentError, ~r/unknown option `:height`/, fn ->
        Kino.ExRatatui.frame(simple_widgets(), height: "600px")
      end

      assert_raise ArgumentError, ~r/unknown option `:cursor_blink`/, fn ->
        Kino.ExRatatui.frame(simple_widgets(), cursor_blink: false)
      end
    end

    test "rejects unknown opts (catches typos in :col vs :cols)" do
      assert_raise ArgumentError, ~r/unknown option `:col`/, fn ->
        Kino.ExRatatui.frame(simple_widgets(), col: 40)
      end
    end

    test "validates :cols / :rows are positive integers" do
      assert_raise ArgumentError, ~r/`:cols` must be a positive integer/, fn ->
        Kino.ExRatatui.frame(simple_widgets(), cols: 0)
      end

      assert_raise ArgumentError, ~r/`:rows` must be a positive integer/, fn ->
        Kino.ExRatatui.frame(simple_widgets(), rows: -1)
      end
    end

    test "validates :theme is a map or :dark / :light / :livebook" do
      assert_raise ArgumentError, ~r/`:theme`: :neon/, fn ->
        Kino.ExRatatui.frame(simple_widgets(), theme: :neon)
      end
    end
  end

  describe "telemetry events" do
    test "[:transport, :connect] span fires around the lazy boot with mod/width/height" do
      attach_telemetry([
        [:kino_ex_ratatui, :transport, :connect, :start],
        [:kino_ex_ratatui, :transport, :connect, :stop]
      ])

      _kino = boot([], 100, 30)

      assert_received {:tel, [:kino_ex_ratatui, :transport, :connect, :start], _,
                       %{mod: Counter, width: 100, height: 30}}

      assert_received {:tel, [:kino_ex_ratatui, :transport, :connect, :stop], stop_meas,
                       %{mod: Counter, width: 100, height: 30}}

      assert is_integer(stop_meas[:duration])
    end

    test "[:render, :frame] span fires for every ANSI broadcast with byte_count" do
      attach_telemetry([[:kino_ex_ratatui, :render, :frame, :stop]])

      _kino = boot()

      assert_received {:tel, [:kino_ex_ratatui, :render, :frame, :stop], _measurements,
                       %{mod: Counter, byte_count: byte_count}}

      assert byte_count > 0
    end

    test "[:input, :forward] fires when bytes from xterm.js are forwarded" do
      attach_telemetry([[:kino_ex_ratatui, :input, :forward]])

      kino = boot()
      assert_broadcast_event(kino, "ansi", {:binary, %{}, _})
      push_event(kino, "input", {:binary, %{}, "+"})
      _ = :sys.get_state(kino.pid)

      assert_received {:tel, [:kino_ex_ratatui, :input, :forward], measurements,
                       %{mod: Counter, byte_count: 1}}

      assert is_integer(measurements[:system_time])
    end

    test "[:input, :forward] does NOT fire when input arrives before the first resize" do
      attach_telemetry([[:kino_ex_ratatui, :input, :forward]])

      kino = Kino.ExRatatui.new(Counter)
      on_exit_stop(kino)
      push_event(kino, "input", {:binary, %{}, "+"})
      _ = :sys.get_state(kino.pid)

      refute_received {:tel, [:kino_ex_ratatui, :input, :forward], _, _}
    end

    test "[:resize] fires on subsequent resizes (not the booting one)" do
      attach_telemetry([[:kino_ex_ratatui, :resize]])

      kino = boot([], 80, 24)
      # Boot resize is rolled into :transport, :connect, not :resize.
      refute_received {:tel, [:kino_ex_ratatui, :resize], _, _}

      push_event(kino, "resize", %{"cols" => 120, "rows" => 40})
      _ = :sys.get_state(kino.pid)

      assert_received {:tel, [:kino_ex_ratatui, :resize], _,
                       %{mod: Counter, width: 120, height: 40}}
    end

    test "[:transport, :disconnect] fires once on server :DOWN with the exit reason" do
      attach_telemetry([[:kino_ex_ratatui, :transport, :disconnect]])

      kino = boot()
      assert_broadcast_event(kino, "ansi", {:binary, %{}, _})

      # Counter returns {:stop, state} on `q`, which exits :normal.
      push_event(kino, "input", {:binary, %{}, "q"})
      assert_broadcast_event(kino, "stopped", %{message: _}, 500)

      assert_received {:tel, [:kino_ex_ratatui, :transport, :disconnect], _,
                       %{mod: Counter, reason: :normal}}

      # And we don't double-emit when terminate runs after the :DOWN
      # cleared the server refs.
      GenServer.stop(kino.pid, :shutdown)
      refute_received {:tel, [:kino_ex_ratatui, :transport, :disconnect], _, _}
    end

    test "[:transport, :disconnect] fires from terminate/2 when the runtime is still alive" do
      attach_telemetry([[:kino_ex_ratatui, :transport, :disconnect]])

      kino = boot()
      assert_broadcast_event(kino, "ansi", {:binary, %{}, _})

      GenServer.stop(kino.pid, :shutdown)

      assert_received {:tel, [:kino_ex_ratatui, :transport, :disconnect], _,
                       %{mod: Counter, reason: :shutdown}}
    end

    test "[:transport, :disconnect] does NOT fire when no runtime was ever booted" do
      attach_telemetry([[:kino_ex_ratatui, :transport, :disconnect]])

      kino = Kino.ExRatatui.new(Counter)
      GenServer.stop(kino.pid, :shutdown)

      refute_received {:tel, [:kino_ex_ratatui, :transport, :disconnect], _, _}
    end
  end

  defp attach_telemetry(events) do
    handler_id = "kino-test-#{System.unique_integer([:positive])}"

    :ok = :telemetry.attach_many(handler_id, events, &__MODULE__.__forward_telemetry__/4, self())

    on_exit(fn -> :telemetry.detach(handler_id) end)
  end

  @doc false
  def __forward_telemetry__(event, measurements, metadata, parent) do
    send(parent, {:tel, event, measurements, metadata})
  end
end
