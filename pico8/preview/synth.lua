-- Tiny PICO-8-ish synth for the preview player and tools/sfx.lua.
--
-- Plain Lua 5.1 (no LÖVE), so it runs inside love.js and under luajit.
-- It approximates PICO-8's 8 waveforms and the fade/vibrato/slide effects;
-- filters (noiz, buzz, reverb, ...) and custom instruments are ignored.

local synth = {}

synth.RATE = 22050
-- one sfx "speed" tick is 1/120 s
local TICK = synth.RATE / 120

local function tri(p) return 1 - 4 * math.abs(p - 0.5) end

local function wave(w, phase)
  local p = phase % 1
  if w == 0 then return math.sin(p * 2 * math.pi) end
  if w == 1 then return tri(p) end
  if w == 2 then return 2 * p - 1 end
  if w == 3 then return p < 0.5 and 1 or -1 end
  if w == 4 then return p < 0.25 and 1 or -1 end
  if w == 5 then return tri(p) * 0.6 + math.sin(p * 4 * math.pi) * 0.4 end
  if w == 6 then return math.random() * 2 - 1 end
  return math.sin(p * 2 * math.pi + math.sin(p * 6 * math.pi))
end

-- PICO-8 pitch 0 is C2 (65.41 Hz); pitch 33 is A4 (440 Hz).
local function freq(pitch) return 65.41 * 2 ^ (pitch / 12) end

-- Parse one __sfx__ line: "MMSSLLEE" header + 32 notes of "PPWVE".
function synth.parse_sfx(hex)
  local s = {
    speed = tonumber(hex:sub(3, 4), 16) or 0,
    loop_start = tonumber(hex:sub(5, 6), 16) or 0,
    loop_end = tonumber(hex:sub(7, 8), 16) or 0,
    notes = {},
    last = 0,
  }
  for n = 0, 31 do
    local t = hex:sub(9 + n * 5, 13 + n * 5)
    local note = {
      pitch = tonumber(t:sub(1, 2), 16) or 0,
      wave = (tonumber(t:sub(3, 3), 16) or 0) % 8,
      vol = tonumber(t:sub(4, 4), 16) or 0,
      fx = tonumber(t:sub(5, 5), 16) or 0,
    }
    s.notes[n + 1] = note
    if note.vol > 0 then s.last = n + 1 end
  end
  return s
end

-- Parse one __music__ line: "FF AABBCCDD". flags: 1 loop start, 2 loop end,
-- 4 stop. A channel byte >= 0x40 means the channel is silent.
function synth.parse_music(line)
  local flags, chans = line:match("^(%x%x) (%x%x%x%x%x%x%x%x)")
  if not flags then return nil end
  local p = { flags = tonumber(flags, 16), chans = {} }
  for c = 0, 3 do
    local v = tonumber(chans:sub(c * 2 + 1, c * 2 + 2), 16)
    if v < 0x40 then p.chans[#p.chans + 1] = v end
  end
  return p
end

function synth.samples_per_step(s)
  return math.floor(TICK * s.speed)
end

-- Mix steps [first, first + count) of sfx `s` into the float array `out`
-- (1-based, starting at out[offset + 1]). `ch` keeps phase between calls.
function synth.mix(s, first, count, out, offset, ch, gain)
  local per = synth.samples_per_step(s)
  local pos = offset
  for i = first, first + count - 1 do
    local n = s.notes[i + 1]
    local prev = s.notes[i] or n
    if n and n.vol > 0 then
      local f0, f1 = freq(n.pitch), freq(n.pitch)
      if n.fx == 1 then f0 = freq(prev.pitch) end
      if n.fx == 3 then f1 = freq(n.pitch - 24) end
      local v0 = n.vol / 7
      for k = 0, per - 1 do
        local t = k / per
        local v = v0
        if n.fx == 4 then v = v * t end
        if n.fx == 5 then v = v * (1 - t) end
        local f = f0 + (f1 - f0) * t
        if n.fx == 2 then f = f * (1 + 0.012 * math.sin((ch.vib + k) / synth.RATE * 2 * math.pi * 6)) end
        ch.phase = ch.phase + f / synth.RATE
        out[pos + k + 1] = (out[pos + k + 1] or 0) + wave(n.wave, ch.phase) * v * gain
      end
      ch.vib = ch.vib + per
    else
      for k = 0, per - 1 do
        out[pos + k + 1] = out[pos + k + 1] or 0
      end
      ch.vib = 0
    end
    pos = pos + per
  end
  return pos - offset
end

-- Render a whole sfx (up to its last audible note) to a float array.
function synth.render_sfx(s)
  if s.last == 0 or s.speed == 0 then return nil end
  local out = {}
  synth.mix(s, 0, s.last, out, 0, { phase = 0, vib = 0 }, 0.25)
  return out
end

-- A music player that renders `steps` steps at a time, so the preview can
-- stream it into a queueable source without stalling a frame.
--   sfxs[i]  parsed sfx (0-based ids)    pats[i]  parsed music patterns
function synth.new_music(sfxs, pats, start, steps)
  local m = { sfxs = sfxs, pats = pats, pat = start, step = 0, loop = start, chans = {} }
  for c = 1, 4 do m.chans[c] = { phase = 0, vib = 0 } end

  -- a pattern lasts as long as its first channel's sfx (all 32 steps)
  local function lead(p)
    local s = sfxs[p.chans[1]]
    return s
  end

  function m.next_chunk()
    local p = pats[m.pat]
    if not p or #p.chans == 0 or not lead(p) then return nil end
    if m.step == 0 and p.flags % 2 == 1 then m.loop = m.pat end
    local count = math.min(steps, 32 - m.step)
    local out = {}
    for c, id in ipairs(p.chans) do
      local s = sfxs[id]
      if s then synth.mix(s, m.step, count, out, 0, m.chans[c], 0.18) end
    end
    m.step = m.step + count
    if m.step >= 32 then
      m.step = 0
      local fl = p.flags
      if fl % 8 >= 4 then
        m.pat = -1
      elseif fl % 4 >= 2 then
        m.pat = m.loop
      else
        m.pat = m.pat + 1
      end
    end
    return out
  end

  return m
end

return synth
