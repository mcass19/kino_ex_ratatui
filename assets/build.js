// esbuild bundle script for the kino_ex_ratatui widget.
//
// Inputs:
//   js/main.js  — entrypoint, imports xterm + FitAddon + xterm.css
//
// Outputs:
//   ../lib/assets/kino_ex_ratatui/main.js
//   ../lib/assets/kino_ex_ratatui/main.css   (auto-extracted from CSS imports)
//
// Run via `npm run build` (minified) or `npm run build:dev` (sourcemaps).
import * as esbuild from "esbuild";

const dev = process.argv.includes("--dev");

await esbuild.build({
  entryPoints: ["js/main.js"],
  outdir: "../lib/assets/kino_ex_ratatui",
  bundle: true,
  format: "esm",
  target: ["es2020"],
  minify: !dev,
  sourcemap: dev,
  logLevel: "info",
});
