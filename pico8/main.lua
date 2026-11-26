-- main.lua (pico-8 only)
-- the pico-8 "body": input, drawing, turn flow. no love
-- counterpart is expected to match this file line for line;
-- only board/rules/ai are mirrored.
--
-- the look follows mossballs (koaning.io/posts/mossballs):
-- shaded balls with pupils, a floating selected ball, hops
-- in an arc, and captured balls that pop up and flip colour
-- mid-air.

local difficulties = { "easy", "medium", "hard" }
local theme_names = { "light", "dark" }
local theme_pals = {
  light = {
    bg_out = 6, bg_in = 7, play_bg = 6,
    tray_sh = 13, tray_well = 13, tray_hi = 7, tray_lo = 5,
    tile_bg = 7, tile_dot = 6, tile_sh = 6,
    ball_sh = 13,
    grow_c = 3, grow_hi = 11, jump_c = 12, jump_hi = 1,
    cur_a = 1, cur_b = 5,
    p_txt = 3, e_txt = 4,
    bar_bg = 7, bar_rim = 13, bar_tick = 5,
    foot = 5,
    logo_top = 11, logo_bot = 3, logo_out = 5, plaque = true, diam_out = 1,
    dish_sh = 13, dish_rim = 5, dish_bg = 6, dish_dith = 7, dish_hi = 7,
    card_bg = 7, card_in = 6, card_hi = 7, card_lo = 13, card_sh = 13, card_div = 6,
    lbl_on = 1, lbl_off = 13, arr_on = 1, arr_off = 6,
    diff = { 3, 4, 8 }, theme_val = 12,
    go_bg = 7, go_in = 6, go_hi = 5, go_lo = 13,
    go_sub = 5, go_score = 1, go_sh = 6,
    go_win_p = 3, go_win_e = 4, go_tie = 5,
    spore_c = { 13, 12, 15 },
  },
  dark = {
    bg_out = 0, bg_in = 1, play_bg = 0,
    tray_sh = 0, tray_well = 0, tray_hi = 13, tray_lo = 1,
    tile_bg = 1, tile_dot = 13, tile_sh = 0,
    ball_sh = 0,
    grow_c = 11, grow_hi = 7, jump_c = 12, jump_hi = 7,
    cur_a = 7, cur_b = 10,
    p_txt = 11, e_txt = 9,
    bar_bg = 0, bar_rim = 1, bar_tick = 13,
    foot = 13,
    logo_top = 11, logo_bot = 3, logo_out = 0, plaque = false, diam_out = 7,
    dish_sh = 0, dish_rim = 13, dish_bg = 1, dish_dith = 0, dish_hi = 6,
    card_bg = 0, card_in = 1, card_hi = 13, card_lo = 1, card_sh = 0, card_div = 1,
    lbl_on = 7, lbl_off = 13, arr_on = 7, arr_off = 1,
    diff = { 11, 10, 9 }, theme_val = 12,
    go_bg = 1, go_in = 0, go_hi = 13, go_lo = 0,
    go_sub = 13, go_score = 7, go_sh = 0,
    go_win_p = 11, go_win_e = 9, go_tie = 6,
    spore_c = { 13, 3, 4 },
  },
}
local history_limit = 8
local ai_delay = 25
local fly_dur = 18
local react_dur = 22

local tile = 13
local board_ox = 18
local board_oy = 17

-- base (rim), lit (body), spec (highlight)
local looks = {
  player = { 3, 11, 7 },
  enemy = { 4, 9, 15 },
}

local dxs = { -1, 0, 1, -1, 1, -1, 0, 1 }
local dys = { -1, -1, -1, 0, 0, 1, 1, 1 }

-- crisp 1px-resolution 9px-tall pixel glyphs for the title logo
local logo_glyphs = {
  m = { 9,
    "110000011" ..
    "111000111" ..
    "111101111" ..
    "110111011" ..
    "110010011" ..
    "110000011" ..
    "110000011" ..
    "110000011" ..
    "110000011" },
  o = { 7,
    "0111110" ..
    "1111111" ..
    "1100011" ..
    "1100011" ..
    "1100011" ..
    "1100011" ..
    "1100011" ..
    "1111111" ..
    "0111110" },
  s = { 7,
    "0111110" ..
    "1111111" ..
    "1100000" ..
    "1111110" ..
    "0111111" ..
    "0000011" ..
    "0000011" ..
    "1111111" ..
    "0111110" },
  b = { 7,
    "1111100" ..
    "1111110" ..
    "1100011" ..
    "1111100" ..
    "1111110" ..
    "1100011" ..
    "1100011" ..
    "1111110" ..
    "1111100" },
  a = { 7,
    "0011100" ..
    "0111110" ..
    "1100011" ..
    "1100011" ..
    "1111111" ..
    "1111111" ..
    "1100011" ..
    "1100011" ..
    "1100011" },
  l = { 6,
    "110000" ..
    "110000" ..
    "110000" ..
    "110000" ..
    "110000" ..
    "110000" ..
    "110000" ..
    "111111" ..
    "111111" },
}

-- subtle ambient background spores (kept clear of hud/footer text)
local spores = {
  { 7, 22, 0.14, 1 }, { 120, 28, 0.19, 2 }, { 10, 52, 0.11, 1 },
  { 119, 58, 0.16, 1 }, { 6, 86, 0.13, 2 }, { 121, 92, 0.17, 3 },
  { 12, 104, 0.12, 1 }, { 116, 106, 0.15, 1 }, { 16, 38, 0.18, 2 },
  { 112, 42, 0.15, 3 },
}

local scene = "title"
local diff_i = 2
local theme_i = 1
local menu_row = 1

local function th()
  return theme_pals[theme_names[theme_i]]
end

local state = nil
local history = {}
local cur = { x = 1, y = 1 }
local selected = nil
local targets = {}
local anim = nil
local ai_co = nil
local ai_wait = 0
local sparks = {}

-- called from ai.lua hot loops: give the frame back before
-- pico-8 runs out of cpu, then carry on next frame.
function ai_tick()
  if stat(1) > 0.8 then
    yield()
  end
end

local function cycle(i, n, step)
  return (i - 1 + step) % n + 1
end

local function record(st)
  add(history, ai_state_hash(st))
  while #history > history_limit do
    deli(history, 1)
  end
end

local function tile_xy(x, y)
  return board_ox + (x - 1) * tile, board_oy + (y - 1) * tile
end

local function ball_xy(x, y)
  local px, py = tile_xy(x, y)
  return px + 6, py + 6
end

local function spawn_sparks(cx, cy, side, n)
  local cols = looks[side]
  for i = 1, n do
    local a = (i - 1) / n + rnd(0.12)
    local spd = 0.4 + rnd(0.6)
    add(sparks, {
      x = cx,
      y = cy,
      vx = cos(a) * spd,
      vy = sin(a) * spd - 0.25,
      life = 14 + flr(rnd(8)),
      max_life = 22,
      c1 = cols[3],
      c2 = cols[2],
      c3 = cols[1],
    })
  end
end

local function update_sparks()
  for i = #sparks, 1, -1 do
    local p = sparks[i]
    p.x = p.x + p.vx
    p.y = p.y + p.vy
    p.vy = p.vy + 0.04
    p.life = p.life - 1
    if p.life <= 0 then
      deli(sparks, i)
    end
  end
end

-------------------------------------------------------------
-- turn flow: a move is a hop animation, then the board
-- updates, then captured balls react.
-------------------------------------------------------------

local function start_move(move)
  selected = nil
  targets = {}
  anim = {
    phase = "fly",
    t = 0,
    move = move,
    side = state.current_player,
    jump = move.kind == "jump",
    conv = {},
  }
end

local function land()
  local a = anim
  local prev = state
  state = rules_resolve_state(rules_apply_move(prev, a.move))
  record(state)

  local lx, ly = ball_xy(a.move.to.x, a.move.to.y)
  spawn_sparks(lx, ly, a.side, 6)

  local foe = other_side(a.side)
  for y = 1, state.height do
    for x = 1, state.width do
      if prev.cells[y][x] == foe and state.cells[y][x] == a.side then
        add(a.conv, { x = x, y = y })
        local cx, cy = ball_xy(x, y)
        spawn_sparks(cx, cy, a.side, 5)
      end
    end
  end

  if #a.conv > 0 then
    sfx(1)
  else
    sfx(0)
  end
  if a.side == "player" then
    cur = { x = a.move.to.x, y = a.move.to.y }
  end
  a.phase = "react"
  a.t = 0
end

local function update_anim()
  anim.t = anim.t + 1
  if anim.phase == "fly" then
    if anim.t >= fly_dur then
      land()
    end
  elseif anim.t >= react_dur then
    anim = nil
    ai_wait = ai_delay
  end
end

local function start_game()
  history = {}
  selected = nil
  targets = {}
  anim = nil
  ai_co = nil
  ai_wait = ai_delay
  sparks = {}
  state = rules_resolve_state(level_load())
  cur = { x = 1, y = 1 }
  scene = "play"
end

local function target_at(x, y)
  for m in all(targets) do
    if m.to.x == x and m.to.y == y then
      return m
    end
  end
  return nil
end

local function update_title()
  if btnp(2) or btnp(3) then
    menu_row = cycle(menu_row, 2, 1)
  end
  local step = 0
  if btnp(0) then step = -1 end
  if btnp(1) then step = 1 end
  if step ~= 0 then
    if menu_row == 1 then
      diff_i = cycle(diff_i, #difficulties, step)
    else
      theme_i = cycle(theme_i, #theme_names, step)
    end
  end
  if btnp(4) or btnp(5) then
    start_game()
  end
end

local function update_player()
  if btnp(0) then cur.x = max(1, cur.x - 1) end
  if btnp(1) then cur.x = min(state.width, cur.x + 1) end
  if btnp(2) then cur.y = max(1, cur.y - 1) end
  if btnp(3) then cur.y = min(state.height, cur.y + 1) end

  if btnp(5) then
    selected = nil
    targets = {}
  end

  if btnp(4) then
    local m = selected and target_at(cur.x, cur.y)
    if m then
      start_move(m)
    elseif board_get_cell(state, cur.x, cur.y) == "player" then
      if board_same_cell(selected, cur) then
        selected = nil
        targets = {}
      else
        selected = { x = cur.x, y = cur.y }
        targets = rules_get_piece_moves(state, "player", cur.x, cur.y)
      end
    else
      sfx(2)
    end
  end
end

local function update_enemy()
  if ai_wait > 0 then
    ai_wait = ai_wait - 1
    return
  end

  if not ai_co then
    local snapshot = state
    ai_co = cocreate(function()
      return ai_choose_move(snapshot, "enemy", difficulties[diff_i], history)
    end)
  end

  local ok, move = coresume(ai_co)
  if not ok then
    -- surface ai crashes instead of hanging on "thinking"
    stop(move)
  end
  if costatus(ai_co) == "dead" then
    ai_co = nil
    if move then
      start_move(move)
    else
      state = rules_resolve_state(state)
    end
  end
end

function _update60()
  update_sparks()

  if scene == "title" then
    update_title()
    return
  end

  if anim then
    update_anim()
    return
  end

  if state.winner then
    if btnp(4) or btnp(5) then
      scene = "title"
    end
    return
  end

  if state.current_player == "player" then
    update_player()
  else
    update_enemy()
  end
end

-------------------------------------------------------------
-- drawing helpers
-------------------------------------------------------------

local function draw_title_backdrop()
  local p = th()
  cls(p.bg_out)
  -- soft dithered petri-dish radial glow for title screen
  fillp(0x5f5f + 0.5)
  circfill(64, 62, 74, p.bg_in)
  fillp(0x5a5a + 0.5)
  circfill(64, 62, 60, p.bg_in)
  fillp()
  circfill(64, 62, 46, p.bg_in)

  -- subtle drifting background micro-spores
  local tm = time()
  for i = 1, #spores do
    local sp = spores[i]
    local sx = sp[1] + sin(tm * sp[3] + i * 0.17) * 2
    local sy = sp[2] + cos(tm * sp[3] * 0.8 + i * 0.23) * 2
    pset(sx, sy, p.spore_c[sp[4]])
  end
end

local function draw_panel(x0, y0, x1, y1, bg, hi, lo, sh)
  -- drop shadow
  rectfill(x0 + 2, y0 + 2, x1 + 2, y1 + 2, sh or 0)
  -- rounded/chamfered body
  rectfill(x0 + 1, y0, x1 - 1, y1, bg)
  rectfill(x0, y0 + 1, x1, y1 - 1, bg)
  -- top & left highlight bevel
  line(x0 + 1, y0, x1 - 1, y0, hi)
  line(x0, y0 + 1, x0, y1 - 1, hi)
  -- bottom & right shade bevel
  line(x0 + 1, y1, x1 - 1, y1, lo)
  line(x1, y0 + 1, x1, y1 - 1, lo)
end

-- exact pixel ink width (wide button glyphs >= 128 are 8px, ascii is 4px)
local function text_w(s)
  local w = 0
  for i = 1, #s do
    w = w + (ord(s, i) >= 128 and 8 or 4)
  end
  return max(0, w - 1)
end

local function cprint(s, y, c)
  print(s, flr((128 - text_w(s)) / 2), y, c)
end

-- a new look direction every ~1.25s; the seed desyncs balls
local function glance(seed)
  local n = flr(time() * 0.8 + seed * 0.37) % 8
  return dxs[n + 1], dys[n + 1]
end

-- pupil offset toward a target: -1, 0 or 1
local function look_toward(d)
  if d > 1 then return 1 end
  if d < -1 then return -1 end
  return 0
end

-- flat ground shadow that shrinks cleanly as the ball rises
local function ground_shadow(cx, by, h)
  local r = flr(4 - h * 0.4)
  if r >= 1 then
    local y1 = by + 4
    if r >= 3 then y1 = by + 5 end
    ovalfill(cx - r, by + 4, cx + r, y1, th().ball_sh)
  end
end

-- lx/ly: pupil offsets (-1..1). lifted balls skip the
-- contact shadow and draw a ground_shadow instead.
local function draw_ball(cx, cy, side, lx, ly, lifted, blink, alarmed)
  local c = looks[side]
  if not lifted then
    ovalfill(cx - 3, cy + 4, cx + 3, cy + 5, th().ball_sh)
  end
  -- 3-tone shaded mossball
  circfill(cx, cy, 4, c[1])
  circfill(cx - 1, cy - 1, 3, c[2])
  pset(cx - 2, cy - 2, c[3])
  pset(cx - 1, cy - 3, c[3])

  -- inset eyes that stay neatly on the lit face
  local ex1 = cx - 2 + lx
  local ex2 = cx + 2 + lx
  if lx > 0 then ex2 = cx + 2 end
  if lx < 0 then ex1 = cx - 2 end
  local ey = cy + ly

  if alarmed then
    -- wide startled eyes when threatened by a hovered move
    pset(ex1, ey - 1, 7)
    pset(ex2, ey - 1, 7)
    pset(ex1, ey, 0)
    pset(ex2, ey, 0)
  elseif blink then
    pset(ex1, ey, c[1])
    pset(ex2, ey, c[1])
  else
    pset(ex1, ey, 0)
    pset(ex2, ey, 0)
  end
end

local function draw_mini_ball(cx, cy, side)
  local c = looks[side]
  circfill(cx, cy, 2, c[2])
  pset(cx + 1, cy + 2, c[1])
  pset(cx + 2, cy + 1, c[1])
  pset(cx, cy + 2, c[1])
  pset(cx + 2, cy, c[1])
  pset(cx - 1, cy - 1, c[3])
end

local function draw_sparks()
  for p in all(sparks) do
    local r = p.life / p.max_life
    local c = p.c3
    if r > 0.65 then
      c = p.c1
    elseif r > 0.3 then
      c = p.c2
    end
    pset(p.x, p.y, c)
  end
end

-------------------------------------------------------------
-- board & gameplay rendering
-------------------------------------------------------------

local function draw_board_frame()
  local p = th()
  local x0 = board_ox - 2
  local y0 = board_oy - 2
  local x1 = board_ox + state.width * tile + 1
  local y1 = board_oy + state.height * tile + 1

  -- subtle bottom drop shadow
  rectfill(x0 + 1, y1 + 1, x1 + 1, y1 + 2, p.tray_sh)
  -- clean rounded dish frame
  rectfill(x0 + 1, y0, x1 - 1, y1, p.tray_well)
  rectfill(x0, y0 + 1, x1, y1 - 1, p.tray_well)
  -- quiet 1px outer rim
  line(x0 + 1, y0, x1 - 1, y0, p.tray_hi)
  line(x0, y0 + 1, x0, y1 - 1, p.tray_hi)
  line(x0 + 1, y1, x1 - 1, y1, p.tray_lo)
  line(x1, y0 + 1, x1, y1 - 1, p.tray_lo)
end

local function draw_tile(px, py, x, y)
  local p = th()
  -- calm uniform cell with subtle alternating top-left pin dot
  rectfill(px + 1, py + 1, px + 11, py + 11, p.tile_bg)
  if (x + y) % 2 == 0 then
    pset(px + 1, py + 1, p.tile_dot)
  end
  -- soft inner depth along bottom-right
  line(px + 1, py + 11, px + 11, py + 11, p.tile_sh)
  line(px + 11, py + 1, px + 11, py + 11, p.tile_sh)
end

local function draw_target(px, py, kind, hovered)
  local p = th()
  local cx, cy = px + 6, py + 6
  if kind == "grow" then
    -- dot = grow target
    if hovered then
      circfill(cx, cy, 2, p.grow_c)
      pset(cx - 1, cy - 1, p.grow_hi)
    else
      circfill(cx, cy, 1, p.grow_c)
    end
  else
    -- hollow ring = jump target
    circ(cx, cy, 2, hovered and p.jump_hi or p.jump_c)
  end
end

local function is_converting(x, y)
  if anim and anim.phase == "react" then
    for c in all(anim.conv) do
      if c.x == x and c.y == y then
        return true
      end
    end
  end
  return false
end

local function is_threatened(x, y, hover_move)
  if not hover_move then return false end
  if state.cells[y][x] ~= "enemy" then return false end
  return abs(x - hover_move.to.x) <= 1 and abs(y - hover_move.to.y) <= 1
end

local function draw_cell_ball(x, y, hover_move)
  local side = state.cells[y][x]
  local cx, cy = ball_xy(x, y)
  local a = anim

  -- a jumping ball is in the air: its old tile is empty
  if a and a.phase == "fly" and a.jump
    and x == a.move.from.x and y == a.move.from.y then
    return
  end

  if a and a.phase == "react" then
    local pr = a.t / react_dur
    -- captured neighbours pop up and flip colour mid-air
    if is_converting(x, y) then
      local lift = abs(sin(pr * 0.5)) * 6
      local shown = side
      if pr < 0.5 then shown = other_side(side) end
      local lx, ly = glance(x * 3 + y * 5)
      ground_shadow(cx, cy, lift)
      draw_ball(cx, cy - lift, shown, lx, ly, true, false, false)
      return
    end
    -- the freshly landed ball gives a small settle bounce
    if x == a.move.to.x and y == a.move.to.y then
      local lift = abs(sin(pr * 0.5)) * 2
      ground_shadow(cx, cy, lift)
      draw_ball(cx, cy - lift, side, 0, 1, true, false, false)
      return
    end
  end

  -- the selected ball floats above its tile and eyes the cursor
  if not a and board_same_cell(selected, { x = x, y = y }) then
    local lift = 2 + abs(sin(time() * 0.8)) * 2
    local tx, ty = ball_xy(cur.x, cur.y)
    ground_shadow(cx, cy, lift)
    draw_ball(cx, cy - lift, side, look_toward(tx - cx), look_toward(ty - cy), true, false, false)
    return
  end

  -- enemy balls adjacent to a hovered legal target glance over nervously
  if not a and is_threatened(x, y, hover_move) then
    local tx, ty = ball_xy(hover_move.to.x, hover_move.to.y)
    draw_ball(cx, cy, side, look_toward(tx - cx), look_toward(ty - cy), false, false, true)
    return
  end

  local seed = x * 3 + y * 5 + (side == "enemy" and 7 or 0)
  local lx, ly = glance(seed)
  local blink = (flr(time() * 60) + seed * 41) % 240 < 5
  draw_ball(cx, cy, side, lx, ly, false, blink, false)
end

local function draw_flying_ball()
  local m = anim.move
  local fx, fy = ball_xy(m.from.x, m.from.y)
  local tx, ty = ball_xy(m.to.x, m.to.y)
  local pr = anim.t / fly_dur
  local cx = fx + (tx - fx) * pr
  local cy = fy + (ty - fy) * pr
  local hop = abs(sin(pr * 0.5)) * 8
  if not anim.jump then hop = hop * 0.6 end
  ground_shadow(cx, cy, hop)
  draw_ball(cx, cy - hop, anim.side, look_toward(tx - cx), look_toward(ty - cy), true, false, false)
end

local function draw_cursor(px, py)
  local p = th()
  local x0, y0 = px, py
  local x1, y1 = px + 12, py + 12
  local c = time() % 0.9 < 0.45 and p.cur_a or p.cur_b

  -- crisp 2px corner reticle ticks
  line(x0, y0, x0 + 2, y0, c)
  line(x0, y0, x0, y0 + 2, c)
  line(x1 - 2, y0, x1, y0, c)
  line(x1, y0, x1, y0 + 2, c)
  line(x0, y1, x0 + 2, y1, c)
  line(x0, y1 - 2, x0, y1, c)
  line(x1 - 2, y1, x1, y1, c)
  line(x1, y1 - 2, x1, y1, c)
end

local function draw_board()
  draw_board_frame()

  local hover_move = (not anim and selected) and target_at(cur.x, cur.y) or nil

  for y = 1, state.height do
    for x = 1, state.width do
      local px, py = tile_xy(x, y)
      draw_tile(px, py, x, y)

      local m = not anim and target_at(x, y)
      if m then
        local hovered = cur.x == x and cur.y == y
        draw_target(px, py, m.kind, hovered)
      end
    end
  end

  -- balls after tiles so lifted balls can overlap the row above
  for y = 1, state.height do
    for x = 1, state.width do
      if state.cells[y][x] ~= "empty" then
        draw_cell_ball(x, y, hover_move)
      end
    end
  end

  if anim and anim.phase == "fly" then
    draw_flying_ball()
  end

  draw_sparks()

  if not anim and not state.winner and state.current_player == "player" then
    local px, py = tile_xy(cur.x, cur.y)
    draw_cursor(px, py)
  end
end

local function draw_hud()
  local pal = th()
  local p = board_count_cells(state, "player")
  local e = board_count_cells(state, "enemy")
  local total = state.width * state.height

  -- player side: mini spore icon + count
  draw_mini_ball(8, 7, "player")
  local pt = tostr(p)
  print(pt, 14, 5, pal.p_txt)

  -- bot side: count + mini spore icon
  local et = tostr(e)
  print(et, 114 - text_w(et), 5, pal.e_txt)
  draw_mini_ball(119, 7, "enemy")

  -- sleek territory bar (matches the love edition)
  local bx0, bx1, by0, by1 = 27, 100, 6, 8
  rect(bx0 - 1, by0 - 1, bx1 + 1, by1 + 1, pal.bar_rim)
  rectfill(bx0, by0, bx1, by1, pal.bar_bg)

  local inner_w = bx1 - bx0 + 1
  if p > 0 then
    local pw = max(2, flr(p * inner_w / total + 0.5))
    rectfill(bx0, by0, bx0 + pw - 1, by1, 11)
    line(bx0, by1, bx0 + pw - 1, by1, 3)
  end
  if e > 0 then
    local ew = max(2, flr(e * inner_w / total + 0.5))
    rectfill(bx1 - ew + 1, by0, bx1, by1, 9)
    line(bx1 - ew + 1, by1, bx1, by1, 4)
  end
  pset(64, by0 - 1, pal.bar_tick)

  -- quiet bottom controls strip
  if not state.winner then
    if not anim and state.current_player == "enemy" then
      local dots = sub("...", 1, flr(time() * 3) % 4)
      print("bot thinking" .. dots, flr((128 - text_w("bot thinking...")) / 2), 117, pal.e_txt)
    elseif selected then
      cprint("\142 move   \151 cancel", 117, pal.foot)
    else
      cprint("\142 pick spore", 117, pal.foot)
    end
  end
end

local function draw_game_over()
  local pal = th()
  local x0, y0, x1, y1 = 12, 38, 115, 88
  draw_panel(x0, y0, x1, y1, pal.go_bg, pal.go_hi, pal.go_lo, pal.card_sh)
  rect(x0 + 2, y0 + 2, x1 - 2, y1 - 2, pal.go_in)

  local msg, accent = "a tie!", pal.go_tie
  if state.winner == "player" then
    msg, accent = "you win!", pal.go_win_p
  elseif state.winner == "enemy" then
    msg, accent = "bot wins", pal.go_win_e
  end

  cprint("game over", y0 + 6, pal.go_sub)
  -- shadowed headline
  local mx = flr((128 - text_w(msg)) / 2)
  print(msg, mx + 1, y0 + 18, pal.go_sh)
  print(msg, mx, y0 + 17, accent)

  local p = board_count_cells(state, "player")
  local e = board_count_cells(state, "enemy")
  cprint("you " .. p .. " - " .. e .. " bot", y0 + 27, pal.go_score)

  line(x0 + 10, y0 + 35, x1 - 10, y0 + 35, pal.go_in)
  cprint("\142 play again", y0 + 39, pal.foot)

  -- the winners flank the result and glance around idly
  if state.winner ~= "tie" then
    local hop = abs(sin(time() * 1.2)) * 3
    local lx, ly = glance(0)
    ground_shadow(x0 + 13, y0 + 22, hop)
    draw_ball(x0 + 13, y0 + 22 - hop, state.winner, lx, ly, true, false, false)
    local rx, ry = glance(3)
    ground_shadow(x1 - 13, y0 + 22, hop)
    draw_ball(x1 - 13, y0 + 22 - hop, state.winner, rx, ry, true, false, false)
  end
end

-------------------------------------------------------------
-- title screen
-------------------------------------------------------------

local function draw_logo(word, ox, oy, pal)
  -- draw crisp 1px-resolution 9px-tall pixel wordmark with 3d drop shadow
  local function render(dx, dy, flat_col)
    local cx = ox
    for k = 1, #word do
      local ch = sub(word, k, k)
      local g = logo_glyphs[ch]
      local w, bits = g[1], g[2]
      for r = 0, 8 do
        for c = 0, w - 1 do
          if sub(bits, r * w + c + 1, r * w + c + 1) == "1" then
            local col = flat_col
            if not col then
              if pal.plaque and r == 0 then
                col = 7
              elseif r < 5 then
                col = pal.logo_top
              elseif r < 8 then
                -- dithered mid-green so the lower shade feels lighter and softer
                col = (c + r) % 2 == 0 and pal.logo_top or pal.logo_bot
              else
                col = pal.logo_bot
              end
            end
            pset(cx + c + dx, oy + r + dy, col)
          end
        end
      end
      cx = cx + w + 3
    end
  end

  -- crisp bottom-right drop shadow (keeps letter counters wide open)
  render(1, 2, pal.logo_out)
  render(1, 1, pal.logo_out)
  render(0, 1, pal.logo_out)
  render(0, 0, nil)
end

local function draw_setting_row(y, label, val, val_col, active, x0, x1, pal)
  local ax0, ax1 = x0 + 36, x1 - 9
  local nudge = (active and sin(time() * 2) > 0.3) and 1 or 0
  if active then
    -- tiny selection caret on focused row
    line(x0 + 4, y + 1, x0 + 4, y + 3, val_col)
    pset(x0 + 5, y + 2, val_col)
  end
  print(label, x0 + 8, y, active and pal.lbl_on or pal.lbl_off)
  local ac = active and pal.arr_on or pal.arr_off
  print("<", ax0 - nudge, y, ac)
  local vcx = flr((ax0 + 3 + ax1 - text_w(val)) / 2)
  print(val, vcx, y, val_col)
  print(">", ax1 + nudge, y, ac)
end

local function draw_title()
  local pal = th()
  if pal.plaque then
    -- warm wood banner plaque behind the green mossballs wordmark
    rectfill(15, 11, 114, 27, pal.card_sh)
    rectfill(15, 9, 112, 25, 4)
    rectfill(14, 10, 113, 24, 4)
    line(15, 9, 112, 9, 9)
    line(14, 10, 14, 24, 5)
    line(113, 10, 113, 24, 5)
    line(15, 25, 112, 25, 5)
  end

  -- crisp 9px-tall logo centered at x=20 (width 87)
  draw_logo("mossballs", 20, pal.plaque and 13 or 15, pal)

  -- two-tone rivalry underline with clean breathing room below the banner
  line(20, 34, 60, 34, 3)
  line(20, 33, 60, 33, 11)
  line(67, 34, 107, 34, 4)
  line(67, 33, 107, 33, 9)
  -- tiny diamond centerpiece
  pset(64, 32, pal.diam_out)
  pset(63, 33, pal.diam_out)
  pset(64, 33, 10)
  pset(65, 33, pal.diam_out)
  pset(64, 34, pal.diam_out)

  -- shallow 3d petri-dish stage for the hopping mossballs
  ovalfill(10, 58, 118, 72, pal.dish_sh)
  ovalfill(10, 56, 118, 70, pal.dish_rim)
  ovalfill(11, 57, 117, 69, pal.dish_bg)
  fillp(0x5a5a + 0.5)
  ovalfill(13, 58, 115, 68, pal.dish_dith)
  fillp()
  -- soft inner glass reflection arc
  line(28, 57, 48, 57, pal.dish_hi)

  -- a line of balls hopping in a wave, eyeing their neighbour
  for i = 0, 6 do
    local side = "player"
    if i % 2 == 1 then side = "enemy" end
    local cx = 22 + i * 14
    local by = 59
    local hop = abs(sin(time() * 0.6 + i / 7)) * 9
    local lx = 1
    if i % 2 == 1 then lx = -1 end
    local blink = (flr(time() * 60) + i * 53) % 210 < 5
    ground_shadow(cx, by, hop)
    draw_ball(cx, by - hop, side, lx, 0, true, blink, false)
  end

  -- framed 2-row settings card: bot difficulty + theme
  local x0, y0, x1, y1 = 18, 79, 109, 106
  draw_panel(x0, y0, x1, y1, pal.card_bg, pal.card_hi, pal.card_lo, pal.card_sh)
  rect(x0 + 1, y0 + 1, x1 - 1, y1 - 1, pal.card_in)

  draw_setting_row(y0 + 5, "bot", difficulties[diff_i], pal.diff[diff_i], menu_row == 1, x0, x1, pal)
  line(x0 + 6, y0 + 13, x1 - 6, y0 + 13, pal.card_div)
  draw_setting_row(y0 + 17, "theme", theme_names[theme_i], pal.theme_val, menu_row == 2, x0, x1, pal)

  -- centered controls footer
  cprint("\139\145 set   \142 play", 116, pal.foot)
end

function _draw()
  if scene == "title" then
    draw_title_backdrop()
    draw_title()
    return
  end
  cls(th().play_bg)
  draw_board()
  draw_hud()
  if state.winner and not anim then
    draw_game_over()
  end
end
