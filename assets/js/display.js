// Pure display/theme resolution for the kino_ex_ratatui widget.
//
// Split out of main.js so it can be unit-tested under `node --test`
// without pulling in xterm.js or its CSS (which the Node test runner
// can't import). main.js imports everything here; esbuild bundles it
// back into a single file. Keep this module free of DOM/xterm imports
// so the tests stay dependency-free.

// Bundled named themes resolved when Elixir sends a theme atom
// (`:dark` / `:light` / `:livebook`) instead of a full ITheme map.
// Keep DARK_THEME in sync with `@default_display.theme` in
// `lib/kino/ex_ratatui.ex` — it's the same Catppuccin Mocha-flavored
// trio the Elixir-side default uses. LIGHT_THEME is Catppuccin Latte,
// chosen because it pairs visually with DARK_THEME.
export const DARK_THEME = {
  background: "#1e1e2e",
  foreground: "#cdd6f4",
  cursor: "#f5e0dc",
};

export const LIGHT_THEME = {
  background: "#eff1f5",
  foreground: "#4c4f69",
  cursor: "#dc8a78",
};

// JS-side fallbacks for non-theme display options. Elixir always sends
// the full display map today, but copying the values here keeps the JS
// hook usable in isolation (custom payload shapes, future smart-cell
// variants) and gives us a single answer for "what is the default
// look".
export const NON_THEME_DEFAULTS = {
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
export function resolveTheme(value) {
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

export function prefersDark() {
  return (
    typeof window !== "undefined" &&
    typeof window.matchMedia === "function" &&
    window.matchMedia("(prefers-color-scheme: dark)").matches
  );
}

// Folds a (potentially empty / partial) display payload into the
// defaults and resolves the theme into a concrete map. Returns a
// `{ theme, themeAtom, font_family, ... }` shape — `themeAtom`
// preserves the original atom so the live path can decide whether
// to subscribe to color-scheme changes.
export function resolveDisplay(payload) {
  const merged = { ...NON_THEME_DEFAULTS, ...(payload || {}) };
  const themeValue = (payload && payload.theme) ?? "dark";

  return {
    ...merged,
    theme: resolveTheme(themeValue),
    themeAtom: typeof themeValue === "string" ? themeValue : null,
  };
}
