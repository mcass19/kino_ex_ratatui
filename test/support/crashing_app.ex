defmodule KinoExRatatui.Test.CrashingMount do
  @moduledoc """
  `ExRatatui.App` whose `mount/1` always returns `{:error, _}`. Used by
  `Kino.ExRatatuiTest` to verify the live widget surfaces App startup
  failures via the live server's exit.
  """

  use ExRatatui.App

  alias ExRatatui.Layout.Rect
  alias ExRatatui.Widgets.Paragraph

  @impl true
  def mount(_opts), do: {:error, :boom}

  @impl true
  def render(_state, frame) do
    [{%Paragraph{text: ""}, %Rect{x: 0, y: 0, width: frame.width, height: frame.height}}]
  end

  @impl true
  def handle_event(_event, state), do: {:noreply, state}
end
