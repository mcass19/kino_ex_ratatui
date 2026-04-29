# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [0.1.0] - 2026-04-29

### Added

- **First release.** `kino_ex_ratatui` runs an `ExRatatui.App` inside a Livebook notebook via xterm.js, implemented as a ~150-line `Kino.JS.Live` widget on top of [`ExRatatui.Transport.ByteStream`](https://hexdocs.pm/ex_ratatui/ExRatatui.Transport.ByteStream.html). Two entry points: `Kino.ExRatatui.new/2` for live App-driven kinos, `Kino.ExRatatui.frame/2` for one-shot static frames suitable for docs and `Kino.Layout.grid/1` side-by-side comparisons.
- **JS bundle** under `assets/` — `@xterm/xterm` 5.5 + `@xterm/addon-fit` 0.10 bundled with esbuild 0.28 to `lib/assets/kino_ex_ratatui/{main.js,main.css}`. The bundle is committed so installing the hex package needs no Node toolchain. `mix assets.install` and `mix assets.build` aliases are provided for contributors.
- **Lazy lifecycle.** The runtime server and `ExRatatui.Session` are created on the first `"resize"` event from the iframe, so dimensions always come from xterm.js's `FitAddon` rather than a hardcoded default. Subsequent resize events flow through `ByteStream.forward_resize/4`. When the App returns `{:stop, _}` (or `mount/1` fails), the widget broadcasts the canonical alt-screen leave sequence so xterm.js restores its cursor and main buffer.
- **Test suite** — 22 tests via `Kino.Test`'s `configure_livebook_bridge` + `push_event/3` + `assert_broadcast_event/3`, covering: lazy boot, mount-opts pass-through, handle_connect payload, first/subsequent resize, input round-trip, input arriving before first resize, server `:DOWN`, terminate cleanup, mount failure, unrelated `handle_info` messages, and `__assets_info__/0`. Runs async in 0.2s, 100% line coverage (test fixtures excluded via `test_coverage: [ignore_modules: [...]]`).
- **Three bundled example notebooks** under `examples/` — `system_monitor.livemd` (callback-runtime dashboard porting `ex_ratatui/examples/system_monitor.exs` with `Gauge`, `Table`, `/proc` polling), `chat_interface.livemd` (callback-runtime AI-chat mock exercising `Markdown`, `Textarea`, `Throbber`, `Scrollbar`, and `/`-prefixed `SlashCommands` autocomplete via `Popup` — ported from the original imperative `ExRatatui.run/1` loop in `ex_ratatui/examples/chat_interface.exs`), and `reducer_counter.livemd` (reducer-runtime counter with a `Subscription.interval` plus a `Kino.ExRatatui.frame/2` static-frame demo). Each notebook cross-references the other two and links to the relevant runtime guide so any one of them is a complete jumping-off point.

[Unreleased]: https://github.com/mcass19/kino_ex_ratatui/compare/v0.1.0...HEAD
[0.1.0]: https://github.com/mcass19/kino_ex_ratatui/releases/tag/v0.1.0
