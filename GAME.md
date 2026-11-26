# Mossballs

marimo strategy

Notes for agents about this game (the toolchain notes are in AGENTS.md).

- Code: `pico8/mossballs.p8` `#include`s `board.lua` (7×7 board state and
  starting layout), `rules.lua` (grow/jump moves, conversions, passing, win
  detection), `ai.lua` (easy/medium/hard bots; hard is 2-ply alpha-beta
  minimax), and `main.lua` (title menu, light/dark themes, 3D organic blob
  renderer, animations, HUD).
- Unit tests live in `tests/test_brain.lua`. `ai.lua` calls `ai_tick()` in its
  hot loops so `main.lua` can `yield()` when `stat(1) > 0.8`; tests pass a
  no-op via `pico8_env.new(".", rng, { globals = { ai_tick = function() end } })`.
- Sound: `tools/scores.lua` sets `first_sfx = 8` and omits `effects`, so the
  cart keeps its hand-made sfx 0–7 (0 grow, 1 capture, 2 invalid). The two
  songs compile into sfx 8+ and `__music__`: title `music(0)` ("sprout
  parade") and game `music(4)` ("moss garden"), using channels 0–1 (mask 3)
  so sfx keep channels 2–3.
- Screenshots: `pico8/preview/shots.lua` captures the title screen
  (`pico8-title.png`, `pico8-cart.png`, and `__label__`) and a mid-game board
  (`pico8.png`).
