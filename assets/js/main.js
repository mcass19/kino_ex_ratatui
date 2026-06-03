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
import { ImageAddon } from "@xterm/addon-image";
import "@xterm/xterm/css/xterm.css";
import { DARK_THEME, LIGHT_THEME, resolveDisplay } from "./display.js";

// Default options for `@xterm/addon-image`. The addon registers Sixel
// (`DCS q ...`) and iTerm2 inline-image (`ESC ] 1337 ; File=... ^G`)
// handlers on the xterm parser; without it those sequences would be
// silently swallowed and `ExRatatui.Widgets.Image` would render
// nothing in Livebook. Loaded in both live and static modes so an
// image embedded in `Kino.ExRatatui.frame/2` survives a static
// snapshot. The defaults match the addon's own — Sixel + iTerm2 on,
// no Kitty (the addon doesn't ship Kitty), conservative size limits.
const IMAGE_ADDON_OPTIONS = { sixelSupport: true, iipSupport: true };

// When `theme === "livebook"`, listen for OS-level color-scheme
// changes and re-apply the matching bundled theme to both xterm and
// the container's outer background. The listener lives for the
// lifetime of the iframe — Livebook tears the iframe down on cell
// re-eval, taking the listener with it.
function subscribeLivebookTheme(ctx, term) {
  if (
    typeof window === "undefined" ||
    typeof window.matchMedia !== "function"
  ) {
    return;
  }

  const mql = window.matchMedia("(prefers-color-scheme: dark)");
  const apply = () => {
    const next = mql.matches ? DARK_THEME : LIGHT_THEME;
    term.options.theme = next;
    ctx.root.style.background = next.background;
  };

  // Modern browsers expose addEventListener; very old ones used
  // `addListener`. Prefer the standard form, fall back if needed.
  if (typeof mql.addEventListener === "function") {
    mql.addEventListener("change", apply);
  } else if (typeof mql.addListener === "function") {
    mql.addListener(apply);
  }
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
  // ImageAddon is loaded after `term.open(container)` so its
  // `activate()` runs against a mounted terminal. The write is
  // deferred by one animation frame so addon-image's DOM
  // measurement + canvas overlay positioning settle before the
  // first byte hits the parser. Without the defer, a single-shot
  // static frame containing Sixel renders as an empty black
  // rectangle — the bytes are consumed but the addon hasn't
  // computed cell offsets yet, so the image paints at (0, 0)
  // with zero dimensions. Live mode is unaffected because the
  // first ANSI frame arrives many ticks later anyway (resize →
  // runtime boot → render). The Kino.Layout.grid path dodges
  // this accidentally because each cell mounts inside its own
  // iframe lifecycle that already defers across frames.
  term.loadAddon(new ImageAddon(IMAGE_ADDON_OPTIONS));
  const bytes = new Uint8Array(buffer);
  // Double rAF: first frame, xterm.js's renderer measures the
  // newly-opened terminal's cell pixel dimensions; second frame,
  // addon-image's canvas overlay is positioned against those
  // measurements and ready to receive Sixel. Writing on a single
  // rAF works for small terminals (the measurement is cheap enough
  // to complete in the same frame) but larger terminals lose the
  // image — bytes are consumed before the overlay is positioned.
  requestAnimationFrame(() =>
    requestAnimationFrame(() => term.write(bytes))
  );

  if (display.themeAtom === "livebook") {
    subscribeLivebookTheme(ctx, term);
  }
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
  term.loadAddon(new ImageAddon(IMAGE_ADDON_OPTIONS));
  term.open(container);
  fit.fit();

  if (display.themeAtom === "livebook") {
    subscribeLivebookTheme(ctx, term);
  }

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

  // Receive the stopped-state signal — the runtime server has exited
  // (App returned {:stop, _}, mount/1 failed, …). Replace the frozen
  // final frame with an accessible overlay so screen readers announce
  // the message and sighted users see a clean hint rather than a
  // dead cursor sitting on the last rendered output.
  ctx.handleEvent("stopped", ({ message }) => {
    showStoppedOverlay(container, display.theme, message);
  });
}

// Anchors a `role="status"` overlay to the xterm container with the
// supplied message. Idempotent — if a previous "stopped" event
// already rendered an overlay we leave it alone (Elixir won't fire
// twice today, but the JS being defensive costs nothing).
//
// The overlay uses the configured theme's background/foreground so
// it visually continues from the terminal rather than punching a
// random color over it. `pointer-events: none` so it doesn't capture
// clicks — there's nothing to click yet, but if we ever add a
// "restart" button we'd flip this on for that element only.
function showStoppedOverlay(container, theme, message) {
  if (container.querySelector(".pxr-stopped")) return;

  // The overlay is absolutely positioned, so the container needs to
  // be a positioning context.
  if (!container.style.position) {
    container.style.position = "relative";
  }

  const overlay = document.createElement("div");
  overlay.className = "pxr-stopped";
  overlay.setAttribute("role", "status");
  overlay.setAttribute("aria-live", "polite");
  // textContent (not innerHTML) so a user-supplied stopped_message
  // containing HTML never executes — defensive even though the message
  // originates from the user's own Elixir code.
  overlay.textContent = message;
  overlay.style.cssText = [
    "position:absolute",
    "inset:0",
    "display:flex",
    "align-items:center",
    "justify-content:center",
    "padding:1rem",
    "font-style:italic",
    "background:" + theme.background,
    "color:" + (theme.foreground || "#888"),
    "border-radius:inherit",
    "z-index:1",
    "white-space:pre-line",
    "text-align:center",
    "pointer-events:none",
  ].join(";");

  container.appendChild(overlay);
}
