# /// script
# requires-python = ">=3.10"
# dependencies = ["torch>=2.0", "typer>=0.12", "numpy", "rich"]
# ///
"""Train a Sporeline agent with REINFORCE against a ladder of opponents.

    uv run train.py train                          # train on 7x7 (resumes checkpoint.pt)
    uv run train.py train --batches 50             # short smoke run
    uv run train.py simulate checkpoint.pt hard    # any mix of .pt paths and bot names
    uv run train.py watch --vs medium

The net starts against the easy AI and unlocks medium and self-play as its win
rate climbs. Self-play opponents are frozen snapshots: every --snapshot batches
the current net joins a sliding pool of the newest 5. Progress is a rich live
table. Weights are saved to weights.json (plain matrices, ready for a future
Lua loader) and checkpoint.pt (for resuming). Every game played — training and
simulate — is appended to games.jsonl, replayable through game.py.
"""
from __future__ import annotations

import json
import random
import sys
import time
from pathlib import Path

import torch
import torch.nn as nn
import typer
from rich.console import Console
from rich.live import Live
from rich.table import Table

sys.path.insert(0, str(Path(__file__).parent))
import game
from game import PLAYER, TIE, Bot

HERE = Path(__file__).parent
RUNGS = ("easy", "medium")  # scripted ladder; snapshot selves join the mix on their own
UNLOCK_WINRATE = 0.8
POOL_SIZE = 5  # frozen self opponents kept (sliding window of the last 5 snapshots)
WINKEY = {1: "p1", 2: "p2", TIE: "tie"}

app = typer.Typer(add_completion=False, help=__doc__.splitlines()[0])


class PolicyNet(nn.Module):
    """Two planes (mine, theirs) flattened -> hidden -> one logit per action."""

    def __init__(self, n, hidden=64):
        super().__init__()
        self.n = n
        self.hidden = hidden
        self.fc1 = nn.Linear(2 * n * n, hidden)
        self.fc2 = nn.Linear(hidden, n * n * game.N_DIRS)

    def forward(self, x):
        return self.fc2(torch.relu(self.fc1(x)))


def encode(state):
    """Board from the side-to-move's perspective, so one net plays both colours."""
    me = state.current
    opp = 3 - me
    planes = [1.0 if c == me else 0.0 for c in state.board]
    planes += [1.0 if c == opp else 0.0 for c in state.board]
    return torch.tensor(planes)


def net_agent(net, greedy=True):
    def agent(state, rng):
        with torch.no_grad():
            logits = net(encode(state))
            logits = logits.masked_fill(~torch.tensor(game.legal_mask(state)), -torch.inf)
            action = logits.argmax() if greedy else torch.distributions.Categorical(logits=logits).sample()
        return game.action_to_move(action.item(), state.n)
    return agent


def play_training_game(net, opponent, net_side, n, rng, ply_cap):
    """Net samples its moves; returns (observations, actions, masks, result, game_actions)."""
    state = game.new_game(n)
    obs, actions, masks, game_actions = [], [], [], []
    plies = 0
    while state.winner is None and plies < ply_cap:
        if state.current == net_side:
            with torch.no_grad():
                o = encode(state)
                mask = torch.tensor(game.legal_mask(state))
                logits = net(o).masked_fill(~mask, -torch.inf)
                action = torch.distributions.Categorical(logits=logits).sample()
            obs.append(o)
            actions.append(action)
            masks.append(mask)
            move = game.action_to_move(action.item(), n)
        else:
            move = opponent(state, rng)
        game_actions.append(game.move_to_str(move, n))
        state = game.resolve(game.apply_move(state, move))
        if state.pass_count > 0:  # the other side was stuck and auto-passed
            game_actions.append("pass")
        plies += 1
    result = state.winner if state.winner is not None else game.adjudicate(state)
    return obs, actions, masks, result, game_actions


def run_game(agent_p, agent_e, size, rng, ply_cap=200):
    """One full game with every move recorded; returns (result, actions)."""
    state = game.new_game(size)
    actions = []
    while state.winner is None and len(actions) < ply_cap:
        agent = agent_p if state.current == 1 else agent_e
        move = agent(state, rng)
        actions.append(game.move_to_str(move, size))
        state = game.resolve(game.apply_move(state, move))
        if state.pass_count > 0:  # the other side was stuck and auto-passed
            actions.append("pass")
    result = state.winner if state.winner is not None else game.adjudicate(state)
    return result, actions


def save(net, opt, batch, unlocked, ema):
    torch.save({"model": net.state_dict(), "opt": opt.state_dict(), "batch": batch,
                "unlocked": unlocked, "ema": ema, "size": net.n, "hidden": net.hidden},
               HERE / "checkpoint.pt")
    layers = [{"weights": layer.weight.tolist(), "bias": layer.bias.tolist()}
              for layer in (net.fc1, net.fc2)]
    spec = {
        "size": net.n,
        "hidden": net.hidden,
        "input": "2 planes (side-to-move's pieces, then opponent's), row-major, index = y*n + x",
        "action": "cell*12 + dir; dirs 0-7 grow (rules.lua ADJACENT_OFFSETS order), 8-11 jump",
        "forward": "relu(x @ W1' + b1) @ W2' + b2, mask illegal actions, argmax",
        "layers": layers,
    }
    (HERE / "weights.json").write_text(json.dumps(spec))


def load_net(path=None):
    ckpt = torch.load(path or HERE / "checkpoint.pt", weights_only=True)
    net = PolicyNet(ckpt["size"], ckpt["hidden"])
    net.load_state_dict(ckpt["model"])
    return net, ckpt


def status_table(batch, total_games, unlocked, ema, pool, avg_len, loss, secs):
    t = Table(title=f"batch {batch:,} · {total_games:,} games · {avg_len:.0f} plies/game "
                    f"· loss {loss:+.3f} · {secs:.1f}s/batch")
    t.add_column("opponent")
    t.add_column("win%", justify="right")
    t.add_column("")
    def bar_row(name, pct):
        filled = round(pct * 20)
        t.add_row(name, f"{100 * pct:.0f}%", f"[cyan]{'█' * filled}[dim]{'░' * (20 - filled)}")

    for i, rung in enumerate(RUNGS):
        if i >= unlocked:
            t.add_row(f"[dim]{rung}", "[dim]–", "[dim]locked")
        else:
            bar_row(rung, ema.get(rung, 0.0))
    if pool:
        for label, _ in pool:
            bar_row(f"self@{label}", ema.get(f"self@{label}", 0.0))
    else:
        t.add_row("[dim]self", "[dim]–", "[dim]no snapshots yet")
    return t


@app.command()
def train(size: int = 7,
          batches: int = 500,
          games: int = typer.Option(32, help="games per batch"),
          lr: float = 1e-3,
          entropy: float = 0.01,
          ply_cap: int = 200,
          snapshot: int = typer.Option(500, help="batches between frozen-self snapshots"),
          seed: int | None = None,
          fresh: bool = typer.Option(False, "--fresh", help="ignore an existing checkpoint.pt")):
    """Train with REINFORCE against the opponent ladder."""
    rng = random.Random(seed)
    torch.manual_seed(seed if seed is not None else rng.randrange(2**31))

    net = PolicyNet(size)
    opt = torch.optim.Adam(net.parameters(), lr=lr)
    start_batch, unlocked = 0, 1
    ema = {r: 0.0 for r in RUNGS}
    if not fresh and (HERE / "checkpoint.pt").exists():
        net, ckpt = load_net()
        if net.n != size:
            sys.exit(f"checkpoint.pt is for size {net.n}, not {size} (use --fresh to start over)")
        opt = torch.optim.Adam(net.parameters(), lr=lr)
        opt.load_state_dict(ckpt["opt"])
        start_batch, unlocked, ema = ckpt["batch"], min(ckpt["unlocked"], len(RUNGS)), ckpt["ema"]
        print(f"resumed at batch {start_batch}, rungs unlocked: {RUNGS[:unlocked]}")

    # one canonical training trace: --fresh restarts the log, resume appends
    log = (HERE / "games.jsonl").open("w" if fresh else "a")
    pool = []  # sliding window of frozen (label, net) snapshots
    if not fresh:
        snaps = sorted(HERE.glob("snapshot-*.pt"), key=lambda p: int(p.stem.split("-")[1]))
        for path in snaps[-POOL_SIZE:]:
            snap, _ = load_net(path)
            if snap.n == size:
                pool.append((path.stem.split("-")[1], snap))
        if pool:
            print(f"seeded pool from disk: {', '.join(label for label, _ in pool)}")

    def add_to_pool(label):
        snap = PolicyNet(size, net.hidden)
        snap.load_state_dict(net.state_dict())
        pool.append((label, snap))
        del pool[:-POOL_SIZE]

    console = Console()
    with Live(console=console, auto_refresh=False) as live:
        for batch in range(start_batch, start_batch + batches):
            t0 = time.time()
            all_obs, all_actions, all_masks, returns = [], [], [], []
            total_plies = 0
            for _ in range(games):
                # one ticket per unlocked scripted rung and per pool snapshot
                pick = rng.randrange(unlocked + len(pool))
                if pick < unlocked:
                    opp_name, opponent = RUNGS[pick], game.AIS[RUNGS[pick]]
                else:
                    label, snap = pool[pick - unlocked]
                    opp_name, opponent = f"self@{label}", net_agent(snap, greedy=False)
                net_side = rng.choice((1, 2))
                obs, actions, masks, result, game_actions = play_training_game(
                    net, opponent, net_side, size, rng, ply_cap)
                reward = 1.0 if result == net_side else 0.0 if result == TIE else -1.0
                all_obs += obs
                all_actions += actions
                all_masks += masks
                returns += [reward] * len(obs)
                total_plies += len(game_actions)
                ema[opp_name] = 0.97 * ema.get(opp_name, 0.0) + 0.03 * (1.0 if reward > 0 else 0.0)
                log.write(json.dumps({
                    "batch": batch, "size": size,
                    "p1": "net" if net_side == 1 else opp_name,
                    "p2": opp_name if net_side == 1 else "net",
                    "winner": WINKEY[result], "actions": game_actions}) + "\n")
            log.flush()

            # REINFORCE: per-batch whitened returns as the baseline.
            obs = torch.stack(all_obs)
            actions = torch.stack(all_actions)
            masks = torch.stack(all_masks)
            ret = torch.tensor(returns)
            adv = (ret - ret.mean()) / (ret.std() + 1e-8)
            logits = net(obs).masked_fill(~masks, -torch.inf)
            dist = torch.distributions.Categorical(logits=logits)
            loss = -(adv * dist.log_prob(actions)).mean() - entropy * dist.entropy().mean()
            opt.zero_grad()
            loss.backward()
            opt.step()

            # Unlock the next rung once we reliably beat the newest one.
            if unlocked < len(RUNGS) and ema[RUNGS[unlocked - 1]] > UNLOCK_WINRATE:
                unlocked += 1
                live.console.print(f"[bold green]unlocked opponent: {RUNGS[unlocked - 1]}")
            if (batch + 1) % snapshot == 0:
                add_to_pool(str(batch + 1))
                torch.save({"model": net.state_dict(), "size": size, "hidden": net.hidden},
                           HERE / f"snapshot-{batch + 1}.pt")
                live.console.print(f"[bold cyan]snapshot-{batch + 1}.pt added to the pool")
            if (batch + 1) % 20 == 0:
                save(net, opt, batch + 1, unlocked, ema)

            live.update(status_table(batch + 1, (batch + 1 - start_batch) * games, unlocked, ema, pool,
                                     total_plies / games, loss.item(), time.time() - t0),
                        refresh=True)

    log.close()
    save(net, opt, start_batch + batches, unlocked, ema)
    print(f"saved checkpoint.pt and weights.json ({sum(p.numel() for p in net.parameters())} params)")


@app.command()
def simulate(p1: str = typer.Argument("checkpoint.pt", help="checkpoint .pt path, or easy/medium/hard"),
             p2: str = typer.Argument("easy", help="checkpoint .pt path, or easy/medium/hard"),
             n: int = typer.Option(100, "-n"),
             size: int = typer.Option(7, help="board size (only used when neither side is a checkpoint)"),
             greedy: bool = typer.Option(False, help="checkpoints play argmax instead of sampling"),
             seed: int | None = None):
    """Pit two players against each other, alternating colours, logging every game."""
    rng = random.Random(seed)

    def make_player(spec):
        if spec in game.AIS:
            return game.AIS[spec], None
        net, _ = load_net(Path(spec) if Path(spec).is_absolute() else HERE / spec)
        return net_agent(net, greedy=greedy), net.n

    agent1, n1 = make_player(p1)
    agent2, n2 = make_player(p2)
    if n1 and n2 and n1 != n2:
        sys.exit(f"checkpoint sizes differ: {n1} vs {n2}")
    board_size = n1 or n2 or size

    wins = {"p1": 0, "p2": 0, "tie": 0}
    with (HERE / "games.jsonl").open("a") as log:
        for i in range(n):
            first, second = ((agent1, agent2), (agent2, agent1))[i % 2]
            result, actions = run_game(first, second, board_size, rng)
            key = WINKEY[result]
            if i % 2 == 1 and key != "tie":  # undo the colour swap in the tally
                key = "p1" if key == "p2" else "p2"
            wins[key] += 1
            log.write(json.dumps({
                "size": board_size,
                "p1": p1 if i % 2 == 0 else p2,
                "p2": p2 if i % 2 == 0 else p1,
                "winner": WINKEY[result], "actions": actions}) + "\n")
            if sys.stdout.isatty():
                print(f"\r{i + 1}/{n}", end="", flush=True)
    print(f"\r{p1} vs {p2} on {board_size}x{board_size} ({n} games): "
          f"{wins['p1']} - {wins['p2']} ({wins['tie']} ties)")


@app.command()
def watch(vs: Bot = Bot.easy,
          ckpt: str | None = None,
          delay: float = 0.3,
          seed: int | None = None):
    """ASCII playback of the net (●) vs a scripted AI (○)."""
    net, _ = load_net(ckpt)
    rng = random.Random(seed)

    def show(state):
        print("\033[2J\033[H" + game.render(state))
        time.sleep(delay)

    result = game.play(net_agent(net), game.AIS[vs.value], n=net.n, rng=rng, on_state=show)
    print("\nwinner: " + {1: "net (●)", 2: f"{vs.value} (○)", TIE: "nobody — tie"}[result])


if __name__ == "__main__":
    if len(sys.argv) == 1:
        sys.argv.append("--help")
    app()
