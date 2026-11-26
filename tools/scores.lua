-- Mossballs background music, compiled by `make music` (tools/sfx.lua).
--
-- `effects` is omitted on purpose so the cart's hand-made sfx 0-7 stay
-- untouched; music patterns compile into sfx 8+ and __music__.
--
-- Two calm, original chord loops with nods to classic adventure and
-- platformer soundtracks (maj7 voicings, borrowed minor chords, bVII lifts):
--   title  "sprout parade"  music(0)  F major, 72 bpm
--   game   "moss garden"    music(4)  C major, 90 bpm
-- No lead melody: a soft plucked sine harp arpeggio on channel 0 and a
-- root/fifth triangle bass on channel 1. Channels 2-3 stay free for sfx.

return {
  first_sfx = 8,

  songs = {
    {
      name = "title", title = "sprout parade", speed = 50,
      patterns = {
        a = { "fmaj7", "dm7", "gm7", "c7" },
        a2 = { "fmaj7", "dm7", "a#maj7/a#m6", "fmaj7/c7" },
        b = { "a#maj7", "am7", "d7", "gm7/c7" },
        coda = { "fmaj7", "dm7", "gm7/c7", "fmaj" },
      },
      order = { "a", "a2", "b", "coda" },
    },
    {
      name = "game", title = "moss garden", speed = 40,
      patterns = {
        a = { "cmaj7", "fmaj7", "cmaj7", "dm7/g7" },
        a2 = { "cmaj7", "fmaj7", "am7/fm6", "dm7/g7" },
        b = { "fmaj7", "em7", "dm7", "cmaj7" },
        b2 = { "a#maj7", "fmaj7", "a#maj7", "gsus4/gmaj" },
        coda = { "cmaj7", "fmaj7", "a#maj7/fmaj7", "cmaj" },
      },
      order = { "a", "a2", "b", "b2", "a", "coda" },
    },
  },
}
