# Bacteria Prototype Handoff

## Goal

Build a greenfield LÖVE 2D desktop prototype inspired by the bacteria game from *The 7th Guest*.

## Implemented Scope

- Local LÖVE app with a fixed 7x7 board
- Human player versus simple deterministic AI
- Full turn loop with move selection, AI response, automatic passing, and end-game states
- Placeholder visuals with move highlighting and a HUD
- Repo-local setup and rules documentation

## Rules Implemented

- Player starts with bacteria at `(1,1)` and `(7,7)`.
- Enemy starts with bacteria at `(1,7)` and `(7,1)`.
- Grow moves can target any adjacent cell, including diagonals.
- Jump moves go exactly 2 cells up, down, left, or right.
- Jumping empties the origin cell.
- After either move, any adjacent enemy bacteria around the destination convert.
- Elimination ends the game immediately.
- If both sides have no legal moves, the side with more bacteria wins.
- If a side has no legal moves but still has bacteria, it passes automatically.

## Project Structure

- `conf.lua`: LÖVE window config
- `main.lua`: callback wiring
- `src/board.lua`: board helpers and cloning
- `src/level.lua`: single fixed starting layout
- `src/rules.lua`: move generation, application, passing, and win detection
- `src/ai.lua`: one-ply heuristic opponent
- `src/input.lua`: mouse and keyboard helpers
- `src/render.lua`: drawing, highlights, HUD, and winner overlay
- `src/game.lua`: state orchestration and AI timing
- `README.md`: run instructions and rules summary

## What To Expect

- Left click one of the teal bacteria to select it.
- Green highlights indicate grow moves.
- Blue highlights indicate jump moves.
- Press `R` to restart.
- Press `Esc` to quit.

## Verification Status

- Static review completed.
- Runtime verification was not possible in this workspace because `love`, `lua`, and `luac` are not installed here.

## Run On Another Machine

1. Install LÖVE 11.x from <https://love2d.org/>.
2. Open this repo.
3. Run:

```bash
love .
```

## Suggested Manual Checks

- Selection only works on player pieces.
- Adjacent growth keeps the origin occupied.
- Orthogonal jumps vacate the origin.
- Adjacent enemy bacteria convert after a move.
- AI takes valid turns and respects the same rules.
- Pass handling and end-game messaging work correctly.
