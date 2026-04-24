# Sporeline on Steam Deck

End-to-end walkthrough: produce a Linux build, get it onto the Deck, make it appear as a first-class title in Gaming Mode with custom artwork.

## 1. Produce the AppImage

You have two ways to get `Sporeline-x86_64.AppImage`.

### From GitHub Actions (easiest on macOS)

1. Push a tag: `git tag v0.1.0 && git push origin v0.1.0`, **or** trigger manually:
   Repo → Actions → "Release" → "Run workflow".
2. Wait for the run to finish (~2 minutes).
3. Download `Sporeline-x86_64.AppImage` from the workflow's artifacts panel, or from the GitHub Release if you tagged.

### Locally on Linux

```bash
make appimage
```

Produces `dist/Sporeline-x86_64.AppImage`. Requires `curl`, `zip`, and a Linux host (the build script refuses to run on macOS).

## 2. Get it onto the Deck

1. Hold the Deck's power button → **Switch to Desktop**.
2. Open Firefox on the Deck and download the AppImage directly from the GitHub Release / Actions artifacts page.
3. In Dolphin (file manager): right-click the file → **Properties → Permissions → Is executable**.
4. Double-click it. The game window should open; press `Esc` or close the window to quit.

*(Alternatives: USB stick into the Deck's USB-C slot, or `scp` if you've enabled SSH in SteamOS.)*

## 3. Add to Steam

1. Right-click the AppImage in Dolphin → **Add to Steam**. If that option isn't present: open Steam → **Games → Add a Non-Steam Game to My Library → Browse…** → pick the AppImage.
2. Rename the shortcut to "Sporeline" if it defaulted to the filename.
3. Click the desktop shortcut **Return to Gaming Mode**.

## 4. Custom library artwork

In Gaming Mode: select Sporeline in the library → press **Y** (Manage shortcut) → **Set artwork** for each slot.

Or in Desktop Mode, drop PNGs into `~/.steam/steam/userdata/<your-steam-id>/config/grid/` with these names:

| Slot            | Filename pattern          | Recommended size |
| --------------- | ------------------------- | ---------------- |
| Library capsule | `<appid>p.png`            | 600 × 900        |
| Hero            | `<appid>_hero.png`        | 1920 × 620       |
| Logo            | `<appid>_logo.png`        | ~1280 × 720, PNG with transparency |
| Icon            | `<appid>_icon.png`        | 32 × 32          |

`<appid>` is the shortcut's Steam app id — check via the Steam shortcut's properties, or the filename Steam created in the `grid/` folder once you set any artwork via the UI.

## 5. Controller

The game has native gamepad support (added in the Steam Deck build), so the Deck's built-in controls drive it directly — no Steam Input layout needed:

| Deck                   | Action                            |
| ---------------------- | --------------------------------- |
| D-pad                  | Move cursor / navigate menus      |
| **A**                  | Confirm / select                  |
| **B**                  | Back (menus) / return to main menu (in game) |
| **X**                  | Toggle mute                       |
| **Y**                  | Restart the board                 |
| **L1** / **R1**        | Toggle settings row (in menus)    |
| **Start** (≡)          | Back                              |

## Troubleshooting

**"AppImage won't launch on the Deck"** — check it's executable (`chmod +x Sporeline-x86_64.AppImage`). SteamOS has FUSE, so no extra runtime setup is needed.

**"Game launches but can't find audio"** — the `.love` archive packaged inside the AppImage contains everything; if music is silent, try pressing `M` (or the **X** button on a controller) to toggle mute.

**"Window is a small square in the middle of the Deck screen"** — expected. The game renders at 700×700 and fullscreen-desktops onto the Deck's 1280×800, which leaves pillarbox bars on the sides. Visual only; all input works.

**"Controller does nothing"** — confirm the shortcut is launched *through Steam* (not the Desktop Mode file manager). Gamepad events only arrive when SDL sees Steam Input attaching a virtual controller.
