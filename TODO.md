# TODO

## Current Focus

### Gameplay AI
- [ ] Add a `medium` bot difficulty in `src/ai.lua`.
- [ ] `medium` behavior: choose the current greedy/best-scoring move about `2/3` of the time, and a random legal move about `1/3` of the time.
- [ ] Expose `medium` in the play menu UI and keyboard controls (between `easy` and `hard`).
- [ ] Add tests that verify:
  - medium always returns a legal move when moves exist
  - medium returns `nil` when no legal moves exist
  - medium can produce both greedy and random-style outcomes over repeated runs

### Audio
- [ ] Add an asset loader module for SFX (menu select, move, convert, win/lose).
- [ ] Trigger SFX on menu activation and gameplay events.
- [ ] Add a mute toggle (`M`) and visible muted/unmuted indicator.

### Visual Polish
- [ ] Add menu fade-in transitions.
- [ ] Add button hover pulse animation in menus.
- [ ] Add piece spawn/convert animation when pieces appear or change side.
- [ ] Keep animation timings subtle and readable (avoid slowing down turn flow).

### Typography
- [ ] Introduce a bundled UI font (title + body), loaded from `assets/fonts/`.
- [ ] Apply consistent type scale for title, section labels, button text, and HUD text.
- [ ] Verify readability at all supported window sizes.

## Definition of Done
- [ ] All existing tests pass.
- [ ] New AI tests for `medium` pass.
- [ ] Manual check in LÖVE: audio, fades, hover pulse, spawn animation, and typography all visible and stable.
