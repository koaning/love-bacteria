# Agent notes

This repo is a PICO-8 game: one cart (`pico8/<game>.p8`, where `<game>` is
`GAME` in `game.mk`) whose code lives in `#include`d `.lua` files. Notes on
this particular game are in `GAME.md`.

The toolchain comes from the koaning/geyser-pico8-template copier template.
Files it manages are overwritten by `copier update`, so fix shared tooling
there, not here: `Makefile`, `AGENTS.md`, `CLAUDE.md`, `.github/workflows/`,
`scripts/`, `site/`, `pico8/preview/{main,conf,synth}.lua`,
`tests/pico8_stub.lua` and `tools/{cart,label,p8tokens,pico8_env,serve,sfx}`.
Everything else (`game.mk`, `GAME.md`, `README.md`, the cart and its `.lua`
files, `pico8/preview/shots.lua`, `tests/test_*.lua`, `tests/cart_smoke.lua`,
`tools/scores.lua`, and any other tools) belongs to the game.

- Always finish with `make test` from the repo root. It runs every
  `tests/test_*.lua`, the cart smoke test (`tests/cart_smoke.lua`, which
  plays the cart through its buttons), the approximate 8192-token budget
  meter (`tools/p8tokens.lua`), and checks the cart's sound data is up to
  date (`tools/sfx.lua --check`). `game.mk` can add more via `TEST_EXTRA`.
- PICO-8 files (`pico8/*.lua`) use the Lua subset accepted by both PICO-8 and
  LuaJIT: no `+=`/`!=`/`?`, no `math.`/`table.`/`string.`/`ipairs`, and keep
  numbers within PICO-8's ±32767 fixed-point range. Use lowercase in strings
  (PICO-8 shows uppercase as small caps glyphs).
- `tools/pico8_env.lua` loads every file the cart `#include`s except
  `main.lua` into a sandbox with only PICO-8 builtins, so unit tests run the
  cart's own logic, and any non-PICO-8 global is an error.
  `tests/pico8_stub.lua` boots `main.lua` on top of that with a stubbed
  graphics/input API; `main.lua` only sees the other files' globals, not
  their `local`s.
- Sound is compiled from `tools/scores.lua` by `make music`; don't hand-edit
  the cart's `__sfx__`/`__music__` (unless `scores.lua` leaves `effects` out,
  in which case sfx below `first_sfx` are the cart's own).
- PICO-8 itself isn't installed in CI; `make smoke` boots the cart on a
  stubbed API, and `make serve` hosts the cart in the browser via
  `pico8/preview/` (a minimal PICO-8 stand-in player written in LÖVE). If the
  cart uses a PICO-8 API the preview player or the stub doesn't implement
  yet, add it there (in the template, so every game gets it).
- `make screenshots` (needs LÖVE; without a display use
  `make screenshots LOVE="xvfb-run -a love"`) replays `pico8/preview/shots.lua`
  and refreshes `docs/screenshots/` and the cart label. Rerun it after visual
  changes.
- When showing screenshots or visual previews to the user, embed the images
  directly inline in the conversation response rather than hiding them behind
  a separate markdown artifact.
