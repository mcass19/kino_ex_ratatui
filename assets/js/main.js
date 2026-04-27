// kino_ex_ratatui — Livebook widget for ExRatatui.
//
// Two modes share the same bundle:
//
//   1. Live  (Kino.ExRatatui.new/2)
//        payload from Elixir: {}  (empty object — handle_connect/1)
//        wiring: FitAddon + onData + ResizeObserver + "ansi" handler
//
//   2. Static (Kino.ExRatatui.frame/2)
//        payload from Elixir: {:binary, %{cols, rows, mode: "static"}, bytes}
//        delivered to JS as: [{cols, rows, mode}, ArrayBuffer]
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

const FONT_FAMILY =
  "ui-monospace, SFMono-Regular, Menlo, Monaco, Consolas, monospace";
const FONT_SIZE = 13;
const THEME = {
  background: "#1e1e2e",
  foreground: "#cdd6f4",
  cursor: "#f5e0dc",
};

export function init(ctx, payload) {
  ctx.importCSS("main.css");

  ctx.root.style.fontFamily = FONT_FAMILY;
  ctx.root.style.background = THEME.background;
  ctx.root.style.padding = "8px";
  ctx.root.style.borderRadius = "6px";

  // `Array.isArray` reliably distinguishes Kino's binary payload shape
  // ([info, ArrayBuffer]) from the empty `{}` map the live widget sends
  // back from handle_connect/1.
  if (Array.isArray(payload)) {
    initStatic(ctx, payload);
  } else {
    initLive(ctx);
  }
}

function initStatic(ctx, [{ cols, rows }, buffer]) {
  // Static frames know their exact size up front, so we don't need
  // FitAddon — just create the terminal at the right cell dimensions
  // and let xterm.js compute the pixel size from font metrics.
  const container = document.createElement("div");
  container.style.width = "100%";
  ctx.root.appendChild(container);

  const term = new Terminal({
    cols,
    rows,
    cursorBlink: false,
    cursorStyle: "block",
    disableStdin: true,
    convertEol: false,
    fontFamily: FONT_FAMILY,
    fontSize: FONT_SIZE,
    scrollback: 0,
    theme: THEME,
  });

  term.open(container);
  term.write(new Uint8Array(buffer));
}

function initLive(ctx) {
  // Container styling. xterm.js needs a fixed-height host; we give it a
  // sensible default that fits a typical 80×24 viewport at 13px font.
  // Users can grow the cell to make this larger and the FitAddon picks
  // it up via the ResizeObserver below.
  const container = document.createElement("div");
  container.style.height = "400px";
  container.style.width = "100%";
  ctx.root.appendChild(container);

  const term = new Terminal({
    cursorBlink: true,
    convertEol: false,
    fontFamily: FONT_FAMILY,
    fontSize: FONT_SIZE,
    theme: THEME,
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
