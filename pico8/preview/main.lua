-- PICO-8 preview player, written in LÖVE.
--
-- This is NOT PICO-8. It is a small stand-in that implements just enough of
-- the PICO-8 API (128x128 screen, 16-colour palette plus the 16 extra
-- screen colours, shapes, sprites, a 3x5 font, buttons, coroutines, a tiny
-- sfx/music synth) to play the cart in a
-- browser through love.js when the real PICO-8 isn't available to export an
-- HTML player. For the real thing: `make pico8` / PICO-8's own `export`.
--
-- CPU: PICO-8 gives a cart a fixed instruction budget per frame. We count Lua
-- VM instructions with a debug hook so stat(1) behaves roughly like the real
-- console, which makes the bot "think" for a PICO-8-like number of frames.
--
-- The cart is loaded from the one cart/*.p8 inside this .love; its #include
-- lines are resolved against cart/ (`make pico8-preview` copies the cart and
-- pico8/*.lua there).
--
-- `love <game>-p8.love --shots <dir> [--label <file>] [--all]` plays the
-- scripted run in shots.lua and saves screenshots into <dir>, and the title
-- screen as cart label text into <file> (`make screenshots`).

local W = 128
local SCALE_MIN = 1
local INSTR_PER_SECOND = 4000000 -- PICO-8 spec: "CPU: 4M vm insts/sec" (approx.)
local HOOK_STEP = 500

local PALETTE = {
  [0] = 0x000000, 0x1d2b53, 0x7e2553, 0x008751, 0xab5236, 0x5f574f, 0xc2c3c7, 0xfff1e8,
  0xff004d, 0xffa300, 0xffec27, 0x00e436, 0x29adff, 0x83769c, 0xff77a8, 0xffccaa,
  -- the extra colours, for the screen palette: pal(c, 128 + n, 1)
}
for i, c in ipairs({ 0x291814, 0x111d35, 0x422136, 0x125359, 0x742f29, 0x49333b, 0xa28879, 0xf3ef7d,
  0xbe1250, 0xff6c24, 0xa8e72e, 0x00b543, 0x065ab5, 0x754665, 0xff6e59, 0xff9d81 }) do
  PALETTE[127 + i] = c
end

local rgb_of = {}
for i, c in pairs(PALETTE) do
  rgb_of[i] = { math.floor(c / 65536) / 255, (math.floor(c / 256) % 256) / 255, (c % 256) / 255 }
end
-- the standard 16 colours (the cartridge picture's shell), and the
-- screen palette: which colour each of the 16 shows as
local rgb = {}
local screen_pal = {}
for i = 0, 15 do rgb[i] = rgb_of[i] end
local function shown(c)
  return rgb_of[screen_pal[c or 0] or 0]
end

-- framebuffer of palette indices
local fb = {}
local image_data, image
local draw_pal = {}
local transparent = {}
-- the sprite sheet (__gfx__), 128x128 colour indices
local sheet = {}
local pen = 6
local cursor_x, cursor_y = 0, 0
local camera_x, camera_y = 0, 0
local fill_pat = 0
local fill_trans = false
local clip_x0, clip_y0, clip_x1, clip_y1 = 0, 0, W - 1, W - 1

local function reset_palt()
  for i = 0, 15 do
    transparent[i] = i == 0
  end
end

local function reset_pal()
  for i = 0, 15 do
    draw_pal[i] = i
    screen_pal[i] = i
  end
  reset_palt()
end

local function pset_shape(x, y, c)
  x = math.floor(x - camera_x)
  y = math.floor(y - camera_y)
  if x >= clip_x0 and x <= clip_x1 and y >= clip_y0 and y <= clip_y1 then
    local col = c or pen
    if fill_pat ~= 0 then
      local bit_idx = (3 - (y % 4)) * 4 + (3 - (x % 4))
      local on = math.floor(fill_pat / (2 ^ bit_idx)) % 2 == 1
      if on then
        if fill_trans then return end
        col = math.floor(col / 16) % 16
      else
        col = col % 16
      end
    else
      col = col % 16
    end
    fb[y * W + x] = draw_pal[math.floor(col) % 16]
  end
end

local function pset(x, y, c)
  x = math.floor(x - camera_x)
  y = math.floor(y - camera_y)
  if x >= clip_x0 and x <= clip_x1 and y >= clip_y0 and y <= clip_y1 then
    fb[y * W + x] = draw_pal[math.floor(c or pen) % 16]
  end
end

local function hline(x0, x1, y, c)
  if x0 > x1 then x0, x1 = x1, x0 end
  for x = math.floor(x0), math.floor(x1) do
    pset_shape(x, y, c)
  end
end

-------------------------------------------------------------------------------
-- 3x5 font (lowercase glyphs; uppercase folds onto them) + wide button glyphs
-------------------------------------------------------------------------------
local FONT = {
  a = "111101111101101", b = "111101110101111", c = "111100100100111",
  d = "110101101101111", e = "111100110100111", f = "111100110100100",
  g = "111100100101111", h = "101101111101101", i = "111010010010111",
  j = "111010010010110", k = "101101110101101", l = "100100100100111",
  m = "111111101101101", n = "110101101101101", o = "011101101101110",
  p = "111101111100100", q = "010101101110011", r = "111101110101101",
  s = "011100111001110", t = "111010010010010", u = "101101101101011",
  v = "101101101111010", w = "101101101111111", x = "101101010101101",
  y = "101101111001111", z = "111001010100111",
  ["0"] = "111101101101111", ["1"] = "110010010010111", ["2"] = "111001111100111",
  ["3"] = "111001011001111", ["4"] = "101101111001001", ["5"] = "111100111001111",
  ["6"] = "100100111101111", ["7"] = "111001001001001", ["8"] = "111101111101111",
  ["9"] = "111101111001001",
  [" "] = "000000000000000", ["."] = "000000000000010", [","] = "000000000010100",
  ["!"] = "010010010000010", ["?"] = "111001011000010", [":"] = "000010000010000",
  ["-"] = "000000111000000", ["+"] = "000010111010000", ["<"] = "001010100010001",
  [">"] = "100010001010100", ["/"] = "001001010100100", ["("] = "010100100100010",
  [")"] = "010001001001010", ["'"] = "010010000000000", ["="] = "000111000111000",
  ["_"] = "000000000000111", ["%"] = "101001010100101", ["#"] = "101111101111101",
  ["*"] = "101010111010101", ['"'] = "101101000000000",
}

local WIDE = {
  [139] = { "1111111", "1100111", "1000111", "1100111", "1111111" }, -- left
  [145] = { "1111111", "1110011", "1110001", "1110011", "1111111" }, -- right
  [148] = { "1111111", "1110111", "1100011", "1000001", "1111111" }, -- up
  [131] = { "1111111", "1000001", "1100011", "1110111", "1111111" }, -- down
  [142] = { "0111110", "1100011", "1101011", "1100011", "0111110" }, -- o
  [151] = { "0111110", "1101011", "1110111", "1101011", "0111110" }, -- x
}

local function print_text(str, x, y, c)
  str = tostring(str)
  if x == nil then
    x, y = cursor_x, cursor_y
  end
  if c then pen = c end
  local sx = x
  for i = 1, #str do
    local b = str:byte(i)
    if b == 10 then
      x = sx
      y = y + 6
    elseif WIDE[b] then
      local rows = WIDE[b]
      for gy = 1, 5 do
        for gx = 1, 7 do
          if rows[gy]:sub(gx, gx) == "1" then pset(x + gx - 1, y + gy - 1, pen) end
        end
      end
      x = x + 8
    else
      local glyph = FONT[string.char(b):lower()]
      if glyph then
        for gy = 0, 4 do
          for gx = 0, 2 do
            if glyph:sub(gy * 3 + gx + 1, gy * 3 + gx + 1) == "1" then
              pset(x + gx, y + gy, pen)
            end
          end
        end
      end
      x = x + 4
    end
  end
  cursor_x, cursor_y = sx, y + 6
  return x
end

-------------------------------------------------------------------------------
-- shapes
-------------------------------------------------------------------------------
local function rectfill(x0, y0, x1, y1, c)
  if y0 > y1 then y0, y1 = y1, y0 end
  for y = math.floor(y0), math.floor(y1) do
    hline(x0, x1, y, c)
  end
end

local function rect(x0, y0, x1, y1, c)
  hline(x0, x1, y0, c)
  hline(x0, x1, y1, c)
  if y0 > y1 then y0, y1 = y1, y0 end
  for y = math.floor(y0), math.floor(y1) do
    pset_shape(x0, y, c)
    pset_shape(x1, y, c)
  end
end

local function line(x0, y0, x1, y1, c)
  x0, y0, x1, y1 = math.floor(x0), math.floor(y0), math.floor(x1), math.floor(y1)
  local dx, dy = math.abs(x1 - x0), -math.abs(y1 - y0)
  local sx, sy = x0 < x1 and 1 or -1, y0 < y1 and 1 or -1
  local err = dx + dy
  while true do
    pset_shape(x0, y0, c)
    if x0 == x1 and y0 == y1 then break end
    local e2 = 2 * err
    if e2 >= dy then err = err + dy; x0 = x0 + sx end
    if e2 <= dx then err = err + dx; y0 = y0 + sy end
  end
end

local function circ_points(cx, cy, r, fn)
  cx, cy, r = math.floor(cx), math.floor(cy), math.floor(r)
  if r < 0 then return end
  local x, y, d = r, 0, 1 - r
  while y <= x do
    fn(cx, cy, x, y)
    y = y + 1
    if d < 0 then
      d = d + 2 * y + 1
    else
      x = x - 1
      d = d + 2 * (y - x) + 1
    end
  end
end

local function circfill(cx, cy, r, c)
  circ_points(cx, cy, r or 4, function(px, py, x, y)
    hline(px - x, px + x, py + y, c)
    hline(px - x, px + x, py - y, c)
    hline(px - y, px + y, py + x, c)
    hline(px - y, px + y, py - x, c)
  end)
end

local function ovalfill(x0, y0, x1, y1, c)
  if x0 > x1 then x0, x1 = x1, x0 end
  if y0 > y1 then y0, y1 = y1, y0 end
  local cx, cy = (x0 + x1) / 2, (y0 + y1) / 2
  local rx, ry = (x1 - x0) / 2, (y1 - y0) / 2
  for y = math.floor(y0), math.floor(y1) do
    local dy = ry > 0 and (y + 0.5 - cy) / (ry + 0.5) or 0
    local w = (rx + 0.5) * math.sqrt(math.max(0, 1 - dy * dy))
    hline(cx - w + 0.5, cx + w - 0.5, y, c)
  end
end

local function circ(cx, cy, r, c)
  circ_points(cx, cy, r or 4, function(px, py, x, y)
    pset_shape(px + x, py + y, c); pset_shape(px - x, py + y, c)
    pset_shape(px + x, py - y, c); pset_shape(px - x, py - y, c)
    pset_shape(px + y, py + x, c); pset_shape(px - y, py + x, c)
    pset_shape(px + y, py - x, c); pset_shape(px - y, py - x, c)
  end)
end

-------------------------------------------------------------------------------
-- sprites
-------------------------------------------------------------------------------
-- sspr: a sw x sh part of the sheet, stretched to dw x dh
local function sspr(sx, sy, sw, sh, dx, dy, dw, dh, fx, fy)
  sx, sy, sw, sh = math.floor(sx), math.floor(sy), math.floor(sw), math.floor(sh)
  dx, dy = math.floor(dx), math.floor(dy)
  dw, dh = math.floor(dw or sw), math.floor(dh or sh)
  for y = 0, dh - 1 do
    for x = 0, dw - 1 do
      local u = math.floor((fx and dw - 1 - x or x) * sw / dw)
      local v = math.floor((fy and dh - 1 - y or y) * sh / dh)
      local px, py = sx + u, sy + v
      if px >= 0 and px < W and py >= 0 and py < W then
        local c = sheet[py * W + px] or 0
        if not transparent[c] then pset(dx + x, dy + y, c) end
      end
    end
  end
end

local function spr(n, x, y, w, h, fx, fy)
  n = math.floor(n)
  w, h = w or 1, h or 1
  sspr(n % 16 * 8, math.floor(n / 16) * 8, w * 8, h * 8, x, y, w * 8, h * 8, fx, fy)
end

-------------------------------------------------------------------------------
-- input: 0 left 1 right 2 up 3 down 4 O (z/c/n) 5 X (x/v/m)
-------------------------------------------------------------------------------
local KEYS = {
  [0] = { "left" }, { "right" }, { "up" }, { "down" },
  { "z", "c", "n", "return", "kpenter", "space" }, { "x", "v", "m" }, { "p", "escape" },
}
local held_frames = {}
-- `--shots <dir>`: a scripted run (shots.lua) presses the buttons instead
local shots = nil

local function button_down(i)
  if shots then return shots.buttons[i] == true end
  for _, k in ipairs(KEYS[i] or {}) do
    if love.keyboard.isDown(k) then return true end
  end
  return false
end

local function update_buttons()
  for i = 0, 6 do
    held_frames[i] = button_down(i) and (held_frames[i] or 0) + 1 or 0
  end
end

local function btn(i)
  if i == nil then
    local mask = 0
    for b = 0, 6 do
      if held_frames[b] > 0 then mask = mask + 2 ^ b end
    end
    return mask
  end
  return (held_frames[i] or 0) > 0
end

local function btnp(i)
  local f = held_frames[i] or 0
  -- PICO-8 repeat: first frame, then after 15 frames every 4 (at 30fps).
  -- We tick at 60fps, so double those.
  return f == 1 or (f > 30 and (f - 30) % 8 == 0)
end

-------------------------------------------------------------------------------
-- sfx + music: the cart's __sfx__/__music__ data played through synth.lua
-------------------------------------------------------------------------------
local synth = require("synth")
local sources = {}
local sfx_data = {}
local music_pats = {}
local song = nil -- { player = synth music, src = queueable source }

local function to_source(samples)
  local data = love.sound.newSoundData(#samples, synth.RATE, 16, 1)
  for i = 1, #samples do data:setSample(i - 1, samples[i]) end
  return data
end

local function sfx(n)
  local src = sources[n]
  if src then
    src:stop()
    src:play()
  end
end

-- music(n): stream pattern n onward (following loop/stop flags), rendering
-- 4 steps (~0.7 s) at a time so no single frame stalls. music(-1) stops.
local function music(n)
  if song then song.src:stop() end
  song = nil
  n = n or 0
  if n < 0 or not music_pats[n] then return end
  local ok, src = pcall(love.audio.newQueueableSource, synth.RATE, 16, 1, 6)
  if not ok then return end
  song = { player = synth.new_music(sfx_data, music_pats, n, 4), src = src }
end

local function update_music()
  if not song then return end
  if song.src:getFreeBufferCount() > 0 then
    local chunk = song.player.next_chunk()
    if chunk then
      song.src:queue(to_source(chunk))
    end
  end
  if not song.src:isPlaying() then song.src:play() end
end

-------------------------------------------------------------------------------
-- CPU accounting + cart environment
-------------------------------------------------------------------------------
local instructions = 0
local native_depth = 0
local frame_budget = INSTR_PER_SECOND / 60

local function hook()
  if native_depth == 0 then
    instructions = instructions + HOOK_STEP
  end
end

local function native(fn)
  return function(...)
    native_depth = native_depth + 1
    local r = { pcall(fn, ...) }
    native_depth = native_depth - 1
    if not r[1] then error(r[2], 2) end
    return unpack(r, 2)
  end
end

local start_time = 0
local crash_message = nil

-- cartdata: 64 numbers kept in the LÖVE save folder (IndexedDB in a browser)
local cart_file = nil
local cart_nums = {}

local function cartdata(id)
  for i = 0, 63 do cart_nums[i] = 0 end
  if shots then
    -- a scripted run starts from its own save and never writes one
    for i, v in pairs(shots.save or {}) do cart_nums[i] = v end
    return true
  end
  cart_file = tostring(id) .. ".cartdata"
  local saved = love.filesystem.getInfo(cart_file) and love.filesystem.read(cart_file)
  local i = 0
  for v in (saved or ""):gmatch("[^\n]+") do
    cart_nums[i] = tonumber(v) or 0
    i = i + 1
  end
  return saved ~= nil
end

local function dget(i)
  return cart_nums[math.floor(i)] or 0
end

local function dset(i, v)
  i = math.floor(i)
  if i < 0 or i > 63 then return end
  cart_nums[i] = v or 0
  if cart_file then
    local out = {}
    for n = 0, 63 do out[#out + 1] = tostring(cart_nums[n]) end
    love.filesystem.write(cart_file, table.concat(out, "\n"))
  end
end

local function make_env()
  local env = {}

  local api = {
    cls = function(c)
      local col = math.floor(c or 0) % 16
      for i = 0, W * W - 1 do fb[i] = col end
      cursor_x, cursor_y = 0, 0
    end,
    pset = pset,
    pget = function(x, y) return fb[math.floor(y) * W + math.floor(x)] or 0 end,
    rectfill = rectfill, rect = rect, line = line, circfill = circfill, circ = circ,
    ovalfill = ovalfill,
    print = print_text,
    color = function(c) pen = c or 6 end,
    cursor = function(x, y) cursor_x, cursor_y = x or 0, y or 0 end,
    camera = function(x, y) camera_x, camera_y = x or 0, y or 0 end,
    -- pal(c, v), pal(c, v, 1) for the screen palette, pal(table, p)
    pal = function(a, b, p)
      if a == nil then
        reset_pal()
      elseif type(a) == "table" then
        for k, v in pairs(a) do
          if b == 1 then screen_pal[k % 16] = v else draw_pal[k % 16] = v % 16 end
        end
      elseif p == 1 then
        screen_pal[a % 16] = b
      else
        draw_pal[a % 16] = b % 16
      end
    end,
    fillp = function(p)
      p = p or 0
      fill_trans = (p - math.floor(p)) >= 0.5
      fill_pat = math.floor(p) % 65536
    end,
    palt = function(c, t)
      if c == nil then reset_palt() else transparent[c % 16] = t == true end
    end,
    spr = spr, sspr = sspr,
    sget = function(x, y) return sheet[math.floor(y) * W + math.floor(x)] or 0 end,
    sset = function(x, y, c)
      x, y = math.floor(x), math.floor(y)
      if x >= 0 and x < W and y >= 0 and y < W then sheet[y * W + x] = (c or 0) % 16 end
    end,
    clip = function(x, y, w, h)
      if x == nil then
        clip_x0, clip_y0, clip_x1, clip_y1 = 0, 0, W - 1, W - 1
      else
        clip_x0 = math.max(0, math.floor(x))
        clip_y0 = math.max(0, math.floor(y))
        clip_x1 = math.min(W - 1, math.floor(x + w - 1))
        clip_y1 = math.min(W - 1, math.floor(y + h - 1))
      end
    end,
    btn = btn, btnp = btnp,
    sfx = sfx, music = music,
    cartdata = cartdata, dget = dget, dset = dset,
    -- PICO-8's pause menu isn't emulated; carts should offer their own way in
    menuitem = function() end,
    -- memory isn't emulated: draw-state and devkit pokes are no-ops
    poke = function() end, peek = function() return 0 end,
    printh = function(...) print(...) end,
    add = function(t, v) t[#t + 1] = v; return v end,
    del = function(t, v)
      for i = 1, #t do
        if t[i] == v then return table.remove(t, i) end
      end
    end,
    deli = function(t, i) return table.remove(t, i or #t) end,
    count = function(t) return #t end,
    all = function(t)
      local i = 0
      return function()
        i = i + 1
        return t[i]
      end
    end,
    foreach = function(t, f) for _, v in ipairs(t) do f(v) end end,
    abs = math.abs, flr = math.floor, ceil = math.ceil, sqrt = math.sqrt,
    max = function(a, b) return math.max(a or 0, b or 0) end,
    min = function(a, b) return math.min(a or 0, b or 0) end,
    mid = function(a, b, c)
      if a > b then a, b = b, a end
      return math.max(a, math.min(b, c))
    end,
    sgn = function(x) return x < 0 and -1 or 1 end,
    sin = function(a) return -math.sin(a * 2 * math.pi) end,
    cos = function(a) return math.cos(a * 2 * math.pi) end,
    atan2 = function(dx, dy) return (math.atan2(-dy, dx) / (2 * math.pi)) % 1 end,
    rnd = function(n)
      if type(n) == "table" then return n[love.math.random(#n)] end
      return love.math.random() * (n or 1)
    end,
    srand = function(s) love.math.setRandomSeed(s) end,
    sub = function(s, i, j) return string.sub(s, i, j or -1) end,
    tostr = tostring, tonum = tonumber,
    chr = string.char, ord = function(s, i) return s:byte(i or 1) end,
    t = function() return love.timer.getTime() - start_time end,
    time = function() return love.timer.getTime() - start_time end,
    stat = function(n, k)
      if n == 1 or n == 0 then return instructions / frame_budget end
      -- devkit keyboard: raw keys by SDL scancode (enter, keypad enter, r)
      if n == 28 then
        local name = ({ [40] = "return", [88] = "kpenter", [21] = "r" })[k]
        return name ~= nil and love.keyboard.isScancodeDown(name)
      end
      if n == 30 then return false end
      if n == 7 then return 60 end
      return 0
    end,
    stop = function(msg) error("stop(): " .. tostring(msg), 2) end,
  }

  for k, v in pairs(api) do
    env[k] = native(v)
  end

  -- Coroutines can't be wrapped as "native" (yield must cross them), and each
  -- coroutine needs its own instruction hook in Lua 5.1.
  env.cocreate = function(f)
    return coroutine.create(function(...)
      debug.sethook(hook, "", HOOK_STEP)
      return f(...)
    end)
  end
  env.coresume = coroutine.resume
  env.costatus = coroutine.status
  env.yield = coroutine.yield

  env.pairs = pairs
  env.ipairs = ipairs
  env.type = type
  env.unpack = unpack
  env.select = select
  env.tostring = tostring
  env.tonumber = tonumber

  return env
end

local function find_cart()
  for _, name in ipairs(love.filesystem.getDirectoryItems("cart")) do
    if name:match("%.p8$") then return "cart/" .. name end
  end
  error("no cart/*.p8 in the .love")
end

local function read_cart(path)
  local src = assert(love.filesystem.read(path))
  local lua = src:match("__lua__\n(.-)\n__%w+__") or src:match("__lua__\n(.*)$") or ""
  local dir = path:match("^(.*)/") or "."

  lua = lua:gsub("#include%s+([^\n]+)", function(name)
    name = name:gsub("%s+$", "")
    local inc = love.filesystem.read(dir .. "/" .. name)
    if not inc then
      error("cart #include not found: " .. name)
    end
    return inc
  end)

  local function section(name)
    local block = src:match("__" .. name .. "__\n(.-)\n__%w+__") or src:match("__" .. name .. "__\n(.*)$") or ""
    local out = {}
    for l in block:gmatch("[^\n]+") do out[#out + 1] = l end
    return out
  end

  return lua, section("sfx"), section("music"), section("gfx")
end

-------------------------------------------------------------------------------
-- LÖVE callbacks
-------------------------------------------------------------------------------
local env
local accumulator = 0
local step = 1 / 60
local update_fn

-- saves the framebuffer as a PNG, `scale` times bigger, at an OS path
local function capture(path, scale)
  local out = love.image.newImageData(W * scale, W * scale)
  for y = 0, W * scale - 1 do
    for x = 0, W * scale - 1 do
      local c = shown(fb[math.floor(y / scale) * W + math.floor(x / scale)])
      out:setPixel(x, y, c[1], c[2], c[3], 1)
    end
  end
  local f = assert(io.open(path, "wb"))
  f:write(out:encode("png"):getString())
  f:close()
  print("saved " .. path)
end

-- the cart's two frontmatter lines (`-- title`, `-- byline`), read in love.load
local cart_title, cart_byline = "", ""

-- saves the framebuffer as a picture of a PICO-8 cartridge: the frame (the
-- same one that becomes __label__) at 2x in the label window, with the cart's
-- title and byline on the strip under it, like PICO-8 shows its carts
local function capture_cart(path)
  local S = 2 -- label scale
  local LX, LY = 32, 48 -- top left of the label
  local lines = { cart_title }
  if #cart_byline * 4 * S > W * S then
    -- too wide for the strip: wrap "by ... - tagline" at the dash
    local a, b = cart_byline:match("^(.-) %- (.*)$")
    lines[2], lines[3] = a or cart_byline, b
  elseif cart_byline ~= "" then
    lines[2] = cart_byline
  end
  local strip_y = LY + W * S + 12
  local strip_h = 10 + 16 * #lines
  local foot_y = strip_y + strip_h + 14
  local CW, CH = LX * 2 + W * S, foot_y + 10 + 16

  local out = love.image.newImageData(CW, CH)
  local function rect(x0, y0, x1, y1, c)
    local col = rgb[c]
    for y = y0, y1 do
      for x = x0, x1 do out:setPixel(x, y, col[1], col[2], col[3], 1) end
    end
  end
  local function text(str, x, y, c)
    for i = 1, #str do
      local glyph = FONT[str:sub(i, i):lower()]
      if glyph then
        for gy = 0, 4 do
          for gx = 0, 2 do
            if glyph:sub(gy * 3 + gx + 1, gy * 3 + gx + 1) == "1" then
              rect(x + gx * S, y + gy * S, x + gx * S + S - 1, y + gy * S + S - 1, c)
            end
          end
        end
      end
      x = x + 4 * S
    end
  end
  local function centred(str, y, c)
    text(str, math.floor((CW - (#str * 4 - 1) * S) / 2), y, c)
  end

  -- shell: dark outline, grey body, notched corners left transparent
  rect(4, 0, CW - 5, CH - 1, 0)
  rect(0, 4, CW - 1, CH - 5, 0)
  rect(4, 2, CW - 5, CH - 3, 5)
  rect(2, 4, CW - 3, CH - 5, 5)
  rect(4, 2, CW - 5, 3, 13) -- top highlight
  -- grip ridges at the top, coloured dots in the middle
  for y = 10, 30, 5 do
    rect(LX, y, LX + 79, y + 1, 0)
    rect(CW - LX - 80, y, CW - LX - 1, y + 1, 0)
    rect(LX, y + 2, LX + 79, y + 2, 13)
    rect(CW - LX - 80, y + 2, CW - LX - 1, y + 2, 13)
  end
  for i, c in ipairs({ 8, 9, 10, 11, 12 }) do
    local x = math.floor(CW / 2) - 27 + (i - 1) * 11
    rect(x, 15, x + 9, 24, c)
  end
  -- label window
  rect(LX - 4, LY - 4, LX + W * S + 3, LY + W * S + 3, 0)
  for y = 0, W * S - 1 do
    for x = 0, W * S - 1 do
      local col = shown(fb[math.floor(y / S) * W + math.floor(x / S)])
      out:setPixel(LX + x, LY + y, col[1], col[2], col[3], 1)
    end
  end
  -- title strip and the words under it
  rect(LX - 4, strip_y, LX + W * S + 3, strip_y + strip_h - 1, 0)
  for i, l in ipairs(lines) do
    text(l, LX + 6, strip_y + 8 + (i - 1) * 16, i == 1 and 7 or 6)
  end
  centred("pico-8 cartridge", foot_y, 6)

  local f = assert(io.open(path, "wb"))
  f:write(out:encode("png"):getString())
  f:close()
  print("saved " .. path)
end

-- saves the framebuffer as the text of a cart's __label__ section, in the
-- colours shown: 0-f, and g-v for the extra colours 128-143
local LABEL_DIGITS = "0123456789abcdefghijklmnopqrstuv"
local function dump_label(path)
  local rows = {}
  for y = 0, W - 1 do
    local row = {}
    for x = 0, W - 1 do
      local c = screen_pal[fb[y * W + x] or 0] or 0
      if c >= 128 then c = c - 112 end
      row[x + 1] = LABEL_DIGITS:sub(c + 1, c + 1)
    end
    rows[#rows + 1] = table.concat(row)
  end
  local f = assert(io.open(path, "w"))
  f:write(table.concat(rows, "\n"), "\n")
  f:close()
  print("saved " .. path)
end

local function run_cart(fn, ...)
  instructions = 0
  local ok, err = pcall(fn, ...)
  if not ok then
    crash_message = tostring(err)
  end
end

function love.load(args)
  local opts = {}
  for i, a in ipairs(args or {}) do
    if a:sub(1, 2) == "--" then opts[a:sub(3)] = args[i + 1] or "" end
  end
  if opts.shots then
    -- a scripted run has no one to read LÖVE's error screen: print and stop
    love.errorhandler = function(msg)
      print("error: " .. tostring(msg) .. "\n" .. debug.traceback())
      os.exit(1)
    end
    shots = require("shots").new(opts.shots, opts.all ~= nil, capture, opts.label and function()
      dump_label(opts.label)
    end, capture_cart)
  end
  love.graphics.setDefaultFilter("nearest", "nearest")
  image_data = love.image.newImageData(W, W)
  image = love.graphics.newImage(image_data)
  reset_pal()
  for i = 0, W * W - 1 do fb[i] = 0 end
  start_time = love.timer.getTime()

  local lua, sfx_lines, music_lines, gfx_lines = read_cart(find_cart())
  for i = 0, W * W - 1 do sheet[i] = 0 end
  for y, l in ipairs(gfx_lines) do
    for x = 1, math.min(#l, W) do sheet[(y - 1) * W + x - 1] = tonumber(l:sub(x, x), 16) or 0 end
  end
  cart_title, cart_byline = lua:match("^%-%- ([^\n]*)\n%-%- ([^\n]*)")
  cart_title, cart_byline = cart_title or "", cart_byline or ""
  for i, hex in ipairs(sfx_lines) do
    local s = synth.parse_sfx(hex)
    sfx_data[i - 1] = s
    local samples = synth.render_sfx(s)
    if samples then
      sources[i - 1] = love.audio.newSource(to_source(samples), "static")
    end
  end
  for i, l in ipairs(music_lines) do
    music_pats[i - 1] = synth.parse_music(l)
  end

  env = make_env()
  local chunk, err = loadstring(lua, "=cart")
  if not chunk then
    crash_message = err
    return
  end
  setfenv(chunk, env)
  debug.sethook(hook, "", HOOK_STEP)
  run_cart(chunk)

  if env._update60 then
    update_fn, step = env._update60, 1 / 60
  elseif env._update then
    update_fn, step = env._update, 1 / 30
  end
  frame_budget = INSTR_PER_SECOND * step
  if rawget(env, "_init") then run_cart(env._init) end
  if shots then shots:start(env) end
end

function love.update(dt)
  update_music()
  if crash_message and shots then
    -- a scripted run can't go on: say why and stop
    print("cart crashed: " .. crash_message)
    love.event.quit(1)
    return
  end
  if crash_message then return end
  accumulator = math.min(accumulator + dt, step * 4)
  while accumulator >= step and not crash_message do
    accumulator = accumulator - step
    if shots and not shots:tick() then
      love.event.quit()
      return
    end
    update_buttons()
    if update_fn then run_cart(update_fn) end
    if rawget(env, "_draw") and not crash_message then run_cart(env._draw) end
  end
end

function love.draw()
  for y = 0, W - 1 do
    for x = 0, W - 1 do
      local c = shown(fb[y * W + x])
      image_data:setPixel(x, y, c[1], c[2], c[3], 1)
    end
  end
  image:replacePixels(image_data)

  local ww, wh = love.graphics.getDimensions()
  local scale = math.max(SCALE_MIN, math.floor(math.min(ww, wh) / W))
  love.graphics.clear(0, 0, 0)
  love.graphics.setColor(1, 1, 1)
  love.graphics.draw(image, math.floor((ww - W * scale) / 2), math.floor((wh - W * scale) / 2), 0, scale, scale)

  if crash_message then
    love.graphics.setColor(1, 0.3, 0.3)
    love.graphics.printf("cart crashed:\n" .. crash_message, 8, 8, ww - 16)
  end
end
