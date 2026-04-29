# Contributing to KinoExRatatui

Thanks for your interest in contributing!

KinoExRatatui is a pure Elixir project built on [ExRatatui](https://github.com/mcass19/ex_ratatui).

Feel free to also consider contributing on the upstream library if you're missing a feature, or something is not working. Contributions are welcome everywhere!

This guide will help you get set up.

## Setup

1. Clone the repo:

```sh
git clone https://github.com/mcass19/kino_ex_ratatui.git
cd kino_ex_ratatui
```

2. Prerequisites:

- **Elixir** 1.17+ and **Erlang/OTP** 26+.
- **Node.js** 20+ — only needed to rebuild the xterm.js bundle. End users installing from hex don't need it.

3. Fetch dependencies:

```sh
mix deps.get
mix assets.install   # cd assets && npm install
```

## Running Tests

```sh
mix test
mix test --cover        # must report 100.00% Total
```

The suite uses `Kino.Test`'s `configure_livebook_bridge` setup to drive the live widget end-to-end without a real browser.

For the actual browser smoke test, open one of the notebooks under `examples/` in Livebook and run the cells.

## Bundling the JS

```sh
mix assets.build       # cd assets && npm run build (minified)
# or
cd assets && npm run build:dev   # with sourcemaps
```

The bundled output lands at `lib/assets/kino_ex_ratatui/main.js` (and `main.css` for xterm's stylesheet). Both files are committed so the published hex package needs no Node toolchain at install time.

If you change anything under `assets/js/`, rerun `mix assets.build` and commit the regenerated bundle.

## Branching and Commits

- Branch from `main`
- Keep commits focused and atomic
- Use descriptive commit message prefixes: `feat:`, `fix:`, `docs:`, `test:`, `refactor:`, `chore:`

## Pull Requests

Before submitting a PR, make sure the following pass:

```sh
mix format --check-formatted
mix compile --warnings-as-errors
mix credo --strict
mix dialyzer
mix test --cover
```

- Keep PRs focused — one feature or fix per PR
- Add tests for new functionality
- Add `@doc`, `@spec`, and `@moduledoc` for new public functions and modules
- Update documentation (moduledocs, CHANGELOG, README if applicable)
- For breaking changes, include migration notes in the CHANGELOG
- Follow existing code style and patterns
- Ensure CI passes before requesting review

