# KinoExRatatui

[![Hex.pm](https://img.shields.io/hexpm/v/kino_ex_ratatui.svg)](https://hex.pm/packages/kino_ex_ratatui)
[![Docs](https://img.shields.io/badge/hex-docs-blue)](https://hexdocs.pm/kino_ex_ratatui)
[![License](https://img.shields.io/hexpm/l/kino_ex_ratatui.svg)](https://github.com/mcass19/kino_ex_ratatui/blob/main/LICENSE)

Run [ExRatatui](https://github.com/mcass19/ex_ratatui) apps inside [Livebook](https://livebook.dev) notebooks via xterm.js.

The same `ExRatatui.App` module that runs over the local tty, SSH, or Erlang distribution now runs in a notebook cell. `KinoExRatatui` is a byte-stream transport that pipes the runtime's rendered ANSI through xterm.js and forwards keypresses and resize events back — implemented as a `~150` line `Kino.JS.Live` widget on top of `ExRatatui.Transport.ByteStream`.

## Features

- **Same App, same surface** — any module implementing `ExRatatui.App` runs unchanged. No notebook-flavored "dialect" of ExRatatui.
- **Responsive sizing** — xterm.js's `FitAddon` derives cell dimensions and reports resize events; the App sees them as `%ExRatatui.Event.Resize{}` in `handle_event/2`.
- **Static frames** — `Kino.ExRatatui.frame/2` renders a one-shot `[{widget, rect}, ...]` list and ships the bytes to xterm.js. Useful for documentation, side-by-side comparisons via `Kino.Layout.grid/1`, and screenshots.
- **Zero browser-side state on cell re-eval** — re-running the cell tears the runtime down and starts a fresh one, matching every other `Kino.JS.Live` widget.
- **Tested end-to-end** — 22 lifecycle / message-contract tests using `Kino.Test`, 100% coverage.

## Installation

Add `kino_ex_ratatui` to your Livebook setup cell (or your project's `mix.exs`):

```elixir
Mix.install([
  {:kino_ex_ratatui, "~> 0.1"}
])
```

That's it. The package ships its xterm.js bundle precompiled, so no Node toolchain is needed at install time.

### Prerequisites

- Elixir 1.17+
- Livebook 0.13+ (the modern asset story used here landed in that version)

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

The full notebook lives at [`livebook/counter.livemd`](livebook/counter.livemd) — open it in Livebook and run the cells.

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

`KinoExRatatui` implements `ExRatatui.Transport` as a byte-stream transport — the same shape as the built-in SSH transport and the [TCP example in the Custom Transports guide](https://hexdocs.pm/ex_ratatui/custom_transports.html). The wiring:

```
xterm.js (iframe)            Kino.ExRatatui (Kino.JS.Live)         ExRatatui.Server
─────────────────            ─────────────────────────────         ────────────────
onData(bytes)         ──>    handle_event("input", _)        ──>   {:ex_ratatui_event, _}
ResizeObserver        ──>    handle_event("resize", _)       ──>   {:ex_ratatui_resize, _, _}
xterm.write(bytes)    <──    broadcast_event("ansi", _)      <──   writer_fn.(bytes)
```

The runtime server starts lazily on the first `"resize"` event so the `ExRatatui.Session` opens at the exact dimensions xterm.js's FitAddon settled on. From there, input bytes round-trip through `ExRatatui.Transport.ByteStream.forward_input/3` (which absorbs synthesized `Event.Resize` events and dispatches everything else as `{:ex_ratatui_event, _}`). When the App returns `{:stop, _}`, the live widget catches the runtime's `:DOWN` and broadcasts the alt-screen leave sequence so xterm.js restores its cursor.

If you want to write your own transport, the [Custom Transports guide](https://hexdocs.pm/ex_ratatui/custom_transports.html) walks through the contract in full.

## Sister projects

- [ex_ratatui](https://github.com/mcass19/ex_ratatui) — the underlying Elixir bindings to Rust ratatui
- [ash_tui](https://github.com/mcass19/ash_tui) — terminal explorer for Ash Framework
- [nerves_ex_ratatui_example](https://github.com/mcass19/nerves_ex_ratatui_example) — TUIs on embedded hardware
- [phoenix_ex_ratatui_example](https://github.com/mcass19/phoenix_ex_ratatui_example) — TUIs alongside Phoenix LiveView

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md) for setup, the JS bundling story, and how to run the test suite.

## License

MIT — see [LICENSE](https://github.com/mcass19/kino_ex_ratatui/blob/main/LICENSE).
