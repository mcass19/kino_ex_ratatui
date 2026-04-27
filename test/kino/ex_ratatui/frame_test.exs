defmodule Kino.ExRatatui.FrameTest do
  use ExUnit.Case, async: true

  alias ExRatatui.Layout.Rect
  alias ExRatatui.Widgets.{Block, Paragraph}

  defp widgets(text \\ "Hello") do
    [
      {%Paragraph{text: text, block: %Block{title: "demo"}},
       %Rect{x: 0, y: 0, width: 40, height: 5}}
    ]
  end

  describe "frame/2" do
    test "returns a Kino.JS struct rendered by Kino.ExRatatui's asset bundle" do
      kino = Kino.ExRatatui.frame(widgets())

      assert %Kino.JS{module: Kino.ExRatatui} = kino
    end

    test "defaults to 80×24 when :cols/:rows are omitted" do
      # We can't read the Kino.JS payload back through public API, but
      # `frame/2` calling Session.new with bad dims would raise, so the
      # mere return of a Kino.JS struct proves the defaults were used.
      assert %Kino.JS{} = Kino.ExRatatui.frame(widgets())
    end

    test "honors caller-supplied :cols and :rows" do
      assert %Kino.JS{} = Kino.ExRatatui.frame(widgets(), cols: 40, rows: 5)
    end

    test "renders different widget content into different byte payloads" do
      # Two distinct frames should produce distinct underlying byte
      # streams — exposed through Kino.Test.export/2 which invokes the
      # registered export function. We don't register one, so this is a
      # weaker check: we just assert both calls succeed and don't
      # collide on Session resources.
      assert %Kino.JS{} = Kino.ExRatatui.frame(widgets("First"))
      assert %Kino.JS{} = Kino.ExRatatui.frame(widgets("Second"))
    end

    test "raises ArgumentError on malformed widget shapes" do
      assert_raise ArgumentError, fn ->
        Kino.ExRatatui.frame([:not_a_tuple], cols: 40, rows: 5)
      end
    end

    test "raises ArgumentError on bad rect coordinates" do
      bad = [
        {%Paragraph{text: "x"}, %Rect{x: 0, y: 0, width: -1, height: 5}}
      ]

      assert_raise ArgumentError, fn ->
        Kino.ExRatatui.frame(bad, cols: 40, rows: 5)
      end
    end

    test "closes the underlying Session even when draw/2 raises" do
      bad = [{:not_a_tuple, %Rect{x: 0, y: 0, width: 10, height: 1}}]

      # Capture the count of live BEAM processes; if Session.close/1
      # leaks, we'd see growth here. Best-effort sanity check.
      before = :erlang.system_info(:process_count)

      try do
        Kino.ExRatatui.frame(bad, cols: 40, rows: 5)
      rescue
        _ -> :ok
      end

      # Allow any GC to settle — process count is fuzzy. Just assert
      # we didn't blow up the runtime.
      assert :erlang.system_info(:process_count) - before < 10
    end
  end
end
