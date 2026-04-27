// Placeholder — real bundle (xterm.js + FitAddon + Kino bridge) lands in
// chunk 3. This file exists so `use Kino.JS, assets_path: ...` doesn't
// emit a missing-asset warning at compile time.
export function init(ctx, _payload) {
  ctx.root.innerText = "kino_ex_ratatui: JS bundle not built yet (run `cd assets && npm run build`).";
}
