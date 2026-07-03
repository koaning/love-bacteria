# /// script
# requires-python = ">=3.14"
# dependencies = [
#     "altair==6.2.1",
#     "marimo>=0.23.9",
#     "pandas==3.0.3",
# ]
# ///

import marimo

__generated_with = "0.23.9"
app = marimo.App(width="medium")


@app.cell
def _():
    import json
    from pathlib import Path

    import altair as alt
    import marimo as mo
    import pandas as pd

    return Path, alt, json, mo, pd


@app.cell(hide_code=True)
def _(mo):
    mo.md("""
    # Training progress — win rate per opponent
    """)
    return


@app.cell
def _(mo):
    refresh = mo.ui.refresh(options=["10s", "30s", "1m"], default_interval="30s")
    refresh
    return (refresh,)


@app.cell(hide_code=True)
def _(Path, json, pd, refresh):
    refresh.value  # re-read the log on every tick

    rows = []
    for line in Path("games.jsonl").open():
        g = json.loads(line)
        if "batch" not in g:  # simulate games have no batch; skip
            continue
        net_is_p1 = g["p1"] == "net"
        rows.append({
            "batch": g["batch"],
            "opponent": g["p2"] if net_is_p1 else g["p1"],
            "win": g["winner"] == ("p1" if net_is_p1 else "p2"),
        })
    games = pd.DataFrame(rows)
    games.tail()
    return (games,)


@app.cell(hide_code=True)
def _(alt, games):
    BIN = 25  # batches per point
    binned = (
        games.assign(bin=(games.batch // BIN) * BIN)
        .groupby(["bin", "opponent"])
        .agg(win_rate=("win", "mean"), games=("win", "size"))
        .reset_index()
    )
    chart = (
        alt.Chart(binned)
        .mark_line(point=True)
        .encode(
            x=alt.X("bin:Q", title="batch"),
            y=alt.Y("win_rate:Q", title="win rate", scale=alt.Scale(domain=[0, 1])),
            color=alt.Color("opponent:N"),
            tooltip=["bin", "opponent", alt.Tooltip("win_rate", format=".2f"), "games"],
        )
        .properties(width=700, height=350)
    )
    chart
    return


if __name__ == "__main__":
    app.run()
