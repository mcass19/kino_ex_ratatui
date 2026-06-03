// Unit tests for the pure display/theme resolution behind the widget.
//
// Uses Node's built-in test runner (`node --test`) — no third-party
// deps. These functions live in display.js precisely so they can be
// imported here without dragging in xterm.js or its CSS. The DOM/xterm
// wiring in main.js (term.open, FitAddon, ResizeObserver, the stopped
// overlay) isn't exercised here; this pins the payload-decoding and
// theme-resolution logic that has no browser dependency and is the
// easiest to get subtly wrong.

import { test } from "node:test";
import assert from "node:assert/strict";

import {
  DARK_THEME,
  LIGHT_THEME,
  NON_THEME_DEFAULTS,
  resolveTheme,
  resolveDisplay,
  prefersDark,
} from "../js/display.js";

test("resolveTheme passes a full ITheme map through untouched", () => {
  const custom = { background: "#000", foreground: "#fff", cursor: "#0f0" };
  assert.equal(resolveTheme(custom), custom);
});

test("resolveTheme maps the named atoms to bundled themes", () => {
  assert.equal(resolveTheme("dark"), DARK_THEME);
  assert.equal(resolveTheme("light"), LIGHT_THEME);
});

test("resolveTheme falls back to DARK_THEME for unknown / missing values", () => {
  assert.equal(resolveTheme(undefined), DARK_THEME);
  assert.equal(resolveTheme(null), DARK_THEME);
  assert.equal(resolveTheme("nonsense"), DARK_THEME);
  // An array is an object but not an ITheme map — must not pass through.
  assert.equal(resolveTheme(["rgb", 1, 2, 3]), DARK_THEME);
});

test("resolveTheme('livebook') tracks prefers-color-scheme via window.matchMedia", () => {
  const originalWindow = globalThis.window;

  globalThis.window = { matchMedia: () => ({ matches: true }) };
  assert.equal(resolveTheme("livebook"), DARK_THEME);

  globalThis.window = { matchMedia: () => ({ matches: false }) };
  assert.equal(resolveTheme("livebook"), LIGHT_THEME);

  if (originalWindow === undefined) {
    delete globalThis.window;
  } else {
    globalThis.window = originalWindow;
  }
});

test("prefersDark is false when there is no window (Node / SSR)", () => {
  assert.equal(prefersDark(), false);
});

test("resolveDisplay fills the non-theme defaults and resolves to dark", () => {
  const display = resolveDisplay(undefined);

  assert.equal(display.font_family, NON_THEME_DEFAULTS.font_family);
  assert.equal(display.font_size, NON_THEME_DEFAULTS.font_size);
  assert.equal(display.height, NON_THEME_DEFAULTS.height);
  assert.equal(display.cursor_blink, NON_THEME_DEFAULTS.cursor_blink);
  assert.equal(display.scrollback, NON_THEME_DEFAULTS.scrollback);
  assert.equal(display.theme, DARK_THEME);
  assert.equal(display.themeAtom, "dark");
});

test("resolveDisplay lets the payload override individual defaults", () => {
  const display = resolveDisplay({ font_size: 18, height: "60vh" });

  assert.equal(display.font_size, 18);
  assert.equal(display.height, "60vh");
  // Untouched keys still come from the defaults.
  assert.equal(display.scrollback, NON_THEME_DEFAULTS.scrollback);
});

test("resolveDisplay records the atom for string themes and null for maps", () => {
  assert.equal(resolveDisplay({ theme: "light" }).themeAtom, "light");

  const custom = { background: "#000", foreground: "#fff", cursor: "#0f0" };
  const fromMap = resolveDisplay({ theme: custom });
  assert.equal(fromMap.theme, custom);
  assert.equal(fromMap.themeAtom, null);
});
