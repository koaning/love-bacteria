# Linux AppImage scaffolding

Files consumed by `make appimage` when repacking the upstream LÖVE 11.5 AppImage.

- `AppRun` — launcher shell script. Sets `LD_LIBRARY_PATH` and execs the bundled `love` binary against `sporeline.love`.
- `sporeline.desktop` — freedesktop entry used by desktop environments and Steam when the `.AppImage` is added as a Non-Steam game.
- `sporeline.png` *(optional, 256×256)* — app icon. If absent, `make appimage` falls back to the upstream `love.svg` (renamed to `sporeline.svg`). Drop a PNG in here to replace it.

See `../../docs/steam-deck.md` for the end-to-end walkthrough from `make appimage` to Gaming Mode.
