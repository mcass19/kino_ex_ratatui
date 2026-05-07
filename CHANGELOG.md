# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- **Per-instance display options on `new/2` and `frame/2`.** Seven reserved opts now configure the xterm.js iframe per cell: `:theme` (full xterm.js [`ITheme`](https://xtermjs.org/docs/api/terminal/interfaces/itheme/) map — `background`, `foreground`, `cursor`, `cursorAccent`, `selectionBackground`, the 16-color ANSI palette, etc.), `:font_family` (CSS string), `:font_size` (px integer), `:height` (CSS length applied to the xterm container — accepts `"600px"`, `"60vh"`, `"calc(100vh - 200px)"`, …), `:cursor_blink` (boolean), `:scrollback` (non-negative integer), and `:stopped_message` (string painted into the iframe when the runtime exits via `{:stop, _}` or a mount failure). Defaults preserve the previous look exactly. Reserved keys are stripped from the keyword list before reaching `c:ExRatatui.App.mount/1`, so apps never see them as mount opts. Each value is validated at the call site — bad shapes raise `ArgumentError` with a message naming the offending option, never silently. `frame/2` accepts the static-friendly subset (`:theme`, `:font_family`, `:font_size`); live-only opts and unknown keys raise so typos like `col:` instead of `cols:` no longer go through silently. The display payload flows to the JS bundle via `handle_connect/1` (live mode) and the static info map (frame mode); the JS hook merges it onto its own copy of the defaults so out-of-band callers (custom payloads, future smart-cell variants) still get sensible values when only some opts are supplied. New [`examples/theming.livemd`](examples/theming.livemd) walks through every option — One Dark, Solarized Light, custom Fira Code at 16px, no-blink + custom stopped message, and a side-by-side static gallery via `Kino.Layout.grid/1` of three theme variants on the same widget tree.

- **`Kino.ExRatatui.Telemetry` — `:telemetry` integration.** Mirrors the shape of [`ExRatatui.Telemetry`](https://hexdocs.pm/ex_ratatui/ExRatatui.Telemetry.html) one layer up, emitting events at the boundaries this widget controls so consumers can plug in logging, metrics, or distributed tracing without reaching into the runtime. Two span events (`[:kino_ex_ratatui, :transport, :connect]` with `:mod`/`:width`/`:height` — wraps the lazy `Session` + `Transport.start_server/1` boot triggered by the first `"resize"`; `[:kino_ex_ratatui, :render, :frame]` with `:mod`/`:byte_count` — wraps the `IO.iodata_to_binary/1` + Kino-bridge broadcast per-frame work) and three single events (`[:kino_ex_ratatui, :transport, :disconnect]` with `:mod`/`:reason` — fires exactly once per session, either from the runtime server's `:DOWN` or from the widget's `terminate/2` if the runtime is still alive; `[:kino_ex_ratatui, :input, :forward]` with `:mod`/`:byte_count` — fires when bytes from xterm.js are forwarded to `ByteStream.forward_input/3`; `[:kino_ex_ratatui, :resize]` with `:mod`/`:width`/`:height` — fires on resizes after the boot one). Public helpers: `span/3`, `execute/3`, `attach_default_logger/1`, `detach_default_logger/0`. New [Telemetry guide](guides/telemetry.md) walks through the full event catalogue and a `Telemetry.Metrics` wiring example. Added `{:telemetry, "~> 1.0"}` as an explicit dependency and to `extra_applications` so the handler registry is available wherever the kino runs.

## [0.1.1] - 2026-04-30

### Added

- README demo GIF (`assets/demo.gif`) showing a `Kino.ExRatatui` widget driving an `ExRatatui.App` inside a Livebook notebook.

## [0.1.0] - 2026-04-29

### Added

- **First release.** `kino_ex_ratatui` runs an `ExRatatui.App` inside a Livebook notebook via xterm.js, implemented as a ~150-line `Kino.JS.Live` widget on top of [`ExRatatui.Transport.ByteStream`](https://hexdocs.pm/ex_ratatui/ExRatatui.Transport.ByteStream.html). Two entry points: `Kino.ExRatatui.new/2` for live App-driven kinos, `Kino.ExRatatui.frame/2` for one-shot static frames suitable for docs and `Kino.Layout.grid/1` side-by-side comparisons.
- **JS bundle** under `assets/` — `@xterm/xterm` 5.5 + `@xterm/addon-fit` 0.10 bundled with esbuild 0.28 to `lib/assets/kino_ex_ratatui/{main.js,main.css}`. The bundle is committed so installing the hex package needs no Node toolchain. `mix assets.install` and `mix assets.build` aliases are provided for contributors.
- **Lazy lifecycle.** The runtime server and `ExRatatui.Session` are created on the first `"resize"` event from the iframe, so dimensions always come from xterm.js's `FitAddon` rather than a hardcoded default. Subsequent resize events flow through `ByteStream.forward_resize/4`. When the App returns `{:stop, _}` (or `mount/1` fails), the widget broadcasts the canonical alt-screen leave sequence so xterm.js restores its cursor and main buffer.
- **Test suite** — 22 tests via `Kino.Test`'s `configure_livebook_bridge` + `push_event/3` + `assert_broadcast_event/3`, covering: lazy boot, mount-opts pass-through, handle_connect payload, first/subsequent resize, input round-trip, input arriving before first resize, server `:DOWN`, terminate cleanup, mount failure, unrelated `handle_info` messages, and `__assets_info__/0`. Runs async in 0.2s, 100% line coverage (test fixtures excluded via `test_coverage: [ignore_modules: [...]]`).
- **Three bundled example notebooks** under `examples/` — `system_monitor.livemd` (callback-runtime dashboard porting `ex_ratatui/examples/system_monitor.exs` with `Gauge`, `Table`, `/proc` polling), `chat_interface.livemd` (callback-runtime AI-chat mock exercising `Markdown`, `Textarea`, `Throbber`, `Scrollbar`, and `/`-prefixed `SlashCommands` autocomplete via `Popup` — ported from the original imperative `ExRatatui.run/1` loop in `ex_ratatui/examples/chat_interface.exs`), and `reducer_counter.livemd` (reducer-runtime counter with a `Subscription.interval` plus a `Kino.ExRatatui.frame/2` static-frame demo). Each notebook cross-references the other two and links to the relevant runtime guide so any one of them is a complete jumping-off point.

[Unreleased]: https://github.com/mcass19/kino_ex_ratatui/compare/v0.1.1...HEAD
[0.1.1]: https://github.com/mcass19/kino_ex_ratatui/releases/tag/v0.1.0...v0.1.1
[0.1.0]: https://github.com/mcass19/kino_ex_ratatui/releases/tag/v0.1.0
