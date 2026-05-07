// kino_ex_ratatui — Livebook widget for ExRatatui.
//
// Two modes share the same bundle:
//
//   1. Live  (Kino.ExRatatui.new/2)
//        payload from Elixir: display map (theme, font_family, font_size,
//                              height, cursor_blink, scrollback,
//                              stopped_message)
//        wiring: FitAddon + onData + ResizeObserver + "ansi" handler
//
//   2. Static (Kino.ExRatatui.frame/2)
//        payload from Elixir: {:binary, %{cols, rows, mode: "static",
//                                         theme, font_family, font_size},
//                              bytes}
//        delivered to JS as: [{cols, rows, mode, ...display}, ArrayBuffer]
//        wiring: term.resize(cols, rows); term.write(bytes); nothing else
//
// Wire protocol for live mode (matches lib/kino/ex_ratatui.ex):
//
//   client → server
//     "resize" : {cols, rows}                — first one boots the runtime,
//                                              subsequent ones forward to
//                                              ByteStream.forward_resize/4
//     "input"  : [info, ArrayBuffer]         — bytes typed into xterm.js,
//                                              forwarded to
//                                              ByteStream.forward_input/3
//
//   server → client
//     "ansi"   : [info, ArrayBuffer]         — rendered ANSI bytes from the
//                                              runtime server's writer_fn,
//                                              fed straight to term.write
import { Terminal } from "@xterm/xterm";
import { FitAddon } from "@xterm/addon-fit";
import "@xterm/xterm/css/xterm.css";

// JS-side fallbacks. Keep in sync with `@default_display` in
// `lib/kino/ex_ratatui.ex` — Elixir always sends the full display map
// today, but copying the values here keeps the JS hook usable in
// isolation (custom payload shapes, future smart-cell variants) and
// gives us a single answer for "what is the default look".
const DEFAULTS = {
  theme: {
    background: "#1e1e2e",
    foreground: "#cdd6f4",
    cursor: "#f5e0dc",
  },
  font_family:
    "ui-monospace, SFMono-Regular, Menlo, Monaco, Consolas, monospace",
  font_size: 13,
  height: "400px",
  cursor_blink: true,
  scrollback: 1000,
};

// Folds a (potentially empty / partial) display payload into the
// defaults. Theme is shallow-merged separately so users overriding
// `background` don't lose the default `foreground` / `cursor`.
function resolveDisplay(payload) {
  const merged = { ...DEFAULTS, ...(payload || {}) };
  merged.theme = { ...DEFAULTS.theme, ...((payload && payload.theme) || {}) };
  return merged;
}

function applyContainerStyle(ctx, display) {
  ctx.root.style.fontFamily = display.font_family;
  ctx.root.style.background = display.theme.background;
  ctx.root.style.padding = "8px";
  ctx.root.style.borderRadius = "6px";
}

export function init(ctx, payload) {
  ctx.importCSS("main.css");

  // `Array.isArray` reliably distinguishes Kino's binary payload shape
  // ([info, ArrayBuffer]) from the display map the live widget sends
  // back from handle_connect/1.
  if (Array.isArray(payload)) {
    initStatic(ctx, payload);
  } else {
    initLive(ctx, payload);
  }
}

function initStatic(ctx, [info, buffer]) {
  // Static frames know their exact size up front, so we don't need
  // FitAddon — just create the terminal at the right cell dimensions
  // and let xterm.js compute the pixel size from font metrics.
  const display = resolveDisplay(info);
  applyContainerStyle(ctx, display);

  const container = document.createElement("div");
  container.style.width = "100%";
  ctx.root.appendChild(container);

  const term = new Terminal({
    cols: info.cols,
    rows: info.rows,
    cursorBlink: false,
    cursorStyle: "block",
    disableStdin: true,
    convertEol: false,
    fontFamily: display.font_family,
    fontSize: display.font_size,
    scrollback: 0,
    theme: display.theme,
  });

  term.open(container);
  term.write(new Uint8Array(buffer));
}

function initLive(ctx, payload) {
  const display = resolveDisplay(payload);
  applyContainerStyle(ctx, display);

  // Container styling. xterm.js needs a fixed-height host; the
  // configured `height` is a CSS length applied verbatim, so users
  // can pass `"400px"`, `"60vh"`, `"calc(100vh - 200px)"`, etc.
  const container = document.createElement("div");
  container.style.height = display.height;
  container.style.width = "100%";
  ctx.root.appendChild(container);

  const term = new Terminal({
    cursorBlink: display.cursor_blink,
    convertEol: false,
    fontFamily: display.font_family,
    fontSize: display.font_size,
    scrollback: display.scrollback,
    theme: display.theme,
  });

  const fit = new FitAddon();
  term.loadAddon(fit);
  term.open(container);
  fit.fit();

  // Send the initial size as soon as we mount. The Elixir side uses
  // this first event to lazy-boot the Session + runtime server at the
  // exact dimensions xterm.js settled on.
  ctx.pushEvent("resize", { cols: term.cols, rows: term.rows });

  // Forward keystrokes as raw bytes. xterm's onData hands us a string;
  // TextEncoder turns it into the same UTF-8 bytes a real terminal
  // would deliver, which is exactly what Session.feed_input/2 parses.
  const encoder = new TextEncoder();
  term.onData((data) => {
    const buffer = encoder.encode(data).buffer;
    ctx.pushEvent("input", [{}, buffer]);
  });

  // Watch the host element for size changes (cell resized, Livebook
  // window resized, …). Re-fit the terminal and tell the server.
  const resizeObserver = new ResizeObserver(() => {
    fit.fit();
    ctx.pushEvent("resize", { cols: term.cols, rows: term.rows });
  });
  resizeObserver.observe(container);

  // Receive ANSI from the runtime server. The payload is delivered as
  // [info, ArrayBuffer] — Kino's binary-channel shape — so we wrap in a
  // Uint8Array and feed it straight to xterm.write, which understands
  // raw bytes (escape sequences, UTF-8, the lot).
  ctx.handleEvent("ansi", ([_info, buffer]) => {
    term.write(new Uint8Array(buffer));
  });
}
