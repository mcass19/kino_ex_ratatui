defmodule Kino.ExRatatui.ConfigureTest do
  # async: false because configure/1 mutates the global Application
  # environment under :kino_ex_ratatui. Each test snapshots the env on
  # entry and restores it on exit so order is irrelevant.
  use ExUnit.Case, async: false

  alias Kino.JS.DataStore
  alias KinoExRatatui.Test.Counter

  setup do
    setup_livebook_bridge()

    # Snapshot every key configure/1 might touch, so on_exit can fully
    # restore state regardless of which keys this test (or a prior one
    # in the same suite using async: false) wrote.
    snapshot = Application.get_all_env(:kino_ex_ratatui)

    on_exit(fn ->
      # Wipe everything we might have set.
      for key <- known_keys() do
        Application.delete_env(:kino_ex_ratatui, key)
      end

      # Restore the snapshot.
      for {key, value} <- snapshot do
        Application.put_env(:kino_ex_ratatui, key, value)
      end
    end)
  end

  defp setup_livebook_bridge do
    Kino.Test.configure_livebook_bridge(%{})
    :ok
  end

  defp on_exit_stop(kino) do
    on_exit(fn ->
      if Process.alive?(kino.pid), do: GenServer.stop(kino.pid, :shutdown)
    end)
  end

  defp known_keys do
    [
      :theme,
      :font_family,
      :font_size,
      :height,
      :cursor_blink,
      :scrollback,
      :stopped_message
    ]
  end

  describe "configure/1" do
    test "stores values under :kino_ex_ratatui Application env" do
      :ok = Kino.ExRatatui.configure(theme: :livebook, font_size: 14)

      assert Application.get_env(:kino_ex_ratatui, :theme) == :livebook
      assert Application.get_env(:kino_ex_ratatui, :font_size) == 14
    end

    test "merges with prior calls — calling twice doesn't reset earlier keys" do
      :ok = Kino.ExRatatui.configure(font_size: 14)
      :ok = Kino.ExRatatui.configure(height: "600px")

      assert Application.get_env(:kino_ex_ratatui, :font_size) == 14
      assert Application.get_env(:kino_ex_ratatui, :height) == "600px"
    end

    test "validates each value the same way new/2 does" do
      assert_raise ArgumentError, ~r/`:font_size`/, fn ->
        Kino.ExRatatui.configure(font_size: 0)
      end

      assert_raise ArgumentError, ~r/`:theme`: :neon/, fn ->
        Kino.ExRatatui.configure(theme: :neon)
      end
    end

    test "rejects unknown keys" do
      assert_raise ArgumentError, ~r/unknown option `:not_a_key`/, fn ->
        Kino.ExRatatui.configure(not_a_key: "x")
      end
    end

    test "earlier valid keys persist when a later key fails validation" do
      # Single call with one good and one bad key. Behavior is
      # documented as left-to-right per-key validation, so the good
      # key lands before the bad one raises.
      assert_raise ArgumentError, fn ->
        Kino.ExRatatui.configure(font_size: 14, theme: :neon)
      end

      assert Application.get_env(:kino_ex_ratatui, :font_size) == 14
    end
  end

  describe "merge order at new/2" do
    test "Application env populates display when no per-instance opt is given" do
      :ok = Kino.ExRatatui.configure(theme: :livebook, font_size: 14, height: "600px")

      kino = Kino.ExRatatui.new(Counter)
      on_exit_stop(kino)

      display = :sys.get_state(kino.pid).ctx.assigns.display
      assert display.theme == :livebook
      assert display.font_size == 14
      assert display.height == "600px"
      # Untouched key falls through to the module default.
      assert display.cursor_blink == true
    end

    test "per-instance opts override Application env key-by-key" do
      :ok = Kino.ExRatatui.configure(theme: :livebook, font_size: 14)

      kino = Kino.ExRatatui.new(Counter, theme: %{background: "#000"})
      on_exit_stop(kino)

      display = :sys.get_state(kino.pid).ctx.assigns.display
      # :theme overridden per-instance.
      assert display.theme == %{background: "#000"}
      # :font_size still comes from configure/1.
      assert display.font_size == 14
    end

    test "per-instance validation runs even when configure/1 already set a value" do
      :ok = Kino.ExRatatui.configure(font_size: 14)

      assert_raise ArgumentError, ~r/`:font_size`/, fn ->
        Kino.ExRatatui.new(Counter, font_size: -1)
      end
    end
  end

  describe "merge order at frame/2" do
    alias ExRatatui.Layout.Rect
    alias ExRatatui.Widgets.Paragraph

    defp simple_widgets do
      [{%Paragraph{text: "hi"}, %Rect{x: 0, y: 0, width: 10, height: 1}}]
    end

    test "Application env supplies static-friendly opts to frame/2" do
      :ok = Kino.ExRatatui.configure(theme: :light, font_size: 18)

      kino = Kino.ExRatatui.frame(simple_widgets(), cols: 40, rows: 5)

      info = connect_static(kino)
      assert info.theme == :light
      assert info.font_size == 18
    end

    test "live-only configure values do NOT leak into frame/2's info map" do
      :ok = Kino.ExRatatui.configure(height: "800px", cursor_blink: false)

      kino = Kino.ExRatatui.frame(simple_widgets(), cols: 40, rows: 5)

      info = connect_static(kino)
      refute Map.has_key?(info, :height)
      refute Map.has_key?(info, :cursor_blink)
    end

    defp connect_static(%Kino.JS{ref: ref} = kino) do
      pid = DataStore.cross_node_name()
      send(pid, {:connect, self(), %{ref: ref, origin: inspect(self())}})
      assert_receive {:connect_reply, data, %{ref: ^ref}}, 200

      case data do
        {:binary, info, _bytes} -> info
        other -> flunk("unexpected payload from #{inspect(kino)}: #{inspect(other)}")
      end
    end
  end

  describe "atom theme shorthands" do
    test ":dark is accepted and threaded through to the display map" do
      kino = Kino.ExRatatui.new(Counter, theme: :dark)
      on_exit_stop(kino)
      assert :sys.get_state(kino.pid).ctx.assigns.display.theme == :dark
    end

    test ":light is accepted and threaded through to the display map" do
      kino = Kino.ExRatatui.new(Counter, theme: :light)
      on_exit_stop(kino)
      assert :sys.get_state(kino.pid).ctx.assigns.display.theme == :light
    end

    test ":livebook is accepted and threaded through to the display map" do
      kino = Kino.ExRatatui.new(Counter, theme: :livebook)
      on_exit_stop(kino)
      assert :sys.get_state(kino.pid).ctx.assigns.display.theme == :livebook
    end

    test "frame/2 accepts the same atom shorthands" do
      kino =
        Kino.ExRatatui.frame(
          [
            {%ExRatatui.Widgets.Paragraph{text: "x"},
             %ExRatatui.Layout.Rect{x: 0, y: 0, width: 5, height: 1}}
          ],
          cols: 10,
          rows: 1,
          theme: :light
        )

      assert %Kino.JS{module: Kino.ExRatatui} = kino
    end

    test "rejects atoms outside the recognised set" do
      assert_raise ArgumentError, ~r/`:theme`: :neon/, fn ->
        Kino.ExRatatui.new(Counter, theme: :neon)
      end
    end
  end
end
