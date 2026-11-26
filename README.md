# Mossballs

A bacteria strategy game for **PICO-8** (128×128, 16 colours, 3 sound effects),
inspired by the bacteria puzzle from *The 7th Guest*.

| Cartridge | Gameplay |
| --- | --- |
| ![PICO-8 cartridge](docs/screenshots/pico8-cart.png) | ![PICO-8 gameplay](docs/screenshots/pico8.png) |

## Play

### In PICO-8

```bash
make pico8    # runs: pico8 -run pico8/mossballs.p8 (set PICO8=/path/to/pico8 if needed)
```

### In a browser (no PICO-8 binary required)

```bash
make fetch-lovejs   # once: download the love.js runtime for the preview player
make serve          # build dist/site and serve it on :8000 (PORT=9000 to change)
```

`make serve` builds `dist/site/` and serves it with the COOP/COEP headers the
browser player needs:

- `/`: the cart running on `pico8/preview/`, a small PICO-8 stand-in player
- `/official/`: also included when the `pico8` binary is installed (real PICO-8 HTML export)
