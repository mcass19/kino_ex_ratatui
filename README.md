# KinoExRatatui

[![Hex.pm](https://img.shields.io/hexpm/v/kino_ex_ratatui.svg)](https://hex.pm/packages/kino_ex_ratatui)
[![Docs](https://img.shields.io/badge/hex-docs-blue)](https://hexdocs.pm/kino_ex_ratatui)
[![License](https://img.shields.io/hexpm/l/kino_ex_ratatui.svg)](https://github.com/mcass19/kino_ex_ratatui/blob/main/LICENSE)

Run [ExRatatui](https://github.com/mcass19/ex_ratatui) apps inside [Livebook](https://livebook.dev) notebooks.

The same `ExRatatui.App` module that runs over the local tty, SSH, or Erlang distribution now runs in a notebook cell. `KinoExRatatui` is a byte-stream transport that pipes the runtime's rendered ANSI through xterm.js and forwards keypresses and resize events back. Implemented as a `Kino.JS.Live` widget on top of `ExRatatui.Transport.ByteStream`.

## Features

- **Same App, same surface** — any module implementing `ExRatatui.App` runs unchanged.
- **Responsive sizing** — xterm.js's `FitAddon` derives cell dimensions and reports resize events; the App sees them as `%ExRatatui.Event.Resize{}` in `handle_event/2`.
- **Static frames** — `Kino.ExRatatui.frame/2` renders a one-shot `[{widget, rect}, ...]` list and ships the bytes to xterm.js. Useful for documentation, side-by-side comparisons via `Kino.Layout.grid/1`, and screenshots.
- **Zero browser-side state on cell re-eval** — re-running the cell tears the runtime down and starts a fresh one, matching every other `Kino.JS.Live` widget.

## Installation

Add `kino_ex_ratatui` to your Livebook setup cell (or your project's `mix.exs`):

```elixir
Mix.install([
  {:kino_ex_ratatui, "~> 0.1"}
])
```

### Prerequisites

- Elixir 1.17+
- Livebook 0.13+

## Quick Start

```elixir
defmodule Counter do
  use ExRatatui.App

  alias ExRatatui.Event.Key
  alias ExRatatui.Layout.Rect
  alias ExRatatui.Widgets.{Block, Paragraph}

  def mount(_), do: {:ok, %{n: 0}}

  def render(state, frame) do
    [
      {%Paragraph{
         text: "Count: #{state.n}\n\n+ increment   - decrement   q quit",
         block: %Block{title: "counter"}
       },
       %Rect{x: 0, y: 0, width: frame.width, height: frame.height}}
    ]
  end

  def handle_event(%Key{code: "+"}, s), do: {:noreply, %{s | n: s.n + 1}}
  def handle_event(%Key{code: "-"}, s), do: {:noreply, %{s | n: s.n - 1}}
  def handle_event(%Key{code: "q"}, s), do: {:stop, s}
  def handle_event(_, s),                do: {:noreply, s}
end

Kino.ExRatatui.new(Counter)
```

Three notebook examples live under [`examples/`](https://github.com/mcass19/kino_ex_ratatui/tree/main/examples) — open them in Livebook and run the cells:

- [`system_monitor.livemd`](https://github.com/mcass19/kino_ex_ratatui/blob/main/examples/system_monitor.livemd) — a callback-runtime dashboard with `Gauge` + `Table` that reads `/proc`, `/sys`, and BEAM stats every two seconds. Drop-in port of the [`ex_ratatui` example](https://github.com/mcass19/ex_ratatui/blob/main/examples/system_monitor.exs).
- [`chat_interface.livemd`](https://github.com/mcass19/kino_ex_ratatui/blob/main/examples/chat_interface.livemd) — a mock AI chat exercising `Markdown`, `Textarea`, `Throbber`, `Scrollbar`, and `/` slash-command autocomplete via a `Popup`.
- [`reducer_counter.livemd`](https://github.com/mcass19/kino_ex_ratatui/blob/main/examples/reducer_counter.livemd) — the same App contract written against the reducer runtime, plus a `Subscription.interval` that ticks the counter every second.

## Static frames

For documentation and side-by-side widget comparisons:

```elixir
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
```

`frame/2` renders the widget list once via `ExRatatui.Session`, ships the resulting ANSI to xterm.js, and stops. No event loop, no runtime server.

## How it works

`KinoExRatatui` implements `ExRatatui.Transport` as a byte-stream transport — the same shape as the built-in SSH transport. The wiring:

```
xterm.js (iframe)            Kino.ExRatatui (Kino.JS.Live)         ExRatatui.Server
─────────────────            ─────────────────────────────         ────────────────
onData(bytes)         ──>    handle_event("input", _)        ──>   {:ex_ratatui_event, _}
ResizeObserver        ──>    handle_event("resize", _)       ──>   {:ex_ratatui_resize, _, _}
xterm.write(bytes)    <──    broadcast_event("ansi", _)      <──   writer_fn.(bytes)
```

The runtime server starts lazily on the first `"resize"` event so the `ExRatatui.Session` opens at the exact dimensions xterm.js's FitAddon settled on. From there, input bytes round-trip through `ExRatatui.Transport.ByteStream.forward_input/3` (which absorbs synthesized `Event.Resize` events and dispatches everything else as `{:ex_ratatui_event, _}`). When the App returns `{:stop, _}`, the live widget catches the runtime's `:DOWN` and broadcasts a stop state message.

If you want to write your own transport, the [Custom Transports guide](https://hexdocs.pm/ex_ratatui/custom_transports.html) walks through the contract in full.

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md) for development setup and guidelines.

KinoExRatatui is built on [ExRatatui](https://github.com/mcass19/ex_ratatui), a general-purpose terminal UI library for Elixir. If you're interested in improving the underlying rendering, widgets, or layout engine, contributions to ExRatatui are very welcome as well.

## License

MIT — see [LICENSE](https://github.com/mcass19/kino_ex_ratatui/blob/main/LICENSE).
