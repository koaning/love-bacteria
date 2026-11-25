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
local history_limit = 8
local ai_delay = 25
local fly_dur = 18
local react_dur = 22

local tile = 13
local board_ox = 18
local board_oy = 16

-- base (rim), lit (body), spec (highlight)
local looks = {
  player = { 3, 11, 7 },
  enemy = { 4, 9, 15 },
}

local dxs = { -1, 0, 1, -1, 1, -1, 0, 1 }
local dys = { -1, -1, -1, 0, 0, 1, 1, 1 }

local scene = "title"
local diff_i = 2

local state = nil
local history = {}
local cur = { x = 1, y = 1 }
local selected = nil
local targets = {}
local anim = nil
local ai_co = nil
local ai_wait = 0

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

  local foe = other_side(a.side)
  for y = 1, state.height do
    for x = 1, state.width do
      if prev.cells[y][x] == foe and state.cells[y][x] == a.side then
        add(a.conv, { x = x, y = y })
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
  if btnp(0) then diff_i = cycle(diff_i, #difficulties, -1) end
  if btnp(1) then diff_i = cycle(diff_i, #difficulties, 1) end
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
-- drawing
-------------------------------------------------------------

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

-- flat ground shadow that shrinks as the ball rises
local function ground_shadow(cx, by, h)
  local r = 4 - h / 2
  if r >= 1 then
    ovalfill(cx - r, by + 4, cx + r, by + 5, 0)
  end
end

-- lx/ly: pupil offsets (-1..1). lifted balls skip the
-- contact shadow and draw a ground_shadow instead.
local function draw_ball(cx, cy, side, lx, ly, lifted)
  local c = looks[side]
  if not lifted then
    circfill(cx, cy + 1, 4, 0)
  end
  circfill(cx, cy, 4, c[1])
  circfill(cx - 1, cy - 1, 3, c[2])
  pset(cx - 2, cy - 2, c[3])
  pset(cx - 2 + lx, cy - 1 + ly, 0)
  pset(cx + 2 + lx, cy - 1 + ly, 0)
end

local function draw_tile(px, py, x, y)
  rectfill(px, py, px + 12, py + 12, 0)
  local c = 1
  if (x + y) % 2 == 0 then c = 13 end
  rectfill(px + 1, py + 1, px + 11, py + 11, c)
  -- 1px bevel: light top-left, dark bottom-right
  line(px + 1, py + 1, px + 11, py + 1, 12)
  line(px + 1, py + 1, px + 1, py + 11, 12)
  line(px + 1, py + 11, px + 11, py + 11, 0)
  line(px + 11, py + 1, px + 11, py + 11, 0)
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

local function draw_cell_ball(x, y)
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
      draw_ball(cx, cy - lift, shown, lx, ly, true)
      return
    end
    -- the freshly landed ball gives a small settle bounce
    if x == a.move.to.x and y == a.move.to.y then
      local lift = abs(sin(pr * 0.5)) * 2
      ground_shadow(cx, cy, lift)
      draw_ball(cx, cy - lift, side, 0, 1, true)
      return
    end
  end

  -- the selected ball floats above its tile and eyes the cursor
  if not a and board_same_cell(selected, { x = x, y = y }) then
    local lift = 2 + abs(sin(time() * 0.75)) * 2
    local tx, ty = ball_xy(cur.x, cur.y)
    ground_shadow(cx, cy, lift)
    draw_ball(cx, cy - lift, side, look_toward(tx - cx), look_toward(ty - cy), true)
    return
  end

  local lx, ly = glance(x * 3 + y * 5 + (side == "enemy" and 7 or 0))
  draw_ball(cx, cy, side, lx, ly)
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
  draw_ball(cx, cy - hop, anim.side, look_toward(tx - cx), look_toward(ty - cy), true)
end

local function draw_board()
  for y = 1, state.height do
    for x = 1, state.width do
      local px, py = tile_xy(x, y)
      draw_tile(px, py, x, y)

      local m = not anim and target_at(x, y)
      if m then
        local c = 10
        if m.kind == "jump" then c = 12 end
        rect(px + 2, py + 2, px + 10, py + 10, c)
      end
    end
  end

  -- balls after tiles so lifted balls can overlap the row above
  for y = 1, state.height do
    for x = 1, state.width do
      if state.cells[y][x] ~= "empty" then
        draw_cell_ball(x, y)
      end
    end
  end

  if anim and anim.phase == "fly" then
    draw_flying_ball()
  end

  if not anim and not state.winner and state.current_player == "player" then
    local px, py = tile_xy(cur.x, cur.y)
    local c = 7
    if time() % 1 < 0.5 then c = 10 end
    rect(px - 1, py - 1, px + tile - 1, py + tile - 1, c)
  end
end

local function cprint(s, y, c)
  print(s, 64 - #s * 2, y, c)
end

local function outlined(s, x, y, c)
  for dx = -1, 1 do
    for dy = -1, 1 do
      print(s, x + dx, y + dy, 0)
    end
  end
  print(s, x, y - 1, 7)
  print(s, x, y, c)
end

local function draw_hud()
  local p = board_count_cells(state, "player")
  local e = board_count_cells(state, "enemy")
  print("you " .. p, 3, 5, 11)
  local et = "bot " .. e
  print(et, 125 - #et * 4, 5, 9)

  if not state.winner and not anim and state.current_player == "enemy" then
    cprint("thinking" .. sub("...", 1, flr(time() * 3) % 4), 5, 6)
  end

  if not state.winner then
    cprint("\142 pick/move  \151 drop", 116, 5)
  end
end

local function draw_game_over()
  local x0, y0, x1, y1 = 14, 44, 113, 82
  rectfill(x0 + 2, y0 + 2, x1 + 2, y1 + 2, 0)
  rectfill(x0, y0, x1, y1, 1)
  rect(x0, y0, x1, y1, 12)

  local msg, accent = "a tie!", 6
  if state.winner == "player" then
    msg, accent = "you win!", 11
  elseif state.winner == "enemy" then
    msg, accent = "bot wins", 9
  end
  cprint("game over", y0 + 5, 6)
  cprint(msg, y0 + 17, accent)
  cprint("\142 for menu", y0 + 29, 5)

  -- the winners flank the result and glance around idly
  if state.winner ~= "tie" then
    local lx, ly = glance(0)
    draw_ball(x0 + 13, y0 + 19, state.winner, lx, ly)
    local rx, ry = glance(3)
    draw_ball(x1 - 13, y0 + 19, state.winner, rx, ry)
  end
end

local function draw_title()
  -- a line of balls hopping in a wave, eyeing their neighbour
  for i = 0, 6 do
    local side = "player"
    if i % 2 == 1 then side = "enemy" end
    local cx = 22 + i * 14
    local by = 62
    local hop = abs(sin(time() * 0.6 + i / 7)) * 8
    local lx = 1
    if i % 2 == 1 then lx = -1 end
    ground_shadow(cx, by, hop)
    draw_ball(cx, by - hop, side, lx, 0, true)
  end

  outlined("sporeline", 46, 28, 11)

  local row = "bot  < " .. difficulties[diff_i] .. " >"
  cprint(row, 84, 10)
  cprint("7x7 dish", 94, 6)
  cprint("\139\145 bot  \142 start", 116, 5)
end

function _draw()
  cls(1)
  if scene == "title" then
    draw_title()
    return
  end
  draw_board()
  draw_hud()
  if state.winner and not anim then
    draw_game_over()
  end
end
