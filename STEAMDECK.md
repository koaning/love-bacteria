# Playing Sporeline on Steam Deck

The goal: **one short Desktop Mode visit to set things up, then everything else from your Mac over SSH**. After the initial setup, you never have to leave Gaming Mode on the Deck again — you push new AppImages with `scp` or the install script, and the existing Steam shortcut picks them up.

---

## TL;DR

1. **On your Mac**: tag a release (or click "Run workflow" in Actions) → GitHub builds `Sporeline-x86_64.AppImage`.
2. **On the Deck (once, in Desktop Mode)**: set sudo password, enable SSH, run `scripts/install-on-deck.sh --latest`, add the AppImage to Steam via the UI.
3. **From then on (from your Mac)**: `ssh deck@<ip> 'bash -s -- --latest' < scripts/install-on-deck.sh` to pull and install new builds. No Desktop Mode needed.

---

## 1. Produce the AppImage

### Via GitHub Actions (recommended from macOS)

Tag and push:

```bash
git tag v0.1.0
git push origin v0.1.0
```

…or go to **Actions → Release → Run workflow** on GitHub. The workflow runs the test suite, then `make appimage`, and attaches `Sporeline-x86_64.AppImage` to the GitHub Release (and also uploads it as a workflow artifact).

### Locally on a Linux host

```bash
make appimage
```

Produces `dist/Sporeline-x86_64.AppImage`. Requires `curl`, `zip`, and a Linux host — the Makefile refuses on macOS.

---

## 2. One-time Steam Deck setup (~5 min in Desktop Mode)

### 2a. Enter Desktop Mode

Press the **STEAM** button → **Power** → **Switch to Desktop**. Takes ~10 seconds; you land in KDE Plasma.

### 2b. Typing without a USB keyboard

If you don't have a USB/Bluetooth keyboard attached, use the on-screen keyboard:

- **STEAM + X** toggles the OSK over any focused input.
- The touchscreen works — tap keys directly, or tap a text field to focus it.
- **Right trackpad** = mouse cursor. **R2** = left click, **L2** = right click.
- Symbols that aren't on the default layer: press **`?123`** (bottom-left of the OSK) for numbers + common symbols. For `/` and similar. Press the alternate-symbols button (often `=\<`) for `|`, `\`, `<`, `>`.
- **R1** / **L1** cycle keyboard layers while the OSK is open.

Pairing a cheap Bluetooth keyboard under **Settings → Bluetooth** makes this visit *much* less painful.

### 2c. Set password, enable SSH, install

Open **Konsole** (search "Konsole" in the app launcher) and run:

```bash
# Set a password for the 'deck' user — needed for sudo and SSH.
passwd

# Enable the SSH server (installed but disabled by default).
sudo systemctl enable --now sshd

# Note the Deck's LAN IP — you'll use it from your Mac.
ip -br addr show | grep -v '^lo'
```

Still in Konsole, install Sporeline with the helper script. Either copy the script over (USB, Syncthing, or clone this repo on the Deck), or paste its contents inline:

```bash
# From a clone of the repo on the Deck:
./scripts/install-on-deck.sh --latest
```

This downloads the latest `Sporeline-x86_64.AppImage` from the GitHub release, drops it in `~/Applications/`, `chmod +x`'s it, and prints the final registration steps:

1. Open **Steam** (Desktop client).
2. In the **top menu bar**: **Games → Add a Non-Steam Game to My Library…** *(also reachable from the bottom-left **+ ADD A GAME** button)*. In the dialog that opens, click **BROWSE…** and navigate to `/home/deck/Applications/Sporeline-x86_64.AppImage`. If the file isn't visible, switch the file-type filter in the bottom-right from "Applications" to **"All Files"** — `.AppImage` isn't in the default filter.
3. Tick Sporeline, click **Add Selected Programs**.
4. **Important — disable Proton:** right-click the new shortcut → **Properties** → **Compatibility** tab → make sure "Force the use of a specific Steam Play compatibility tool" is **unchecked**. If a dropdown appears below, set it to **"None"**. Proton will try to run the Linux AppImage through Wine and it will exit silently — this is the #1 cause of "game appears in library but won't start."
5. Confirm **Shortcut** tab shows:
   - **Target:** `"/home/deck/Applications/Sporeline-x86_64.AppImage"` (with quotes)
   - **Start In:** `"/home/deck/Applications/"` (with quotes)
   - **Launch Options:** empty
6. (Optional) rename the shortcut to "Sporeline".

Return to Gaming Mode via the **Return to Gaming Mode** desktop icon.

> Why not `shortcuts.vdf` automatically? Steam stores non-Steam shortcuts in a binary VDF file that must be edited while Steam is stopped, which fights against the user's logged-in session. The manual click is about 10 seconds and, crucially, **only happens once** — updates don't need it.

---

## 3. Updating from your Mac (no Desktop Mode)

Once the Steam shortcut exists, upgrades are remote-only. From your Mac:

```bash
# Option A: push a freshly built AppImage
scp dist/Sporeline-x86_64.AppImage deck@<deck-ip>:~/Applications/

# Option B: ask the Deck to pull the latest release itself
ssh deck@<deck-ip> 'curl -fsSL https://raw.githubusercontent.com/koaning/love-bacteria/main/scripts/install-on-deck.sh | bash -s -- --latest'
```

Gaming Mode's existing Sporeline shortcut points at `~/Applications/Sporeline-x86_64.AppImage` — when you overwrite that file, the next launch runs the new build.

---

## 4. Custom library artwork

In Gaming Mode: select Sporeline in your library → press **Y** (Manage shortcut) → **Set artwork** for each slot.

Or drop PNGs into `~/.steam/steam/userdata/<your-steam-id>/config/grid/` on the Deck with these names:

| Slot            | Filename             | Recommended size                     |
| --------------- | -------------------- | ------------------------------------ |
| Library capsule | `<appid>p.png`       | 600 × 900                            |
| Hero            | `<appid>_hero.png`   | 1920 × 620                           |
| Logo            | `<appid>_logo.png`   | ~1280 × 720, PNG with transparency   |
| Icon            | `<appid>_icon.png`   | 32 × 32                              |

`<appid>` is the shortcut's generated Steam app id — find it by setting any artwork via the UI once, then checking the filename Steam wrote into `grid/`.

Since the Deck's filesystem is reachable over SSH, you can push artwork from your Mac the same way as the AppImage:

```bash
scp capsule.png deck@<deck-ip>:~/.steam/steam/userdata/<id>/config/grid/<appid>p.png
```

---

## 5. Controls

Native gamepad support is built into the game, so the Deck's controls work without any Steam Input remapping.

| Deck button            | In-game action                              |
| ---------------------- | ------------------------------------------- |
| D-pad                  | Move cursor / navigate menus                |
| **A**                  | Confirm / select                            |
| **B**                  | Back (menus) / return to main menu (in game)|
| **X**                  | Toggle mute                                 |
| **Y**                  | Restart the board                           |
| **L1** / **R1**        | Toggle settings row (in menus)              |
| **Start** (≡)          | Back                                        |

---

## Troubleshooting

**"The game appears in Steam but won't start — takes a few seconds then disappears."** Proton is the usual culprit. Properties → Compatibility → uncheck "Force the use of a specific Steam Play compatibility tool" *and* set the dropdown to "None" if it's visible. Unchecking alone doesn't always stick on Non-Steam shortcuts.

**"How do I verify the AppImage itself works (independent of Steam)?"** From **Konsole on the Deck** (not SSH — see below), run:

```bash
~/Applications/Sporeline-x86_64.AppImage
```

The Love window should appear. If that works but Steam launch fails, you know the wrapper/Proton is the problem, not the AppImage.

**"SSH launch test errors with `Authorization required, but no authorization protocol specified` and `xcb_connection_has_error() returned true`."** Not a real crash. You're trying to draw on the Deck's logged-in Plasma display from an SSH session, and X11's access control rejects it (no xauth cookie in the SSH env). Launch through Steam, or via Konsole *on the Deck*, instead. This is expected — it doesn't indicate a problem with the AppImage.

**"`AppRun: /tmp/.mount_.../usr/bin/love: No such file or directory` on launch."** You're on a pre-v0.1.1 build. The AppRun had the wrong path for the bundled LÖVE binary. Pull v0.1.1 or later:

```bash
curl -fsSL -o ~/Applications/Sporeline-x86_64.AppImage \
  https://github.com/koaning/love-bacteria/releases/latest/download/Sporeline-x86_64.AppImage
chmod +x ~/Applications/Sporeline-x86_64.AppImage
```

**"AppImage won't launch at all"** — confirm it's executable (`ls -l ~/Applications/Sporeline-x86_64.AppImage` — should start with `-rwx`). SteamOS ships FUSE, so no extra runtime is needed.

**"Controller does nothing"** — launch through Steam, not directly from Dolphin or Konsole. Gamepad events only arrive when SDL sees Steam Input attaching a virtual controller.

**"Game window is a small square in the middle of the screen"** — expected. The game renders at 700×700 and fullscreen-desktops onto the Deck's 1280×800, so you get pillarbox bars on the sides. All input still works.

**"SSH stops working after a SteamOS update"** — SteamOS has historically wiped the `deck` user's password and disabled sshd on major updates. Rerun `passwd` + `sudo systemctl enable --now sshd` in Desktop Mode and you're back.

**"`install-on-deck.sh --latest` says no AppImage found"** — the Release workflow hasn't produced an asset yet. Tag a version (`git tag vX.Y.Z && git push origin vX.Y.Z`) or run the workflow manually from the Actions tab.
