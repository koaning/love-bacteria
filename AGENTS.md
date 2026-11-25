# Agent notes

This repo holds two editions of Sporeline: `love/` (LÖVE 11.5, the ambitious
graphics) and `pico8/` (PICO-8 cart). Read `MIRROR.md` first.

- `love/src/ai.lua` ↔ `pico8/ai.lua`, `love/src/rules.lua` ↔ `pico8/rules.lua`,
  `love/src/board.lua`+`level.lua` ↔ `pico8/board.lua` are **twins**. Any
  behavioural change to one must be ported to the other in the same change.
- Always finish with `make test` from the repo root. It runs `make mirror`,
  which fails on the first move where the two AIs disagree.
- Mirrored PICO-8 files: no `+=`/`!=`/`?`, no `math.`/`table.`/`string.`/
  `ipairs`, numbers stay within ±32767.
- Rendering, audio, menus and input are per-edition and need not match.
- PICO-8 itself isn't installed in CI; `make smoke` boots the cart on a
  stubbed API, and `make tokens` approximates the 8192-token budget.
- `make serve` hosts both editions on one page (love.js). The PICO-8 page
  uses `pico8/preview/`, a LÖVE stand-in for PICO-8. If the cart uses a
  PICO-8 API it doesn't implement yet, add it there.
