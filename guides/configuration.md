# Configuration

`kino_ex_ratatui` reads display options from three sources, in order:

```
per-instance opts (new/2 / frame/2)  >  configure/1  >  module defaults
```

Each key is resolved independently, so a global font and theme can be set via `configure/1` while still overriding just the theme on an individual cell.

## Per-instance opts

The most direct path. See the [Display options](`Kino.ExRatatui#module-display-options`) table for the full list.

```elixir
Kino.ExRatatui.new(MyApp,
  theme: %{background: "#0d1117", foreground: "#c9d1d9"},
  font_size: 14,
  height: "600px"
)
```

## Global defaults via `configure/1`

`Kino.ExRatatui.configure/1` writes to the `:kino_ex_ratatui` Application environment and applies to every subsequent `new/2` and `frame/2` call.

```elixir
# In a Livebook setup cell:
Kino.ExRatatui.configure(
  theme: :livebook,
  font_family: "JetBrains Mono, ui-monospace, monospace",
  font_size: 14
)
```

Calling `configure/1` again merges into the existing config rather than replacing it — handy for splitting concerns across cells:

```elixir
Kino.ExRatatui.configure(font_size: 14)         # font choice in one place
Kino.ExRatatui.configure(theme: :livebook)      # theme in another
# Both keys are now active.
```

The same values are available via `Application.get_all_env(:kino_ex_ratatui)`, so a release `config/runtime.exs` or `Config`-driven release config works equivalently:

```elixir
# config/runtime.exs
config :kino_ex_ratatui,
  theme: :livebook,
  font_size: 14
```

Validation runs immediately — `configure/1` raises `ArgumentError` on bad shapes the same way `new/2` does, so a mistyped key fails at the source rather than producing a working-but-wrong widget.

## Atom theme shorthands

The `:theme` option accepts a full xterm.js [`ITheme`](https://xtermjs.org/docs/api/terminal/interfaces/itheme/) map (the lowest-level form) or one of three atoms:

| Atom | What it does |
| ---- | ------------ |
| `:dark` | Bundled Catppuccin Mocha-flavored dark palette. Same colors as the no-opts default. |
| `:light` | Bundled Catppuccin Latte-flavored light palette. Pairs visually with `:dark`. |
| `:livebook` | Picks `:dark` or `:light` based on the user's OS-level `prefers-color-scheme`, and re-applies on the fly when that preference changes. |

The atoms are resolved in the JS hook, so `theme: :livebook` is a single source of truth for "match my Livebook" — no duplicate light/dark configs needed.

```elixir
# Reactively follows the user's color-scheme preference.
Kino.ExRatatui.configure(theme: :livebook)

# Or pick one explicitly.
Kino.ExRatatui.new(MyApp, theme: :light)
```

For finer control (selection backgrounds, the 16-color ANSI palette, cursor accents) supply a map directly — same vocabulary as xterm.js's `Terminal({theme: ...})`:

```elixir
Kino.ExRatatui.new(MyApp,
  theme: %{
    background: "#282c34",
    foreground: "#abb2bf",
    cursorAccent: "#282c34",
    selectionBackground: "#3e4451",
    red: "#e06c75",
    green: "#98c379",
    # …
  }
)
```

## Merge order in practice

```elixir
Kino.ExRatatui.configure(theme: :livebook, font_size: 14, height: "600px")

# This call uses:
#   - theme: %{background: "#000"}    (per-instance — overrides configure's :livebook)
#   - font_size: 14                   (configure)
#   - height: "600px"                 (configure)
#   - cursor_blink: true              (module default — neither set it)
Kino.ExRatatui.new(MyApp, theme: %{background: "#000"})
```

Each key is resolved independently — there's no "all-or-nothing" inheritance.

## When configure/1 is the wrong tool

If a TUI app needs runtime knowledge (current user, request id, …), thread that through `c:ExRatatui.App.mount/1` instead. `configure/1` is for cosmetics: theme, font, height, cursor, scrollback, stopped message — values that don't change between cells in the same notebook.
