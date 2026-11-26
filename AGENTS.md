# Agent notes

This repo holds **Mossballs**, a PICO-8 strategy game (`pico8/mossballs.p8`
and `#include`d `.lua` files).

- Always finish with `make test` from the repo root. It runs brain unit tests
  (`tests/test_brain.lua`), the cart smoke test (`tests/cart_smoke.lua`), and
  the approximate 8192-token budget meter (`tools/p8tokens.lua`).
- PICO-8 files (`pico8/*.lua`) use the Lua subset accepted by both PICO-8 and
  LuaJIT: no `+=`/`!=`/`?`, no `math.`/`table.`/`string.`/`ipairs`, and keep
  numbers within PICO-8's ±32767 fixed-point range.
- PICO-8 itself isn't installed in CI; `make smoke` boots the cart on a
  stubbed API, and `make serve` hosts the cart in the browser via
  `pico8/preview/` (a minimal PICO-8 stand-in player). If the cart uses a
  PICO-8 API `pico8/preview/` doesn't implement yet, add it there.
- When showing screenshots or visual previews to the user, embed the images
  directly inline in the conversation response rather than hiding them behind
  a separate markdown artifact.
