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

// Bundled named themes resolved when Elixir sends a theme atom
// (`:dark` / `:light` / `:livebook`) instead of a full ITheme map.
// Keep DARK_THEME in sync with `@default_display.theme` in
// `lib/kino/ex_ratatui.ex` — it's the same Catppuccin Mocha-flavored
// trio the Elixir-side default uses. LIGHT_THEME is Catppuccin Latte,
// chosen because it pairs visually with DARK_THEME.
const DARK_THEME = {
  background: "#1e1e2e",
  foreground: "#cdd6f4",
  cursor: "#f5e0dc",
};

const LIGHT_THEME = {
  background: "#eff1f5",
  foreground: "#4c4f69",
  cursor: "#dc8a78",
};

// JS-side fallbacks for non-theme display options. Elixir always sends
// the full display map today, but copying the values here keeps the JS
// hook usable in isolation (custom payload shapes, future smart-cell
// variants) and gives us a single answer for "what is the default
// look".
const NON_THEME_DEFAULTS = {
  font_family:
    "ui-monospace, SFMono-Regular, Menlo, Monaco, Consolas, monospace",
  font_size: 13,
  height: "400px",
  cursor_blink: true,
  scrollback: 1000,
};

// Resolves a theme value (map | "dark" | "light" | "livebook") into
// a concrete xterm.js ITheme map. For "livebook" we return whichever
// of DARK / LIGHT matches the user's current `prefers-color-scheme`;
// the live-update wiring is set up separately by `subscribeLivebookTheme`.
function resolveTheme(value) {
  if (value && typeof value === "object" && !Array.isArray(value)) {
    return value;
  }

  switch (value) {
    case "light":
      return LIGHT_THEME;
    case "livebook":
      return prefersDark() ? DARK_THEME : LIGHT_THEME;
    case "dark":
    default:
      return DARK_THEME;
  }
}

function prefersDark() {
  return (
    typeof window !== "undefined" &&
    typeof window.matchMedia === "function" &&
    window.matchMedia("(prefers-color-scheme: dark)").matches
  );
}

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

// Folds a (potentially empty / partial) display payload into the
// defaults and resolves the theme into a concrete map. Returns a
// `{ theme, themeAtom, font_family, ... }` shape — `themeAtom`
// preserves the original atom so the live path can decide whether
// to subscribe to color-scheme changes.
function resolveDisplay(payload) {
  const merged = { ...NON_THEME_DEFAULTS, ...(payload || {}) };
  const themeValue = (payload && payload.theme) ?? "dark";

  return {
    ...merged,
    theme: resolveTheme(themeValue),
    themeAtom: typeof themeValue === "string" ? themeValue : null,
  };
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
