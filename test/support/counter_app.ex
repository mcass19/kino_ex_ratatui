defmodule KinoExRatatui.Test.Counter do
  @moduledoc """
  Minimal `ExRatatui.App` used by tests and the canonical Livebook example.

  Keys:

    * `+` — increment
    * `-` — decrement
    * `q` — quit
  """

  use ExRatatui.App

  alias ExRatatui.Event.Key
  alias ExRatatui.Layout.Rect
  alias ExRatatui.Widgets.{Block, Paragraph}

  @impl true
  def mount(_opts), do: {:ok, %{n: 0}}

  @impl true
  def render(state, frame) do
    [
      {%Paragraph{
         text: "Count: #{state.n}\n\n+ increment   - decrement   q quit",
         block: %Block{title: "kino_ex_ratatui counter"}
       }, %Rect{x: 0, y: 0, width: frame.width, height: frame.height}}
    ]
  end

  @impl true
  def handle_event(%Key{code: "+"}, state), do: {:noreply, %{state | n: state.n + 1}}
  def handle_event(%Key{code: "-"}, state), do: {:noreply, %{state | n: state.n - 1}}
  def handle_event(%Key{code: "q"}, state), do: {:stop, state}
  def handle_event(_event, state), do: {:noreply, state}
end
