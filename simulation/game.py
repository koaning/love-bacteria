# /// script
# requires-python = ">=3.10"
# dependencies = ["typer>=0.12"]
# ///
"""Sporeline game engine — a faithful Python port of src/rules.lua + src/ai.lua.

The engine itself is stdlib-only; typer is used for the CLI. The board is a
flat list of ints (0 empty, 1 player, 2 enemy), index = y * n + x, 0-indexed.
Rules ported: grow to any of 8 neighbours (origin stays), jump exactly 2 cells
orthogonally (origin vacated), landing converts all 8-adjacent enemy pieces,
a stuck side auto-passes, both stuck ends the game on piece count, 0 pieces
loses immediately.

    uv run game.py watch hard medium
    uv run game.py arena hard easy -n 100
    uv run game.py selftest
"""
from __future__ import annotations

import random
import sys
import time
from dataclasses import dataclass, field, replace
from enum import Enum

import typer

EMPTY, PLAYER, ENEMY, TIE = 0, 1, 2, 3
NAMES = {PLAYER: "player", ENEMY: "enemy", TIE: "tie"}
WIN_SCORE = 100_000

# Offsets in the exact order of src/rules.lua (matters for hard-AI tie-breaks).
ADJACENT = ((-1, -1), (0, -1), (1, -1), (-1, 0), (1, 0), (-1, 1), (0, 1), (1, 1))
JUMPS = ((0, -2), (2, 0), (0, 2), (-2, 0))
N_DIRS = 12  # action space per cell: dirs 0-7 grow, 8-11 jump


@dataclass
class State:
    n: int
    board: list = field(default_factory=list)
    current: int = PLAYER
    pass_count: int = 0
    winner: int | None = None
    last_converted: int = 0


_TABLES: dict[int, tuple[list, list]] = {}


def tables(n):
    """Per-cell move targets. grow/jump are dir-indexed (-1 = off-board);
    grow_mv/jump_mv are (target, dir) pairs with off-board entries dropped."""
    if n not in _TABLES:
        grow, jump, grow_mv, jump_mv = [], [], [], []
        for y in range(n):
            for x in range(n):
                grow.append(tuple(
                    (y + dy) * n + (x + dx) if 0 <= x + dx < n and 0 <= y + dy < n else -1
                    for dx, dy in ADJACENT))
                jump.append(tuple(
                    (y + dy) * n + (x + dx) if 0 <= x + dx < n and 0 <= y + dy < n else -1
                    for dx, dy in JUMPS))
                grow_mv.append(tuple((t, d) for d, t in enumerate(grow[-1]) if t >= 0))
                jump_mv.append(tuple((t, d + 8) for d, t in enumerate(jump[-1]) if t >= 0))
        _TABLES[n] = (grow, jump, grow_mv, jump_mv)
    return _TABLES[n]


def new_game(n=7):
    board = [EMPTY] * (n * n)
    board[0] = board[n * n - 1] = PLAYER  # (1,1) and (N,N) in src/level.lua
    board[n - 1] = board[n * (n - 1)] = ENEMY  # (N,1) and (1,N)
    return State(n, board)


def legal_moves(state, side=None):
    """Moves as (from, to, dir) tuples, enumerated in src/rules.lua's order."""
    side = state.current if side is None else side
    _, _, grow_mv, jump_mv = tables(state.n)
    board = state.board
    moves = []
    for cell, piece in enumerate(board):
        if piece != side:
            continue
        for t, d in grow_mv[cell]:
            if board[t] == EMPTY:
                moves.append((cell, t, d))
        for t, d in jump_mv[cell]:
            if board[t] == EMPTY:
                moves.append((cell, t, d))
    return moves


def has_any_move(state, side):
    _, _, grow_mv, jump_mv = tables(state.n)
    board = state.board
    for cell, piece in enumerate(board):
        if piece != side:
            continue
        for t, _ in grow_mv[cell]:
            if board[t] == EMPTY:
                return True
        for t, _ in jump_mv[cell]:
            if board[t] == EMPTY:
                return True
    return False


def count_moves(state, side):
    _, _, grow_mv, jump_mv = tables(state.n)
    board = state.board
    count = 0
    for cell, piece in enumerate(board):
        if piece != side:
            continue
        for t, _ in grow_mv[cell]:
            if board[t] == EMPTY:
                count += 1
        for t, _ in jump_mv[cell]:
            if board[t] == EMPTY:
                count += 1
    return count


def apply_move(state, move):
    frm, to, d = move
    side = state.current
    opp = 3 - side
    board = state.board.copy()
    if d >= 8:  # jump vacates the origin; grow keeps it
        board[frm] = EMPTY
    board[to] = side
    converted = 0
    for t, _ in tables(state.n)[2][to]:
        if board[t] == opp:
            board[t] = side
            converted += 1
    return State(state.n, board, opp, 0, None, converted)


def winner(state):
    p = state.board.count(PLAYER)
    e = state.board.count(ENEMY)
    if p == 0 and e == 0:
        return TIE
    if p == 0:
        return ENEMY
    if e == 0:
        return PLAYER
    # Equivalent to src/rules.lua's "both sides have no legal moves" check:
    # any maximal empty region borders at least one piece, which can grow into
    # it, so with pieces on the board somebody can move unless the board is full.
    if EMPTY in state.board:
        return None
    return PLAYER if p > e else ENEMY if e > p else TIE


def resolve(state):
    """Post-move bookkeeping: declare a winner, or auto-pass a stuck side."""
    w = winner(state)
    if w is not None:
        return replace(state, winner=w)
    if has_any_move(state, state.current):
        return state
    return replace(state, current=3 - state.current, pass_count=state.pass_count + 1)


def adjudicate(state):
    """Most pieces wins — used when a game hits the ply cap (the Lua game instead
    relies on a repetition filter in its AI; a hard cap is simpler for RL)."""
    p = state.board.count(PLAYER)
    e = state.board.count(ENEMY)
    return PLAYER if p > e else ENEMY if e > p else TIE


# --- action encoding shared with train.py: action = cell * 12 + dir ------------


def move_to_action(move):
    return move[0] * N_DIRS + move[2]


def action_to_move(action, n):
    cell, d = divmod(action, N_DIRS)
    target = tables(n)[0][cell][d] if d < 8 else tables(n)[1][cell][d - 8]
    return (cell, target, d)


def legal_mask(state):
    mask = [False] * (state.n * state.n * N_DIRS)
    for move in legal_moves(state):
        mask[move_to_action(move)] = True
    return mask


def move_to_str(move, n):
    """Readable form 'x,y>x,y', 1-indexed like the Lua game. Distance 2 = jump."""
    f, t, _ = move
    return f"{f % n + 1},{f // n + 1}>{t % n + 1},{t // n + 1}"


def str_to_move(s, n):
    fr, to = s.split(">")
    fx, fy = map(int, fr.split(","))
    tx, ty = map(int, to.split(","))
    dx, dy = tx - fx, ty - fy
    d = ADJACENT.index((dx, dy)) if max(abs(dx), abs(dy)) == 1 else 8 + JUMPS.index((dx, dy))
    return ((fy - 1) * n + (fx - 1), (ty - 1) * n + (tx - 1), d)


# --- scripted AIs, ported from src/ai.lua --------------------------------------


def _center_bonus(to, n):
    x, y = to % n, to // n
    c = (n - 1) / 2
    return 8 - (abs(x - c) + abs(y - c))


def _evaluate(state, perspective):
    opp = 3 - perspective
    if state.winner == perspective:
        return WIN_SCORE
    if state.winner == opp:
        return -WIN_SCORE
    if state.winner == TIE:
        return 0
    diff = state.board.count(perspective) - state.board.count(opp)
    return diff * 8 + count_moves(state, perspective) * 5 - count_moves(state, opp) * 6


def _score_move(state, move):
    side = state.current
    opp = 3 - side
    nxt = resolve(apply_move(state, move))
    converted = nxt.last_converted
    if nxt.winner == side:
        return WIN_SCORE + converted
    if nxt.winner == opp:
        return -WIN_SCORE
    diff = nxt.board.count(side) - nxt.board.count(opp)
    return (converted * 100 + diff * 8
            + count_moves(nxt, side) * 5 - count_moves(nxt, opp) * 6
            + _center_bonus(move[1], state.n))


def _better(move, score, best, best_score, n):
    """src/ai.lua compare_moves: score, then grow over jump, then to/from position."""
    if best is None:
        return True
    if score != best_score:
        return score > best_score
    if (move[2] < 8) != (best[2] < 8):
        return move[2] < 8
    for a, b in ((move[1] // n, best[1] // n), (move[1] % n, best[1] % n),
                 (move[0] // n, best[0] // n), (move[0] % n, best[0] % n)):
        if a != b:
            return a < b
    return False


def _minimax(state, perspective, depth, alpha, beta):
    if state.winner is not None or depth == 0:
        return _evaluate(state, perspective)
    moves = legal_moves(state)
    if not moves:
        return _evaluate(state, perspective)
    if state.current == perspective:
        best = -float("inf")
        for move in moves:
            best = max(best, _minimax(resolve(apply_move(state, move)), perspective,
                                      depth - 1, alpha, beta))
            alpha = max(alpha, best)
            if alpha >= beta:
                break
        return best
    best = float("inf")
    for move in moves:
        best = min(best, _minimax(resolve(apply_move(state, move)), perspective,
                                  depth - 1, alpha, beta))
        beta = min(beta, best)
        if alpha >= beta:
            break
    return best


def random_ai(state, rng):
    return rng.choice(legal_moves(state))


def easy_ai(state, rng):
    moves = legal_moves(state)
    grows = [m for m in moves if m[2] < 8]
    return rng.choice(grows or moves)


def medium_ai(state, rng):
    moves = legal_moves(state)
    best, best_score = None, None
    for move in moves:
        score = _score_move(state, move)
        if _better(move, score, best, best_score, state.n):
            best, best_score = move, score
    if rng.randrange(3) == 0:
        return rng.choice(moves)
    return best


def hard_ai(state, rng=None, depth=2):
    side = state.current
    best, best_score = None, None
    for move in legal_moves(state):
        nxt = resolve(apply_move(state, move))
        score = _minimax(nxt, side, depth - 1, -float("inf"), float("inf"))
        if _better(move, score, best, best_score, state.n):
            best, best_score = move, score
    return best


AIS = {"random": random_ai, "easy": easy_ai, "medium": medium_ai, "hard": hard_ai}


# --- playing and rendering ------------------------------------------------------


def play(agent_p, agent_e, n=7, ply_cap=200, rng=None, on_state=None):
    """Run one game; agents are functions (state, rng) -> move. Returns the winner."""
    rng = rng or random.Random()
    state = new_game(n)
    if on_state:
        on_state(state)
    plies = 0
    while state.winner is None and plies < ply_cap:
        agent = agent_p if state.current == PLAYER else agent_e
        state = resolve(apply_move(state, agent(state, rng)))
        plies += 1
        if on_state:
            on_state(state)
    return state.winner if state.winner is not None else adjudicate(state)


def render(state):
    chars = {EMPTY: "·", PLAYER: "●", ENEMY: "○"}
    rows = []
    for y in range(state.n):
        cells = " ".join(chars[state.board[y * state.n + x]] for x in range(state.n))
        rows.append(f"{y + 1:2d}  {cells}")
    rows.append("    " + " ".join(str(x + 1) for x in range(state.n)))
    p, e = state.board.count(PLAYER), state.board.count(ENEMY)
    rows.append(f"● {p}  ○ {e}   to move: {NAMES.get(state.current, '?')}")
    return "\n".join(rows)


class Bot(str, Enum):
    random = "random"
    easy = "easy"
    medium = "medium"
    hard = "hard"


app = typer.Typer(add_completion=False,
                  help="Sporeline engine: watch bots play, run arenas, selftest.")


@app.command()
def watch(a: Bot, b: Bot, size: int = 7, delay: float = 0.3, seed: int | None = None):
    """Watch two bots play in ASCII (a is ●, b is ○)."""
    rng = random.Random(seed)

    def show(state):
        print("\033[2J\033[H" + render(state))
        time.sleep(delay)

    result = play(AIS[a.value], AIS[b.value], n=size, rng=rng, on_state=show)
    side = {PLAYER: f"{a.value} (●)", ENEMY: f"{b.value} (○)", TIE: "nobody — tie"}[result]
    print(f"\nwinner: {side}")


@app.command()
def arena(a: Bot, b: Bot, n: int = typer.Option(100, "-n"), size: int = 7,
          seed: int | None = None):
    """Bot-vs-bot win-rate table, alternating colours."""
    rng = random.Random(seed)
    wins = {a.value: 0, b.value: 0, "tie": 0}
    start = time.time()
    for i in range(n):
        if i % 2 == 0:  # alternate colours for fairness
            result = play(AIS[a.value], AIS[b.value], n=size, rng=rng)
            name = {PLAYER: a.value, ENEMY: b.value, TIE: "tie"}[result]
        else:
            result = play(AIS[b.value], AIS[a.value], n=size, rng=rng)
            name = {PLAYER: b.value, ENEMY: a.value, TIE: "tie"}[result]
        wins[name] += 1
        if sys.stdout.isatty():
            print(f"\r{i + 1}/{n}", end="", flush=True)
    secs = time.time() - start
    print(f"\r{n} games on {size}x{size} in {secs:.1f}s")
    for name in (a.value, b.value, "tie"):
        print(f"  {name:>8}: {wins[name]:4d}  ({100 * wins[name] / n:.0f}%)")


@app.command()
def selftest():
    """Rule sanity checks mirroring tests/test_rules.lua."""
    # Initial position: 2 pieces each, corner piece has 3 grows + 2 jumps.
    s = new_game(5)
    assert s.board.count(PLAYER) == 2 and s.board.count(ENEMY) == 2
    assert len(legal_moves(s, PLAYER)) == 10

    # Grow keeps the origin and converts the adjacent enemy.
    s = State(5, [EMPTY] * 25, PLAYER)
    s.board[12] = PLAYER  # (3,3)
    s.board[6] = ENEMY  # (2,2)
    s.board[18] = ENEMY  # (4,4)
    nxt = apply_move(s, (12, 7, 1))  # grow up to (3,2)
    assert nxt.board[12] == PLAYER and nxt.board[7] == PLAYER
    assert nxt.board[6] == PLAYER and nxt.last_converted == 1
    assert nxt.board[18] == ENEMY and nxt.current == ENEMY

    # Jump vacates the origin.
    nxt = apply_move(s, (12, 2, 8))  # jump up two to (3,1)
    assert nxt.board[12] == EMPTY and nxt.board[2] == PLAYER

    # tests/test_rules.lua: stuck player passes when the enemy can still move.
    s = State(7, [ENEMY] * 49, PLAYER)
    s.board[0] = PLAYER
    s.board[48] = s.board[47] = s.board[41] = EMPTY  # (7,7), (6,7), (7,6)
    r = resolve(s)
    assert r.current == ENEMY and r.winner is None
    assert not has_any_move(r, PLAYER)

    # tests/test_rules.lua: both stuck -> enemy wins on piece count.
    s = State(3, [ENEMY] * 9, PLAYER)
    s.board[0] = PLAYER
    r = resolve(s)
    assert r.winner == ENEMY

    # Elimination: converting the last player piece ends the game at once.
    s = State(5, [EMPTY] * 25, ENEMY)
    s.board[0] = PLAYER  # (1,1)
    s.board[15] = ENEMY  # (1,4)
    r = resolve(apply_move(s, (15, 5, 8)))  # jump to (1,2), converting (1,1)
    assert r.board.count(PLAYER) == 0 and r.winner == ENEMY

    # Action and string encodings round-trip for every legal move.
    s = new_game(7)
    for move in legal_moves(s):
        assert action_to_move(move_to_action(move), 7) == move
        assert str_to_move(move_to_str(move, 7), 7) == move
    assert sum(legal_mask(s)) == len(legal_moves(s))

    print("all selftests passed")


if __name__ == "__main__":
    if len(sys.argv) == 1:
        sys.argv.append("--help")
    app()
