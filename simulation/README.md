# Simulation & RL

A two-file Python stack: `game.py` re-implements the Lua rules (the engine is
stdlib-only), `train.py` trains a tiny policy network against the game's AIs.
Both are uv scripts with typer CLIs — no install step needed.

```sh
uv run game.py selftest                # rule sanity checks
uv run game.py watch hard medium       # watch two bots play in ASCII
uv run game.py arena hard easy -n 100  # win-rate table

uv run train.py train                        # train on 7x7 (resumes checkpoint.pt)
uv run train.py simulate checkpoint.pt hard  # pit any two players: .pt paths or bot names
uv run train.py watch --vs easy              # watch the trained net play
```

Training shows a live table with EMA win rates per opponent. The net starts
against `easy`, then unlocks `medium` and self-play once it wins >80% against
the newest rung. Self-play opponents come from a sliding pool: every
`--snapshot` batches (default 500) the current net is frozen, saved as
`snapshot-<batch>.pt`, and added to the pool (newest 3 kept), so old selves
can also be pitted against new ones with `simulate`. `hard` is not a training
opponent (its search makes games ~100x slower) — use it as the benchmark:
`uv run train.py simulate checkpoint.pt hard`.

Weights land in `weights.json` — plain matrices plus a description of the
input/action encoding, ready for a future pure-Lua forward pass in the game.
`checkpoint.pt` holds the optimizer state for resuming; pass `--fresh` to
start over.

Every game played — during training and `simulate` — is appended to
`games.jsonl`: one line per game with both players, the winner, and the moves
as `"x,y>x,y"` strings (1-indexed, distance 2 = jump; `"pass"` when a stuck
side auto-passed), replayable through `game.str_to_move` for analysis or
future offline training. Moves strictly alternate sides, p1 first.

Fun fact discovered while building this: `easy` (random grow) beats `medium`
(greedy) about 85% of the time — greedy chases conversions with jumps and
bleeds material. Verified against the real Lua engine, not a porting bug.
