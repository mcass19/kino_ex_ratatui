// kino_ex_ratatui — Livebook widget that runs an ExRatatui.App in xterm.js.
//
// Wire protocol (matches lib/kino/ex_ratatui.ex):
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

export function init(ctx, _payload) {
  ctx.importCSS("main.css");

  // Container styling. xterm.js needs a fixed-height host; we give it a
  // sensible default that fits a typical 80×24 viewport at 13px font.
  // Users can grow the cell to make this larger and the FitAddon picks
  // it up via the ResizeObserver below.
  ctx.root.style.fontFamily = "ui-monospace, SFMono-Regular, Menlo, Monaco, Consolas, monospace";
  ctx.root.style.background = "#1e1e2e";
  ctx.root.style.padding = "8px";
  ctx.root.style.borderRadius = "6px";

  const container = document.createElement("div");
  container.style.height = "400px";
  container.style.width = "100%";
  ctx.root.appendChild(container);

  const term = new Terminal({
    cursorBlink: true,
    convertEol: false,
    fontFamily: "ui-monospace, SFMono-Regular, Menlo, Monaco, Consolas, monospace",
    fontSize: 13,
    theme: {
      background: "#1e1e2e",
      foreground: "#cdd6f4",
      cursor: "#f5e0dc",
    },
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
