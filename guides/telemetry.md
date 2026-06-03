# Telemetry

`kino_ex_ratatui` emits [`:telemetry`](https://hexdocs.pm/telemetry/) events at the boundaries the widget itself controls. They sit one layer above the events `ex_ratatui` already emits — together they give a complete profile of a Livebook-driven TUI.

## Event tree at a glance

```
[:kino_ex_ratatui, :transport, :connect]    span    — widget boots Session + runtime
[:kino_ex_ratatui, :transport, :disconnect] single  — server :DOWN or widget terminate
[:kino_ex_ratatui, :render, :frame]         span    — ANSI broadcast over the Kino bridge
[:kino_ex_ratatui, :input, :forward]        single  — bytes from xterm.js → runtime
[:kino_ex_ratatui, :resize]                 single  — resizes after the boot one
```

Span events emit `:start` / `:stop` / `:exception` suffixes. Most handlers only attach to `:stop` for timing and `:exception` for failures.

See `Kino.ExRatatui.Telemetry` for the full metadata reference.

## Quick start: log every event

```elixir
# In a Livebook setup cell, or the application's start/2 callback:
Kino.ExRatatui.Telemetry.attach_default_logger(level: :info)
```

Detach with `Kino.ExRatatui.Telemetry.detach_default_logger/0`.

## Wiring `Telemetry.Metrics`

If `Telemetry.Metrics` is already running (e.g. in a Phoenix LiveDashboard), add these alongside whatever `ex_ratatui` metrics matter:

```elixir
defmodule MyApp.Telemetry do
  import Telemetry.Metrics

  def metrics do
    [
      # Time-to-first-frame on widget boot.
      summary("kino_ex_ratatui.transport.connect.stop.duration",
        unit: {:native, :millisecond}
      ),

      # How many sessions opened / closed.
      counter("kino_ex_ratatui.transport.disconnect"),

      # Per-frame ANSI broadcast cost (typically microseconds).
      summary("kino_ex_ratatui.render.frame.stop.duration",
        unit: {:native, :microsecond}
      ),

      # Input bytes flowing client → server.
      sum("kino_ex_ratatui.input.forward.byte_count"),

      # Resize storms (windows, splits, …).
      counter("kino_ex_ratatui.resize")
    ]
  end
end
```

## Pairing with `ex_ratatui`'s events

The two trees are complementary, not duplicative:

| Concern | Owned by |
| ------- | -------- |
| `mount/1` runtime, App `handle_event/2`, render command building | `[:ex_ratatui, ...]` |
| Widget boot (network handshake + first `Transport.start_server/1`), ANSI broadcast over the Kino bridge, client input forwarding | `[:kino_ex_ratatui, ...]` |

Attach to whichever is needed. A typical setup attaches `[:ex_ratatui, :runtime, :event, :stop]` for App-level latency and `[:kino_ex_ratatui, :render, :frame, :stop]` for the wire cost — together they show where time is going without instrumenting either layer manually.

## Custom handlers

The public helpers `Kino.ExRatatui.Telemetry.span/3` and `Kino.ExRatatui.Telemetry.execute/3` are thin wrappers around `:telemetry.span/3` and `:telemetry.execute/3` that prepend `:kino_ex_ratatui` to the event name. Use them when building a higher-level wrapper around `Kino.ExRatatui.new/2` to emit events under the same namespace.

For one-off handlers, attach directly:

```elixir
:telemetry.attach(
  "my-app-frame-tracker",
  [:kino_ex_ratatui, :render, :frame, :stop],
  &MyApp.TuiTracker.handle_frame/4,
  nil
)
```

Always use a captured module function (`&MyApp.TuiTracker.handle_frame/4`), not an anonymous function — `:telemetry` logs a performance warning otherwise.
