# The mirror

Sporeline ships as two games that share one brain:

| LÖVE (`love/src/`) | PICO-8 (`pico8/`) | Mirrored? |
| --- | --- | --- |
| `ai.lua` | `ai.lua` | **yes, move for move** |
| `rules.lua` | `rules.lua` | yes (the AI depends on it) |
| `board.lua` + `level.lua` | `board.lua` | yes |
| `game.lua`, `render.lua`, `audio.lua`, `input.lua` | `main.lua` | no. Each edition does its own thing |

The AI is the part that matters. Graphics, audio, menus and juice can go as
far as each platform allows: LÖVE can be lavish, PICO-8 lives in 128×128.
But a given board must get the same move from both bots.

There are deliberately **two copies**, side by side, each idiomatic enough for
its platform. Keeping them in step is a porting job, and `make mirror` is
the referee.

## The referee: `make mirror`

`tests/mirror_match.lua` loads both brains in one LuaJIT process and has
them play full 7×7 games (every difficulty pairing, fixed seeds). Both
sides draw from the same scripted random numbers, so even Easy and Medium are
deterministic. After every ply it checks:

- both AIs chose the same move,
- both rule engines produced the same board, turn, pass count and winner,
- no PICO-8 score leaves 16.16 fixed-point range (|n| ≤ 32767).

The first disagreement prints the board and both moves, then exits 1.

The PICO-8 files are loaded into a sandbox with **only PICO-8 builtins**
(`tools/pico8_env.lua`), so the referee also lints the dialect:

- `math.*`, `table.*`, `string.*`, `ipairs`, `require` → "touched undefined global"
- `+=`, `!=`, `?` shorthand → LuaJIT parse error

## Porting cheatsheet

| LÖVE | PICO-8 |
| --- | --- |
| `AI.choose_move`, `Rules.apply_move`, … | `ai_choose_move`, `rules_apply_move`, … |
| `require("src.x")` | `#include x.lua` in `sporeline.p8` |
| `for _, v in ipairs(t)` | `for v in all(t)` |
| `t[#t + 1] = v` | `add(t, v)` |
| `math.abs`, `math.floor` | `abs`, `flr` |
| `love.math.random(n)` | `flr(rnd(n)) + 1` |
| `table.concat` | `..` |
| `math.huge`, big constants | stay under 32767 (`INFINITY = 32000`, `WIN_SCORE = 10000`) |
| `status_text` strings | dropped; the cart draws its own HUD |
| tight loops | call `ai_tick()` so the cart can `yield()` mid-search |

Mirrored PICO-8 files use only syntax both runtimes accept: no `+=`, `!=` or
`?`. `pico8/main.lua` isn't mirrored, so it could use PICO-8 shorthand. It
avoids it anyway so that `make smoke` can run it.

## Changing the AI

1. Change `love/src/ai.lua` (or the PICO-8 side, either direction is fine).
2. Port the same change to the twin file. Keep the function order the same
   so a side-by-side diff stays readable.
3. `make test`: LÖVE unit tests, mirror match, cart smoke, token meter.
4. If a change is *meant* to be platform-specific (e.g. a cheaper Hard search
   just for PICO-8), make it a named difficulty, not a silent divergence, and
   teach `tests/mirror_match.lua` which pairs to compare.
