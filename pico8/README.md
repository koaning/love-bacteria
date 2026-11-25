# Sporeline — PICO-8 edition

```bash
pico8 -run sporeline.p8     # or `make pico8` from the repo root
```

The cart is `sporeline.p8`, which `#include`s:

| File | What | Mirrors |
| --- | --- | --- |
| `board.lua` | board state, cloning, starting layout | `love/src/board.lua`, `level.lua` |
| `rules.lua` | moves, conversion, passing, winner | `love/src/rules.lua` |
| `ai.lua` | easy / medium / hard bot | `love/src/ai.lua` |
| `main.lua` | title menu, 7×7 board, cursor, drawing, sfx; the look follows [Mossballs](https://koaning.io/posts/mossballs/) | — (PICO-8 only) |

Edit the `.lua` files in any editor. PICO-8 picks them up on `run`. To
export a standalone `.p8.png`/HTML, load the cart in PICO-8 and `save` /
`export`; includes get baked in at that point.

## Controls

- Title: ⬅️➡️ change bot difficulty, 🅾️ start. The board is always 7×7.
- Game: ⬆️⬇️⬅️➡️ move the cursor, 🅾️ select a bacterium and then a target, ❎ deselect.
  Dots are grow targets, rings are jump targets.

## Notes

- The bot runs in a coroutine and calls `ai_tick()`, which yields whenever
  the frame's CPU is ~80% used, so the screen keeps animating while it thinks.
- Both editions always play on a 7×7 board.
- Hard is a 2-ply minimax, the same as LÖVE, so it may think for a while on
  PICO-8's CPU.
- Before changing `board.lua`, `rules.lua` or `ai.lua`, read `../MIRROR.md`.

## Preview player (no PICO-8 needed)

`preview/` is a small PICO-8 stand-in written in LÖVE. It reads
`sporeline.p8`, resolves its `#include`s and runs the cart against a minimal
PICO-8 API: 128×128 framebuffer, the 16-colour palette, shapes, a 3×5 font,
buttons, coroutines, and a tiny synth for the `__sfx__` section.

```bash
make pico8-preview && love dist/sporeline-p8.love   # desktop
make serve                                          # browser, at /pico8/
```

It counts Lua VM instructions against PICO-8's ~4M/sec budget, so `stat(1)`
and the bot's thinking time are roughly what the real console would give.
Colours, font and sound are approximations. Use real PICO-8 to judge
how the cart looks and sounds.
