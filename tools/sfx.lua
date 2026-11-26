-- Sound compiler: the readable scores in tools/scores.lua (game-owned)
-- compiled into the cart's __sfx__ and __music__ sections.
--
--   luajit tools/sfx.lua [cart.p8]            rewrite the cart (`make music`)
--   luajit tools/sfx.lua [cart.p8] --check    fail if the cart is out of date
--
-- tools/scores.lua returns a table:
--
--   first_sfx  sfx 0..first_sfx-1 are sound effects, music uses first_sfx+
--   effects    list of { name, speed, notes } compiled into sfx 0, 1, ...;
--              leave it out to keep the cart's own sfx 0..first_sfx-1 (made
--              in PICO-8's editor) untouched
--   songs      list of { name, title, speed, patterns, order }; each loops
--              on itself, and the check makes sure pico8/main.lua calls
--              music(<first pattern>, ...) for every song
--   harp, bass optional voices for the song arranger: { wave, vol }
--
-- Effect notes are "pitch:wave:volume:effect" tokens, "-" for a rest, up to
-- 32 per effect. Pitches are PICO-8 tracker notes (c0 is the lowest; c#2,
-- a3, ...). Waves: 0 sine, 1 triangle, 2 saw, 3 square, 4 pulse, 5 organ,
-- 6 noise, 7 phaser. Effects: 0 none, 1 slide, 2 vibrato, 3 drop, 4 fade in,
-- 5 fade out.
--
-- Song patterns are four bars of chords: one per bar ("gmaj7"), or two
-- sharing a bar ("dsus4/d7"). Chord qualities: maj7 m7 7 6 m6 sus4 maj. Each
-- pattern becomes a plucked harp arpeggio (channel 0) and a root/fifth bass
-- (channel 1); channels 2-3 stay free for sound effects.

package.path = "tools/?.lua;" .. package.path

local args = {}
local check = false
for _, a in ipairs(arg) do
  if a == "--check" then check = true else args[#args + 1] = a end
end
local CART = args[1] or require("cart")()
local scores = dofile("tools/scores.lua")
local FIRST_SFX = assert(scores.first_sfx, "tools/scores.lua: first_sfx is missing")
local effects = scores.effects
local songs = scores.songs or {}

local HARP = scores.harp or { wave = 0, vol = 3 }
local BASS = scores.bass or { wave = 1, vol = 4 }

local chord_tones = {
  maj7 = { 0, 4, 7, 11 }, m7 = { 0, 3, 7, 10 }, ["7"] = { 0, 4, 7, 10 },
  ["6"] = { 0, 4, 7, 9 }, m6 = { 0, 3, 7, 9 }, sus4 = { 0, 5, 7, 12 },
  maj = { 0, 4, 7, 12 },
}

-------------------------------------------------------------------------------
-- compiler
-------------------------------------------------------------------------------
local semis = { c = 0, d = 2, e = 4, f = 5, g = 7, a = 9, b = 11 }

local function parse_chord(c)
  local root, acc, q = c:match("^(%a)(#?)(.*)$")
  assert(root and semis[root], "bad chord " .. c)
  return semis[root] + (acc == "#" and 1 or 0), assert(chord_tones[q], "bad chord " .. c)
end

local function blank()
  local t = {}
  for i = 1, 32 do t[i] = { pitch = 0, wave = 0, vol = 0, fx = 0 } end
  return t
end

local function put(t, i, pitch, voice, fx, vol)
  t[i] = { pitch = pitch, wave = voice.wave, vol = vol or voice.vol, fx = fx or 0 }
end

-- harp: plucked broken chords around C3..E4; bass: root/fifth bounce in
-- octave 2. Pitches are PICO-8's: C2 = 0, so C3 = 12.
local harp_full = { 1, 2, 3, 4, 6, 4, 3, 2 } -- 5,6 = chord tones 1,2 an octave up
local harp_half = { 1, 3, 4, 6 }

local function compile_backing(chords)
  assert(#chords == 4, "pattern is not 4 bars")
  local harp, bass = blank(), blank()
  for b, spec in ipairs(chords) do
    local parts = {}
    for c in spec:gmatch("[^/]+") do parts[#parts + 1] = c end
    local base = (b - 1) * 8
    for h, c in ipairs(parts) do
      local root, tones = parse_chord(c)
      local r3 = root + 12
      local seq = #parts == 1 and harp_full or harp_half
      local at = base + (h - 1) * #seq
      for k, idx in ipairs(seq) do
        local p = idx > 4 and tones[idx - 4] + 12 or tones[idx]
        put(harp, at + k, r3 + p, HARP, 5, k == 1 and HARP.vol or HARP.vol - 1)
      end
      local fifth = root + 7 >= 12 and root - 5 or root + 7
      if #parts == 1 then
        put(bass, at + 1, root, BASS); put(bass, at + 2, root, BASS); put(bass, at + 3, root, BASS, 5)
        put(bass, at + 5, fifth, BASS, 0, 3); put(bass, at + 6, fifth, BASS, 5, 3)
        put(bass, at + 7, root + 12, BASS, 0, 3); put(bass, at + 8, root + 12, BASS, 5, 3)
      else
        put(bass, at + 1, root, BASS); put(bass, at + 2, root, BASS); put(bass, at + 3, root, BASS, 5)
        put(bass, at + 4, fifth, BASS, 5, 3)
      end
    end
  end
  return harp, bass
end

-- "c#3:1:5:0" style notes into sfx note tables
local function compile_effect(e)
  local notes = blank()
  local i = 0
  for tok in e.notes:gmatch("%S+") do
    i = i + 1
    assert(i <= 32, e.name .. " has more than 32 notes")
    if tok ~= "-" then
      local name, acc, oct, w, v, fx = tok:match("^(%a)(#?)(%d):(%d):(%d):(%d)$")
      assert(name and semis[name], "bad note " .. tok .. " in " .. e.name)
      local pitch = semis[name] + (acc == "#" and 1 or 0) + 12 * tonumber(oct)
      assert(pitch <= 63, "note too high in " .. e.name)
      notes[i] = { pitch = pitch, wave = tonumber(w), vol = tonumber(v), fx = tonumber(fx) }
    end
  end
  return notes
end

local function sfx_line(notes, speed)
  local s = string.format("00%02x0000", speed)
  for _, n in ipairs(notes) do
    s = s .. string.format("%02x%x%x%x", n.pitch, n.wave, n.vol, n.fx)
  end
  return s
end

-- Compile songs into sfx lines (from FIRST_SFX) and music lines. Each song
-- loops on itself; `starts[name]` is its first music pattern.
local function build(list)
  local sfx, music, starts = {}, {}, {}
  local function add(line)
    for i, l in ipairs(sfx) do
      if l == line then return FIRST_SFX + i - 1 end
    end
    sfx[#sfx + 1] = line
    return FIRST_SFX + #sfx - 1
  end
  for _, song in ipairs(list) do
    local speed = song.speed
    local ids = {}
    starts[song.name] = #music
    for i, name in ipairs(song.order) do
      if not ids[name] then
        local harp, bass = compile_backing(assert(song.patterns[name], "no pattern " .. name))
        ids[name] = { add(sfx_line(harp, speed)), add(sfx_line(bass, speed)) }
      end
      local flags = (i == 1 and 1 or 0) + (i == #song.order and 2 or 0)
      local c = ids[name] -- channels 2-3 off (0x40), left free for sfx
      music[#music + 1] = string.format("%02x %02x%02x4040", flags, c[1], c[2])
    end
  end
  assert(FIRST_SFX + #sfx <= 64, "out of sfx slots")
  return sfx, music, starts
end

-------------------------------------------------------------------------------
-- cart i/o
-------------------------------------------------------------------------------
local function read(path)
  local f = assert(io.open(path, "rb"), "cannot open " .. path)
  local s = f:read("*a")
  f:close()
  return s
end

local function lines(s)
  local t = {}
  for l in (s or ""):gmatch("[^\n]+") do t[#t + 1] = l end
  return t
end

local function split_sections(src)
  local head, sections, order, cur = {}, {}, {}, nil
  for l in src:gmatch("([^\n]*)\n") do
    local name = l:match("^__(%w+)__$")
    if name then
      cur = {}
      sections[name] = cur
      order[#order + 1] = name
    elseif cur then
      cur[#cur + 1] = l
    else
      head[#head + 1] = l
    end
  end
  for n, body in pairs(sections) do sections[n] = table.concat(body, "\n") end
  return table.concat(head, "\n") .. "\n", sections, order
end

local function updated_cart(src, sfx, music)
  local head, sections, order = split_sections(src)
  local old = lines(sections.sfx)
  local empty = "00010000" .. string.rep("00000", 32)
  local out = {}
  if effects then
    assert(#effects <= FIRST_SFX, "more sound effects than first_sfx slots")
    for i = 1, FIRST_SFX do
      local e = effects[i]
      out[i] = e and sfx_line(compile_effect(e), e.speed) or empty
    end
  else
    for i = 1, FIRST_SFX do out[i] = old[i] or empty end
  end
  for i, l in ipairs(sfx) do out[FIRST_SFX + i] = l end
  local function ensure(name)
    for _, n in ipairs(order) do
      if n == name then return end
    end
    order[#order + 1] = name
  end
  sections.sfx = table.concat(out, "\n")
  ensure("sfx")
  if #music > 0 then
    sections.music = table.concat(music, "\n")
    ensure("music")
  end
  local parts = { head }
  for _, n in ipairs(order) do
    parts[#parts + 1] = "__" .. n .. "__\n" .. sections[n] .. "\n"
  end
  return table.concat(parts)
end

local sfx, music, starts = build(songs)
local src = read(CART)
local new = updated_cart(src, sfx, music)

if check then
  if new ~= src then
    io.stderr:write(CART .. " sound is stale: run `make music`\n")
    os.exit(1)
  end
  local main = read("pico8/main.lua")
  for _, song in ipairs(songs) do
    local n = starts[song.name]
    if not main:find("music%(" .. n .. "[,%)]") then
      io.stderr:write("pico8/main.lua should call music(" .. n .. ", ...) for the song "
        .. song.name .. "\n")
      os.exit(1)
    end
  end
  print(string.format("sound  %d effects, %d songs, %d music patterns, up to date",
    effects and #effects or 0, #songs, #music))
else
  if new ~= src then
    local f = assert(io.open(CART, "wb"))
    f:write(new)
    f:close()
    print("updated " .. CART)
  end
  for _, song in ipairs(songs) do
    print(string.format("%-10s starts at music pattern %d", song.name, starts[song.name]))
  end
end
