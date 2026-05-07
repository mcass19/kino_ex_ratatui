# Examples

A catalog of `kino_ex_ratatui` Livebook notebooks. Each stands alone — open it in [Livebook](https://livebook.dev), run the cells. Three are interactive callback / reducer apps; one is purely a display-options walkthrough.

## Catalog

| Notebook | What to see |
|----------|-------------|
| [`system_monitor.livemd`](system_monitor.livemd) | Callback-runtime dashboard with `Gauge` + `Table` reading `/proc`, `/sys`, and BEAM stats every two seconds. Linux/Nerves only. Drop-in port of [`ex_ratatui/examples/system_monitor.exs`](https://github.com/mcass19/ex_ratatui/blob/main/examples/system_monitor.exs). |
| [`chat_interface.livemd`](chat_interface.livemd) | Callback-runtime AI-chat mock exercising `Markdown`, `Textarea`, `Throbber`, `Scrollbar`, and `/`-prefixed `SlashCommands` autocomplete via `Popup`. The most visually rich example. |
| [`reducer_counter.livemd`](reducer_counter.livemd) | Reducer-runtime counter with `init/1` + `update/2` and a `Subscription.interval` ticking every second. Bonus: a static `Kino.ExRatatui.frame/2` widget gallery at the end. |
| [`theming.livemd`](theming.livemd) | The same showcase App rendered nine ways: default, One Dark, Solarized Light, the `:dark` / `:light` / `:livebook` atom shorthands, `configure/1` global defaults, custom font + size, no-blink + custom stopped message, side-by-side static gallery, and call-site validation. |

## Where to start

If you're new, open `reducer_counter.livemd` — it's the smallest interactive example and the static-frame demo at the end is a useful jumping-off point for `Kino.Layout.grid/1` widget galleries.

If you want to see `Kino.ExRatatui.new/2` and `Kino.ExRatatui.frame/2` configured every way they can be, open `theming.livemd`.

## Related guides

- [`Kino.ExRatatui` moduledoc](https://hexdocs.pm/kino_ex_ratatui/Kino.ExRatatui.html) — full Mount / Display options reference.
- [Configuration](https://hexdocs.pm/kino_ex_ratatui/configuration.html) — global defaults via `Kino.ExRatatui.configure/1` and the merge order.
- [Telemetry](https://hexdocs.pm/kino_ex_ratatui/telemetry.html) — the five `[:kino_ex_ratatui, …]` events you can hook into.
