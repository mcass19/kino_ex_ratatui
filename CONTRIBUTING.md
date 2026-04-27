# Contributing to KinoExRatatui

Thanks for your interest in contributing!

## Setup

1. Clone the repo:

```sh
git clone https://github.com/mcass19/kino_ex_ratatui.git
cd kino_ex_ratatui
```

2. Install dependencies:

- **Elixir** 1.17+ and **Erlang/OTP** 26+
- **Node.js** 20+ (for bundling the xterm.js bridge)

3. Fetch deps:

```sh
mix deps.get
cd assets && npm install && cd ..
```

## Tests

```sh
mix test
```

## Bundling the JS

```sh
cd assets && npm run build
```

The bundled output lands under `priv/static/` and is committed so consumers
don't need a Node toolchain to install the package.

## Formatting & lints

```sh
mix format --check-formatted
mix credo --strict
```
