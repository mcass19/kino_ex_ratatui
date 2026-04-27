# Contributing to KinoExRatatui

Thanks for your interest in contributing!

## Setup

1. Clone the repo:

```sh
git clone https://github.com/mcass19/kino_ex_ratatui.git
cd kino_ex_ratatui
```

2. Prerequisites:

- **Elixir** 1.17+ and **Erlang/OTP** 26+ (the `mise.toml` pins exact versions)
- **Node.js** 20+ — only needed to rebuild the xterm.js bundle. End users installing from hex don't need it.

3. Fetch dependencies:

```sh
mix deps.get
mix assets.install   # cd assets && npm install
```

## Project layout

```
lib/kino/ex_ratatui.ex                 # the live + static widget
lib/assets/kino_ex_ratatui/main.{js,css}   # bundled JS (committed)
assets/                                # JS source — npm project + esbuild
  package.json
  build.js                             # esbuild driver
  js/main.js                           # xterm.js + FitAddon + Kino bridge
test/kino/...                          # ExUnit tests
test/support/                          # App fixtures (Counter, CrashingMount)
```

## Tests

```sh
mix test                # 22 tests, runs async in ~0.2s
mix test --cover        # must report 100.00% Total
```

The suite uses `Kino.Test`'s `configure_livebook_bridge` setup to drive the live widget end-to-end without a real browser. Test fixtures (`KinoExRatatui.Test.Counter`, `KinoExRatatui.Test.CrashingMount`) are excluded from the coverage threshold via `test_coverage: [ignore_modules: [...]]` in `mix.exs`.

For the actual browser smoke test, open `livebook/counter.livemd` in Livebook and run the cells.

## Bundling the JS

```sh
mix assets.build       # cd assets && npm run build (minified)
# or
cd assets && npm run build:dev   # with sourcemaps
```

The bundled output lands at `lib/assets/kino_ex_ratatui/main.js` (and `main.css` for xterm's stylesheet). Both files are committed so the published hex package needs no Node toolchain at install time.

If you change anything under `assets/js/`, rerun `mix assets.build` and commit the regenerated bundle.

## Formatting & lints

```sh
mix format --check-formatted
mix credo --strict
```

Both are required to be clean.

## Pull requests

- Add tests for new behavior — coverage stays at 100%.
- Update `CHANGELOG.md` under `## [Unreleased]` with a sentence describing the change.
- Keep the moduledoc in `lib/kino/ex_ratatui.ex` in sync with any new public surface.

## Scope

`kino_ex_ratatui` is intentionally a thin transport — it doesn't add widgets, change the `ExRatatui.App` contract, or invent a notebook-flavored API. Widgets and runtime features belong [upstream in `ex_ratatui`](https://github.com/mcass19/ex_ratatui).
