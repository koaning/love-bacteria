-- PICO-8 preview player, written in LÖVE.
--
-- This is NOT PICO-8. It is a small stand-in that implements just enough of
-- the PICO-8 API (128x128 screen, 16-colour palette, shapes, a 3x5 font,
-- buttons, coroutines, a tiny sfx synth) to play pico8/sporeline.p8 in a
-- browser through love.js when the real PICO-8 isn't available to export an
-- HTML player. For the real thing: `make pico8` / PICO-8's own `export`.
--
-- CPU: PICO-8 gives a cart a fixed instruction budget per frame. We count Lua
-- VM instructions with a debug hook so stat(1) behaves roughly like the real
-- console, which makes the bot "think" for a PICO-8-like number of frames.
--
-- The cart is loaded from cart/sporeline.p8 inside this .love; its #include
-- lines are resolved against cart/ (the build copies pico8/*.lua there).

local W = 128
local SCALE_MIN = 1
local INSTR_PER_SECOND = 4000000 -- PICO-8 spec: "CPU: 4M vm insts/sec" (approx.)
local HOOK_STEP = 500

local PALETTE = {
  [0] = 0x000000, 0x1d2b53, 0x7e2553, 0x008751, 0xab5236, 0x5f574f, 0xc2c3c7, 0xfff1e8,
  0xff004d, 0xffa300, 0xffec27, 0x00e436, 0x29adff, 0x83769c, 0xff77a8, 0xffccaa,
}

local rgb = {}
for i = 0, 15 do
  local c = PALETTE[i]
  rgb[i] = { math.floor(c / 65536) / 255, (math.floor(c / 256) % 256) / 255, (c % 256) / 255 }
end

-- framebuffer of palette indices
local fb = {}
local image_data, image
local draw_pal = {}
local pen = 6
local cursor_x, cursor_y = 0, 0
local camera_x, camera_y = 0, 0
local fill_pat = 0
local fill_trans = false
local clip_x0, clip_y0, clip_x1, clip_y1 = 0, 0, W - 1, W - 1

local function reset_pal()
  for i = 0, 15 do
    draw_pal[i] = i
  end
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
-- input: 0 left 1 right 2 up 3 down 4 O (z/c/n) 5 X (x/v/m)
-------------------------------------------------------------------------------
local KEYS = {
  [0] = { "left" }, { "right" }, { "up" }, { "down" },
  { "z", "c", "n", "return", "space" }, { "x", "v", "m" },
}
local held_frames = {}

local function button_down(i)
  for _, k in ipairs(KEYS[i] or {}) do
    if love.keyboard.isDown(k) then return true end
  end
  return false
end

local function update_buttons()
  for i = 0, 5 do
    held_frames[i] = button_down(i) and (held_frames[i] or 0) + 1 or 0
  end
end

local function btn(i)
  if i == nil then
    local mask = 0
    for b = 0, 5 do
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
-- sfx: a little synth for the cart's __sfx__ section
-------------------------------------------------------------------------------
local sources = {}
local RATE = 22050

local function wave(w, phase)
  local p = phase % 1
  if w == 0 then return math.sin(p * 2 * math.pi) end
  if w == 1 then return 1 - 4 * math.abs(p - 0.5) end
  if w == 2 then return 2 * p - 1 end
  if w == 3 then return p < 0.5 and 1 or -1 end
  if w == 4 then return p < 0.25 and 1 or -1 end
  if w == 5 then return (1 - 4 * math.abs(p - 0.5)) * 0.6 + math.sin(p * 4 * math.pi) * 0.4 end
  if w == 6 then return love.math.random() * 2 - 1 end
  return math.sin(p * 2 * math.pi + math.sin(p * 6 * math.pi))
end

local function build_sfx(hex)
  local speed = tonumber(hex:sub(3, 4), 16)
  local notes = {}
  for n = 0, 31 do
    local s = hex:sub(9 + n * 5, 13 + n * 5)
    notes[#notes + 1] = {
      pitch = tonumber(s:sub(1, 2), 16),
      wave = tonumber(s:sub(3, 3), 16) % 8,
      vol = tonumber(s:sub(4, 4), 16),
      fx = tonumber(s:sub(5, 5), 16),
    }
  end
  local last = 0
  for i, n in ipairs(notes) do
    if n.vol > 0 then last = i end
  end
  if last == 0 or speed == 0 then return nil end

  local per_note = 183 * speed
  local data = love.sound.newSoundData(per_note * last, RATE, 16, 1)
  local phase = 0
  for i = 1, last do
    local n = notes[i]
    local freq = 65.41 * 2 ^ (n.pitch / 12)
    for s = 0, per_note - 1 do
      local t = s / per_note
      local vol = n.vol / 7
      if n.fx == 4 then vol = vol * t end
      if n.fx == 5 then vol = vol * (1 - t) end
      phase = phase + freq / RATE
      data:setSample((i - 1) * per_note + s, wave(n.wave, phase) * vol * 0.25)
    end
  end
  return love.audio.newSource(data, "static")
end

local function sfx(n)
  local src = sources[n]
  if src then
    src:stop()
    src:play()
  end
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
    pal = function(a, b)
      if a == nil then reset_pal() else draw_pal[a % 16] = b % 16 end
    end,
    fillp = function(p)
      p = p or 0
      fill_trans = (p - math.floor(p)) >= 0.5
      fill_pat = math.floor(p) % 65536
    end,
    palt = function() end,
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
    sfx = sfx, music = function() end,
    cartdata = function() end, dget = function() return 0 end, dset = function() end,
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
    stat = function(n)
      if n == 1 or n == 0 then return instructions / frame_budget end
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

  local sfx_block = src:match("__sfx__\n(.-)\n__%w+__") or src:match("__sfx__\n(.*)$") or ""
  local sfx_lines = {}
  for l in sfx_block:gmatch("[^\n]+") do
    sfx_lines[#sfx_lines + 1] = l
  end

  return lua, sfx_lines
end

-------------------------------------------------------------------------------
-- LÖVE callbacks
-------------------------------------------------------------------------------
local env
local accumulator = 0
local step = 1 / 60
local update_fn

local function run_cart(fn, ...)
  instructions = 0
  local ok, err = pcall(fn, ...)
  if not ok then
    crash_message = tostring(err)
  end
end

function love.load()
  love.graphics.setDefaultFilter("nearest", "nearest")
  image_data = love.image.newImageData(W, W)
  image = love.graphics.newImage(image_data)
  reset_pal()
  for i = 0, W * W - 1 do fb[i] = 0 end
  start_time = love.timer.getTime()

  local lua, sfx_lines = read_cart("cart/sporeline.p8")
  for i, hex in ipairs(sfx_lines) do
    local ok, src = pcall(build_sfx, hex)
    if ok then sources[i - 1] = src end
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
end

function love.update(dt)
  if crash_message then return end
  accumulator = math.min(accumulator + dt, step * 4)
  while accumulator >= step and not crash_message do
    accumulator = accumulator - step
    update_buttons()
    if update_fn then run_cart(update_fn) end
    if rawget(env, "_draw") and not crash_message then run_cart(env._draw) end
  end
end

function love.draw()
  for y = 0, W - 1 do
    for x = 0, W - 1 do
      local c = rgb[fb[y * W + x] or 0]
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
