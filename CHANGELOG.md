# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- **First release.** `kino_ex_ratatui` runs an `ExRatatui.App` inside a Livebook notebook via xterm.js, implemented as a ~150-line `Kino.JS.Live` widget on top of [`ExRatatui.Transport.ByteStream`](https://hexdocs.pm/ex_ratatui/ExRatatui.Transport.ByteStream.html) (introduced in `ex_ratatui v0.8.1`). Two entry points: `Kino.ExRatatui.new/2` for live App-driven kinos, `Kino.ExRatatui.frame/2` for one-shot static frames suitable for docs and `Kino.Layout.grid/1` side-by-side comparisons.
- **JS bundle** under `assets/` — `@xterm/xterm` 5.5 + `@xterm/addon-fit` 0.10 bundled with esbuild 0.28 to `lib/assets/kino_ex_ratatui/{main.js,main.css}`. The bundle is committed so installing the hex package needs no Node toolchain. `mix assets.install` and `mix assets.build` aliases are provided for contributors.
- **Lazy lifecycle.** The runtime server and `ExRatatui.Session` are created on the first `"resize"` event from the iframe, so dimensions always come from xterm.js's `FitAddon` rather than a hardcoded default. Subsequent resize events flow through `ByteStream.forward_resize/4`. When the App returns `{:stop, _}` (or `mount/1` fails), the widget broadcasts the canonical alt-screen leave sequence so xterm.js restores its cursor and main buffer.
- **Test suite** — 22 tests via `Kino.Test`'s `configure_livebook_bridge` + `push_event/3` + `assert_broadcast_event/3`, covering: lazy boot, mount-opts pass-through, handle_connect payload, first/subsequent resize, input round-trip, input arriving before first resize, server `:DOWN`, terminate cleanup, mount failure, unrelated `handle_info` messages, and `__assets_info__/0`. Runs async in 0.2s, 100% line coverage (test fixtures excluded via `test_coverage: [ignore_modules: [...]]`).
