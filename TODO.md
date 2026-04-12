# TODO

## Current Focus

### Audio Polish
- [x] Add a runtime-safe audio module in `src/audio.lua`.
- [x] Trigger baseline SFX for menu open, menu navigation, confirm, game start, and moves.
- [x] Expand SFX coverage:
  - invalid action
  - piece conversion burst
  - pass turn
  - win / lose stingers
- [x] Add audio controls:
  - mute toggle (`M`)
  - visible audio status in UI
- [ ] Add separate SFX / music volume controls.
- [x] Add background music support:
  - load a looping menu track and gameplay track from `assets/audio/`
  - fade between tracks on screen change
  - obey mute/volume settings

### Visual / UX Polish
- [x] Add menu fade-in transitions.
- [x] Add button hover pulse animation in menus.
- [x] Add piece spawn/convert animation when pieces appear or change side.
- [x] Keep animation timings subtle and readable (avoid slowing down turn flow).
- [x] Add fullscreen startup and toggle (`F` / `F11`).
- [ ] Add subtle transition polish when switching `main_menu` <-> `play_menu`.
- [ ] Add a small audio/settings row in menus (fullscreen, mute, volume).

### Typography
- [x] Introduce a bundled UI font (title + body), loaded from `assets/fonts/`.
- [x] Apply consistent type scale for title, section labels, button text, and HUD text.
- [x] Verify readability at all supported window sizes.

## Definition of Done
- [x] All existing tests pass.
- [x] Audio/fullscreen tests pass (`luajit tests/run.lua`).
- [ ] Manual check in LÖVE:
  - audio cues are balanced and not harsh
  - fades/hover/spawn animation remain smooth
  - fullscreen toggle remains stable on macOS
  - typography remains readable at fullscreen resolutions
