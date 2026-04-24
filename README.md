# Sporeline

A small LÖVE 2D strategy game inspired by the bacteria puzzle from *The 7th Guest*.

## Requirements

- Install LÖVE 11.x from [love2d.org](https://love2d.org/).

## Run

From this directory:

```bash
love .
```

On macOS, if `love` is not on your `PATH`, launch the `.app` and open this folder as a project or add the CLI wrapper manually.
If macOS blocks `love` with a developer verification warning, remove quarantine first:

```bash
xattr -dr com.apple.quarantine /Applications/love.app
```

## Tests

Run the lightweight Lua test suite:

```bash
luajit tests/run.lua
```

## Build

Create distributable output:

```bash
make build
```

This creates `dist/sporeline.love` and, on macOS, a standalone app bundle at `dist/Sporeline.app`.

## Steam Deck

Sporeline runs on Steam Deck as a Non-Steam game via a Linux AppImage. Native gamepad support is built in (D-pad + ABXY + shoulders + Start), so the Deck's controls work with no Steam Input remapping.

- Build the AppImage: push a git tag (CI attaches `Sporeline-x86_64.AppImage` to the release) or run `make appimage` on a Linux host.
- Full walkthrough — one-time Deck setup over SSH, install script, and future updates from your Mac — is in [STEAMDECK.md](STEAMDECK.md).

## Web Build (Playable Embed)

To prepare a browser-playable build:

1. Download the web runtime:

```bash
make fetch-lovejs
```

2. Build the web package:

```bash
make web
```

This creates `dist/web/` with:
- `index.html` player page
- `sporeline.love` game package
- header config files (`_headers`, `.htaccess`) required by `love.js`

Deploy `dist/web/` to a host where you can set these headers:

- `Cross-Origin-Opener-Policy: same-origin`
- `Cross-Origin-Embedder-Policy: require-corp`

Then embed in your blog with an iframe:

```html
<iframe
  src="https://games.your-domain.com/sporeline/"
  width="900"
  height="900"
  style="border:0;max-width:100%;"
  loading="lazy"
></iframe>
```

If your blog platform cannot set those headers, host the game on a separate static host/subdomain and embed that URL.

For local testing, serve `dist/web/` (not the source `web/` folder):

```bash
cd dist/web
python3 -m http.server 8000
```

## Controls

- Main menu: click `Play`, choose `5x5`, `7x7`, or `9x9`, pick bot difficulty (`Easy`, `Medium`, or `Hard`), then click `Start`.
- Menu keyboard: `Arrow keys` move focus logically, `Enter`/`Space` activates focused button.
- Main menu keyboard: `P` opens Play, `Esc` quits.
- Play menu keyboard: `5`/`7`/`9` choose board size, `E`/`M`/`H` choose bot difficulty, `Esc` goes back.
- `Tab` shows/hides the menu settings row.
- Menus include a settings row for `Fullscreen`, `Mute`, and `SFX/Music` volume (`+/-`) via mouse click.
- Gamepad: D-pad navigates, `A` confirms, `B` goes back, `X` toggles mute, `Y` restarts, shoulder buttons toggle the settings row.
- Left click one of your bacteria to select it.
- Left click a highlighted cell to move.
- In game keyboard: `Arrow keys` move the cursor, `Enter`/`Space` select and move.
- `M` toggles mute (`Shift+M` while in the play menu to avoid clashing with medium difficulty hotkey).
- `F` or `F11` toggles fullscreen.
- `R` restarts the board.
- `Esc` returns to the main menu.
- `Esc` on the main menu quits.

## Rules

- The board size is chosen before play: `5x5`, `7x7`, or `9x9`.
- You control the teal bacteria. The AI controls the orange bacteria.
- A grow move places a new bacterium into any adjacent cell, including diagonals.
- A jump move moves a bacterium exactly 2 cells up, down, left, or right, and leaves the origin empty.
- After either move type, any adjacent enemy bacteria around the destination are converted.
- If one side is eliminated, the other side wins immediately.
- If no legal moves remain for both sides, the side with more bacteria wins.
- If a side has no legal moves but still has pieces, it passes automatically.

## Project Layout

- `conf.lua` sets the desktop window config.
- `main.lua` wires LÖVE callbacks into the game object.
- `src/board.lua` contains board helpers and state cloning.
- `src/rules.lua` contains move generation, move resolution, passing, and win detection.
- `src/ai.lua` contains enemy move selection logic for easy/medium/hard difficulties.
- `src/render.lua` draws the board, HUD, highlights, and end-game overlay.
- `src/input.lua` handles simple mouse and keyboard helpers.
- `src/audio.lua` manages SFX, mute state, and shared background music fading.
- `assets/audio/` (optional) can provide custom `sfx/*.ogg` and `music/game.ogg` files.
- `web/` contains the browser player template and header config used by `make web`.
- `src/level.lua` defines the starting layout for the chosen board size.
- `src/game.lua` coordinates turn flow and AI timing.
- `assets/fonts/` contains bundled UI fonts used for title/body typography.

## Notes

Run `love .` for a manual visual pass over transitions, animations, and typography.
