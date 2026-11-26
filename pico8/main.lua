-- main.lua
-- input, turn flow, organic 3d moss-blob renderer, and title menu.
--
-- adjacent same-side cells merge into 3-tone pillowy planes with
-- concave waists and rounded holes, competing masses press cleanly
-- across a 1px seam, and every connected blob shares one pair of eyes.

local difficulties = { "easy", "medium", "hard" }
local theme_names = { "light", "dark" }
local theme_pals = {
  light = {
    bg = 7, bg_out = 6, grid = 6,
    grow_c = 3, grow_hi = 11, jump_hi = 1,
    cur_a = 1, cur_b = 5,
    ui_txt = 1, ui_sub = 5, bar_bg = 6,
    p_txt = 3, e_txt = 4,
    logo_out = 5, plaque = true, diam_out = 1,
    dish_sh = 13, dish_rim = 5, dish_bg = 6, dish_dith = 7, dish_hi = 7,
    card_bg = 7, card_in = 6, card_hi = 7, card_lo = 13, card_sh = 13,
    lbl_on = 1, arr_on = 1, arr_off = 6,
    diff = { 3, 4, 8 }, go_tie = 5, go_sh = 6,
    spore_c = { 13, 12, 15 },
  },
  dark = {
    bg = 1, bg_out = 0, grid = 5,
    grow_c = 11, grow_hi = 7, jump_hi = 7,
    cur_a = 7, cur_b = 10,
    ui_txt = 7, ui_sub = 6, bar_bg = 0,
    p_txt = 11, e_txt = 9,
    logo_out = 0, plaque = false, diam_out = 7,
    dish_sh = 0, dish_rim = 13, dish_bg = 1, dish_dith = 0, dish_hi = 6,
    card_bg = 0, card_in = 1, card_hi = 13, card_lo = 1, card_sh = 0,
    lbl_on = 7, arr_on = 7, arr_off = 5,
    diff = { 11, 10, 9 }, go_tie = 6, go_sh = 0,
    spore_c = { 13, 3, 4 },
  },
}

local history_limit = 8
local ai_delay = 25
local fly_dur = 16
local react_dur = 22

-- 7x7 board at 14px pitch -> 98x98px centered at (15, 15).
-- blob radius 7 gives lush round curves against empty space
-- and flattens flush to +-6 against opponents (crisp 1px seam).
local tile = 14
local board_ox = 15
local board_oy = 15
local blob_r = 7

-- concave waist half-heights for dx = 0..6 from a bridge midpoint
local waist = { 5, 5, 5, 6, 6, 7, 7 }
-- quarter-circle cutout offsets for dy = 0..7 from an empty quad corner
local fillet = { 8, 8, 8, 7, 7, 6, 5, 3 }

-- flat fill, dark accent (sparks/outline), bright accent (sparks)
local looks = {
  player = { 11, 3, 7 },
  enemy = { 9, 4, 10 },
}

local dxs = { -1, 0, 1, -1, 1, -1, 0, 1 }
local dys = { -1, -1, -1, 0, 0, 1, 1, 1 }
local odirs = { -1, 0, 1, 0, 0, -1, 0, 1 }

-- crisp 1px-resolution 9px-tall pixel glyphs for the mossballs logo
local logo_glyphs = {
  m = { 9, "110000011111000111111101111110111011110010011110000011110000011110000011110000011" },
  o = { 7, "011111011111111100011110001111000111100011110001111111110111110" },
  s = { 7, "011111011111111100000111111001111110000011000001111111110111110" },
  b = { 7, "111110011111101100011111110011111101100011110001111111101111100" },
  a = { 7, "001110001111101100011110001111111111111111110001111000111100011" },
  l = { 6, "110000110000110000110000110000110000110000111111111111" },
}

local scene = "title"
-- background music on channels 0-1 (mask 3); sfx get channels 2-3.
-- title song at pattern 0, game song at 4 (see tools/music.lua)
music(0, 0, 3)
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
  return px + 7, py + 7
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
      c2 = cols[1],
      c3 = cols[2],
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
-- updates, then captured spores pop and merge.
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
        local diag = abs(x - a.move.to.x) == 1 and abs(y - a.move.to.y) == 1
        add(a.conv, { x = x, y = y, delay = diag and 4 or 0 })
        local cx, cy = ball_xy(x, y)
        spawn_sparks(cx, cy, a.side, 4)
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
  music(4, 500, 3)
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
      music(0, 500, 3)
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

-- a new look direction every ~1.25s; the seed desyncs blobs
local function glance(seed)
  local n = flr(time() * 0.8 + seed * 0.37) % 8
  return dxs[n + 1], dys[n + 1]
end

-- pupil offset toward a target: -1, 0 or 1
local function look_toward(d)
  if d > 2 then return 1 end
  if d < -2 then return -1 end
  return 0
end

local function draw_corners(x0, y0, x1, y1, s, c)
  for a = -1, 1, 2 do
    for b = -1, 1, 2 do
      local x, y = a < 0 and x0 or x1, b < 0 and y0 or y1
      line(x, y, x - a * s, y, c)
      line(x, y, x, y - b * s, c)
    end
  end
end

local function draw_panel(x0, y0, x1, y1, bg, hi, lo, sh)
  rectfill(x0 + 2, y0 + 2, x1 + 2, y1 + 2, sh or 0)
  rectfill(x0 + 1, y0, x1 - 1, y1, bg)
  rectfill(x0, y0 + 1, x1, y1 - 1, bg)
  line(x0 + 1, y0, x1 - 1, y0, hi)
  line(x0, y0 + 1, x0, y1 - 1, hi)
  line(x0 + 1, y1, x1 - 1, y1, lo)
  line(x1, y0 + 1, x1, y1 - 1, lo)
end

local function dish_shadow(cx, by, rx, h)
  local r = flr(rx - h * 0.35)
  if r >= 1 then
    ovalfill(cx - r, by, cx + r, by + (r >= 4 and 2 or 1), th().dish_sh)
  end
end

-- expressive eyes for a blob (big=true for 4+ cell colonies)
local function draw_eyes(cx, cy, lx, ly, blink, alarmed, big, body_c)
  local ex1, ex2, ey, ew, eh
  if big then
    ex1, ex2, ey, ew, eh = cx - 3 + lx, cx + 2 + lx, cy - 1 + ly, alarmed and 1 or 0, 1
  else
    ex1 = lx < 0 and (cx - 2) or (cx - 2 + lx)
    ex2 = lx > 0 and (cx + 2) or (cx + 2 + lx)
    ey, ew, eh = cy + ly, 0, 0
  end
  if alarmed then
    line(ex1, ey - 1, ex1 + ew, ey - 1, 7)
    line(ex2, ey - 1, ex2 + ew, ey - 1, 7)
    rectfill(ex1, ey, ex1 + ew, ey + eh, 0)
    rectfill(ex2, ey, ex2 + ew, ey + eh, 0)
  elseif blink then
    line(ex1, ey + eh, ex1 + (big and 1 or 0), ey + eh, body_c)
    line(ex2, ey + eh, ex2 + (big and 1 or 0), ey + eh, body_c)
  else
    line(ex1, ey, ex1, ey + eh, 0)
    line(ex2, ey, ex2, ey + eh, 0)
  end
end

-- standalone 3d-shaded orb with eyes (airborne moves, game over, title)
local function draw_solo_orb(cx, cy, side, r, lx, ly, blink, alarmed)
  local c = looks[side]
  local spec = side == "player" and 7 or 15
  circfill(cx, cy, r, c[2])
  circfill(cx - 1, cy - 1, r - 1, c[1])
  pset(cx - 3, cy - 2, spec)
  pset(cx - 2, cy - 3, spec)
  draw_eyes(cx, cy, lx, ly, blink, alarmed, false, c[2])
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
-- organic 4-way blob & gameplay rendering
-------------------------------------------------------------

-- local progress (0..1) of a converting cell's absorption wave
local function conv_progress(c)
  local span = max(1, react_dur - c.delay)
  return mid(0, (anim.t - c.delay) / span, 1)
end

local function conv_at(x, y)
  if anim and anim.phase == "react" then
    for c in all(anim.conv) do
      if c.x == x and c.y == y then
        return c
      end
    end
  end
  return nil
end

local function build_grounded()
  local g = {}
  local a = anim
  for y = 1, state.height do
    g[y] = {}
    for x = 1, state.width do
      local s = state.cells[y][x]
      if s == "empty" then
        g[y][x] = nil
      elseif a and a.phase == "fly" and a.jump
        and x == a.move.from.x and y == a.move.from.y then
        g[y][x] = nil
      elseif a and a.phase == "react" then
        local c = conv_at(x, y)
        if c and conv_progress(c) < 0.58 then
          -- stay fused inside the enemy plane until the wave overtakes it
          g[y][x] = other_side(s)
        else
          g[y][x] = s
        end
      else
        g[y][x] = s
      end
    end
  end
  return g
end

local function draw_inner_fillet(ex, ey, sx, sy, col, opp, lit)
  local tx, ty = ex + sx * tile, ey + sy * tile
  if opp then
    local gx, gy = (lit and sx < 0) and 10 or 8, (lit and sy < 0) and 10 or 8
    rectfill(ex + sx * gx, ey, tx, ty, col)
    rectfill(ex, ey + sy * gy, tx, ty, col)
    return
  end
  local o = lit and -1 or 0
  clip(min(ex, tx), min(ey, ty), tile + 1, tile + 1)
  for dy = 0, 7 do
    local py = ey + sy * dy + o
    local off = fillet[dy + 1] + (lit and 1 or 0)
    line(ex + sx * off + o, py, tx + o, py, col)
  end
  rectfill(ex + o, ey + sy * 8 + o, tx + o, ty + o, col)
  clip()
end

local function draw_side_blobs(g, side)
  local cols = looks[side]
  local foe = other_side(side)
  local w, h = state.width, state.height
  local function is(x, y, s)
    return g[y] and g[y][x] == s
  end

  local function pass(lit, col)
    local r, o, br = lit and (blob_r - 1) or blob_r, lit and -1 or 0, lit and 4 or 6

    -- 1. lobes & orthogonal bridges
    for y = 1, h do
      for x = 1, w do
        if g[y][x] == side then
          local cx, cy = ball_xy(x, y)
          local ol, or_ = is(x - 1, y, foe), is(x + 1, y, foe)
          local ou, od = is(x, y - 1, foe), is(x, y + 1, foe)
          local sr, sd = is(x + 1, y, side), is(x, y + 1, side)
          if ol or or_ or ou or od then
            local x0, y0 = cx - (ol and 6 or blob_r), cy - (ou and 6 or blob_r)
            local x1 = cx + (or_ and br or (lit and 5 or blob_r))
            local y1 = cy + (od and br or (lit and 5 or blob_r))
            clip(x0, y0, x1 - x0 + 1, y1 - y0 + 1)
            circfill(cx + o, cy + o, r, col)
            -- only square off walls where the frontline continues into an adjacent cell
            local ul, ur = is(x - 1, y - 1, foe), is(x + 1, y - 1, foe)
            local dl, dr = is(x - 1, y + 1, foe), is(x + 1, y + 1, foe)
            local su, sl = is(x, y - 1, side), is(x - 1, y, side)
            local function elo(a, b) return (a or b) and 6 or 4 end
            local function ehi(a, b) return lit and (b and 6 or (a and 4 or 2)) or elo(a, b) end
            if ol and (ou or od or (su and ul) or (sd and dl)) then
              rectfill(cx - 6, cy - elo(ou, su and ul), cx + o, cy + ehi(od, sd and dl), col)
            end
            if or_ and (ou or od or (su and ur) or (sd and dr)) then
              rectfill(cx + o, cy - elo(ou, su and ur), cx + br, cy + ehi(od, sd and dr), col)
            end
            if ou and (ol or or_ or (sl and ul) or (sr and ur)) then
              rectfill(cx - elo(ol, sl and ul), cy - 6, cx + ehi(or_, sr and ur), cy + o, col)
            end
            if od and (ol or or_ or (sl and dl) or (sr and dr)) then
              rectfill(cx - elo(ol, sl and dl), cy + o, cx + ehi(or_, sr and dr), cy + br, col)
            end
            clip()
          else
            circfill(cx + o, cy + o, r, col)
          end
          if sr then
            local mx = cx + 7
            local fu, fd = ou and is(x + 1, y - 1, foe), od and is(x + 1, y + 1, foe)
            for d = -4, 4 do
              local hh = waist[abs(d) + 1]
              line(mx + d, cy - (fu and 6 or hh),
                mx + d, cy + (fd and br or (lit and (hh - 2) or hh)), col)
            end
          end
          if sd then
            local my = cy + 7
            local fl, fr = ol and is(x - 1, y + 1, foe), or_ and is(x + 1, y + 1, foe)
            for d = -4, 4 do
              local hh = waist[abs(d) + 1]
              line(cx - (fl and 6 or hh), my + d,
                cx + (fr and br or (lit and (hh - 2) or hh)), my + d, col)
            end
          end
        end
      end
    end

    -- 2. 2x2 quads: solid fill, square-hug around opponent, or round cutout around empty
    for y = 1, h - 1 do
      for x = 1, w - 1 do
        local tl, tr = g[y][x] == side, g[y][x + 1] == side
        local bl, br_ = g[y + 1][x] == side, g[y + 1][x + 1] == side
        local cnt = (tl and 1 or 0) + (tr and 1 or 0) + (bl and 1 or 0) + (br_ and 1 or 0)
        if cnt >= 3 then
          local cx0, cy0 = ball_xy(x, y)
          if cnt == 4 then
            rectfill(cx0 + o, cy0 + o, cx0 + tile + o, cy0 + tile + o, col)
          else
            local dx, dy = (not tl or not bl) and 0 or 1, (not tl or not tr) and 0 or 1
            draw_inner_fillet(cx0 + dx * tile, cy0 + dy * tile,
              dx == 0 and 1 or -1, dy == 0 and 1 or -1, col, g[y + dy][x + dx] == foe, lit)
          end
        end
      end
    end
  end

  pass(false, cols[2])
  pass(true, cols[1])

  -- 3. glossy specular glints along sunlit top-left crowns & ridges
  local spec = side == "player" and 7 or 15
  for y = 1, h do
    for x = 1, w do
      if g[y][x] == side and not (selected and x == selected.x and y == selected.y) then
        local cx, cy = ball_xy(x, y)
        local su, sl = is(x, y - 1, side), is(x - 1, y, side)
        if not su and not sl then
          pset(cx - 4, cy - 3, spec); pset(cx - 3, cy - 4, spec)
        elseif not su then
          pset(cx - 2, cy - 4, spec); pset(cx - 1, cy - 4, spec)
        elseif not sl then
          pset(cx - 4, cy - 2, spec); pset(cx - 4, cy - 1, spec)
        end
      end
    end
  end
end

-- find 4-connected components of grounded cells and place one pair
-- of eyes on each blob's best solid anchor nearest its centroid.
local function draw_blob_eyes(g, hover_move)
  local w, h = state.width, state.height
  local vis = {}
  local sel_size = 1

  for sy = 1, h do
    for sx = 1, w do
      local side = g[sy][sx]
      local sk = sy * 8 + sx
      if side and not vis[sk] then
        -- bfs for this 4-connected blob
        local comp = {}
        local in_comp = {}
        local q = { { x = sx, y = sy } }
        vis[sk] = true
        in_comp[sk] = true
        local head = 1
        while head <= #q do
          local cell = q[head]
          head = head + 1
          add(comp, cell)
          for i = 1, 8, 2 do
            local nx, ny = cell.x + odirs[i], cell.y + odirs[i + 1]
            local nk = ny * 8 + nx
            if board_in_bounds(state, nx, ny) and not vis[nk] and g[ny][nx] == side then
              vis[nk], in_comp[nk] = true, true
              add(q, { x = nx, y = ny })
            end
          end
        end

        local n = #comp
        local sum_x, sum_y = 0, 0
        local has_sel = false
        local threatened = false

        for c in all(comp) do
          local px, py = ball_xy(c.x, c.y)
          sum_x = sum_x + px
          sum_y = sum_y + py
          if selected and c.x == selected.x and c.y == selected.y then
            has_sel = true
            sel_size = n
          end
          if side == "enemy" and hover_move
            and abs(c.x - hover_move.to.x) <= 1
            and abs(c.y - hover_move.to.y) <= 1 then
            threatened = true
          end
          if anim and anim.phase == "react" and side == other_side(anim.side)
            and conv_at(c.x, c.y) then
            threatened = true
          end
        end

        local avg_x = sum_x / n
        local avg_y = sum_y / n

        -- pick solid anchor closest to centroid (cell center or 2x2 quad center)
        local best_x, best_y = ball_xy(comp[1].x, comp[1].y)
        local best_sc = 32000
        local best_deg = -1

        local function consider(px, py, deg, pen)
          local dx, dy = px - avg_x, py - avg_y
          local sc = dx * dx + dy * dy + pen
          if sc < best_sc or (sc == best_sc and deg > best_deg) then
            best_sc, best_deg, best_x, best_y = sc, deg, px, py
          end
        end

        for c in all(comp) do
          local px, py = ball_xy(c.x, c.y)
          local k, deg = c.y * 8 + c.x, 0
          for i = 1, 8, 2 do
            if in_comp[k + odirs[i + 1] * 8 + odirs[i]] then deg = deg + 1 end
          end
          consider(px, py, deg, (n > 1 and board_same_cell(selected, c)) and 1600 or 0)
          if in_comp[k + 1] and in_comp[k + 8] and in_comp[k + 9] then
            consider(px + 7, py + 7, 5, 0)
          end
        end

        -- eye direction & expression
        local lx, ly = 0, 0
        local blink = false
        local seed = comp[1].x * 3 + comp[1].y * 5 + (side == "enemy" and 7 or 0)
        if threatened then
          local tx, ty
          if hover_move then
            tx, ty = ball_xy(hover_move.to.x, hover_move.to.y)
          else
            tx, ty = ball_xy(anim.move.to.x, anim.move.to.y)
          end
          lx, ly = look_toward(tx - best_x), look_toward(ty - best_y)
        elseif has_sel and not anim then
          local tx, ty = ball_xy(cur.x, cur.y)
          lx, ly = look_toward(tx - best_x), look_toward(ty - best_y)
        else
          lx, ly = glance(seed)
          blink = (flr(time() * 60) + seed * 41) % 240 < 5
        end

        draw_eyes(best_x, best_y, lx, ly, blink, threatened, n >= 4, looks[side][2])
      end
    end
  end

  return sel_size
end

local function draw_board_chrome()
  local c = th().grid
  draw_corners(board_ox - 2, board_oy - 2,
    board_ox + state.width * tile + 2, board_oy + state.height * tile + 2, 3, c)
  for y = 1, state.height do
    for x = 1, state.width do
      local cx, cy = ball_xy(x, y)
      pset(cx, cy, c)
    end
  end
end

local function draw_target(x, y, kind, hovered)
  local p = th()
  local cx, cy = ball_xy(x, y)
  if kind == "grow" then
    if hovered then
      circfill(cx, cy, 3, p.grow_hi)
      pset(cx, cy, p.bg)
    else
      circfill(cx, cy, 2, p.grow_c)
    end
  else
    if hovered then
      circ(cx, cy, 3, p.jump_hi)
      pset(cx, cy, p.jump_hi)
    else
      circ(cx, cy, 2, 12)
    end
  end
end

local function draw_selection_ring(sel_size)
  if not selected or anim then return end
  local cx, cy = ball_xy(selected.x, selected.y)
  local pulse = time() % 0.8 < 0.4
  if sel_size == 1 then
    circ(cx, cy, pulse and 5 or 4, 7)
  else
    circ(cx, cy, 3, 7)
    if pulse then
      pset(cx, cy, 7)
    end
  end
end

-- organic absorption wave overlaid directly on the fused blobs
local function draw_absorb_wave()
  if not anim or anim.phase ~= "react" then return end
  local cols = looks[anim.side]
  local lx, ly = ball_xy(anim.move.to.x, anim.move.to.y)

  for c in all(anim.conv) do
    local lp = conv_progress(c)
    local cx, cy = ball_xy(c.x, c.y)
    if lp > 0 and lp < 0.58 then
      local wp = lp / 0.58
      local dx = c.x - anim.move.to.x
      local dy = c.y - anim.move.to.y

      -- breach the 1px seam with a widening tendril for orthogonal neighbors
      if (dx == 0 or dy == 0) and wp > 0.15 then
        local mx = flr((lx + cx) / 2)
        local my = flr((ly + cy) / 2)
        local bw = flr(1 + wp * 4)
        if dy == 0 then
          rectfill(mx - 2, cy - bw, mx + 2, cy + bw, cols[1])
        else
          rectfill(cx - bw, my - 2, cx + bw, my + 2, cols[1])
        end
      end

      -- swell the capturer's color smoothly inside the enemy cell's bounds
      local r = flr(1 + wp * 5.5)
      local ox = cx - dx * flr((1 - wp) * 3)
      local oy = cy - dy * flr((1 - wp) * 3)
      clip(cx - 6, cy - 6, 13, 13)
      circfill(ox, oy, r, cols[1])
      if r >= 2 then
        circ(ox, oy, r, cols[3])
      end
      clip()
    elseif lp >= 0.58 and lp < 0.88 then
      -- crisp fusion shimmer as the absorbed cell settles into our plane
      local sp = (lp - 0.58) / 0.3
      local sr = flr((1 - sp) * 4)
      if sr >= 1 then
        circ(cx, cy, sr, cols[3])
      end
    end
  end
end

-- fly animation: stretch=true draws orthogonal grow pseudopod (under eyes);
-- stretch=false draws jumping / diagonal hopping 3d orb (above eyes).
local function draw_fly(stretch)
  if not anim or anim.phase ~= "fly" then return end
  local m = anim.move
  local ortho = not anim.jump and (m.from.x == m.to.x or m.from.y == m.to.y)
  if ortho ~= stretch then return end
  local fx, fy = ball_xy(m.from.x, m.from.y)
  local tx, ty = ball_xy(m.to.x, m.to.y)
  local pr = anim.t / fly_dur
  local cx, cy = fx + (tx - fx) * pr, fy + (ty - fy) * pr
  if stretch then
    local c = looks[anim.side]
    local r, bw = flr(4 + pr * 2), flr(3 + pr * 2)
    for k = 0, 1 do
      local col, o = k == 0 and c[2] or c[1], -k
      circfill(cx + o, cy + o, r + o, col)
      if m.from.y == m.to.y then
        rectfill(min(fx, cx) + o, cy - bw + o, max(fx, cx) + o, cy + bw + o * 2, col)
      else
        rectfill(cx - bw + o, min(fy, cy) + o, cx + bw + o * 2, max(fy, cy) + o, col)
      end
    end
  else
    local hop = abs(sin(pr * 0.5)) * (anim.jump and 9 or 5)
    draw_solo_orb(cx, cy - hop, anim.side, blob_r - 1,
      look_toward(tx - cx), look_toward(ty - cy), false, false)
  end
end

local function draw_cursor(px, py)
  local p = th()
  local c = time() % 0.9 < 0.45 and p.cur_a or p.cur_b
  draw_corners(px, py, px + tile, py + tile, 3, c)
end

local function draw_board()
  draw_board_chrome()

  local hover_move = (not anim and selected) and target_at(cur.x, cur.y) or nil
  local g = build_grounded()

  draw_side_blobs(g, "player")
  draw_side_blobs(g, "enemy")
  draw_fly(true)
  draw_absorb_wave()

  if not anim then
    for m in all(targets) do
      local hovered = cur.x == m.to.x and cur.y == m.to.y
      draw_target(m.to.x, m.to.y, m.kind, hovered)
    end
  end

  local sel_size = draw_blob_eyes(g, hover_move)
  draw_selection_ring(sel_size)
  draw_fly(false)
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

  -- player count + flat dot
  circfill(9, 7, 3, looks.player[1])
  print(tostr(p), 15, 5, pal.ui_txt)

  -- bot count + flat dot
  local et = tostr(e)
  print(et, 113 - text_w(et), 5, pal.ui_txt)
  circfill(118, 7, 3, looks.enemy[1])

  -- clean flat territory bar
  local bx0, bx1, by0, by1 = 29, 98, 6, 8
  rectfill(bx0, by0, bx1, by1, pal.bar_bg)
  local inner_w = bx1 - bx0 + 1
  if p > 0 then
    local pw = max(2, flr(p * inner_w / total + 0.5))
    rectfill(bx0, by0, bx0 + pw - 1, by1, looks.player[1])
  end
  if e > 0 then
    local ew = max(2, flr(e * inner_w / total + 0.5))
    rectfill(bx1 - ew + 1, by0, bx1, by1, looks.enemy[1])
  end
  pset(64, by0 - 1, pal.ui_sub)

  -- quiet bottom controls strip
  if not state.winner then
    if not anim and state.current_player == "enemy" then
      local dots = sub("...", 1, flr(time() * 3) % 4)
      print("bot thinking" .. dots, flr((128 - text_w("bot thinking...")) / 2), 119, pal.e_txt)
    elseif selected then
      cprint("\142 move   \151 cancel", 119, pal.ui_sub)
    else
      cprint("\142 pick spore", 119, pal.ui_sub)
    end
  end
end

local function draw_game_over()
  local pal = th()
  local x0, y0, x1, y1 = 12, 38, 115, 88
  draw_panel(x0, y0, x1, y1, pal.card_bg, pal.card_hi, pal.card_lo, pal.card_sh)
  rect(x0 + 2, y0 + 2, x1 - 2, y1 - 2, pal.card_in)

  local msg, accent = "a tie!", pal.go_tie
  if state.winner == "player" then
    msg, accent = "you win!", pal.p_txt
  elseif state.winner == "enemy" then
    msg, accent = "bot wins", pal.e_txt
  end

  cprint("game over", y0 + 6, pal.ui_sub)
  local mx = flr((128 - text_w(msg)) / 2)
  print(msg, mx + 1, y0 + 18, pal.go_sh)
  print(msg, mx, y0 + 17, accent)

  local p = board_count_cells(state, "player")
  local e = board_count_cells(state, "enemy")
  cprint("you " .. p .. " - " .. e .. " bot", y0 + 27, pal.ui_txt)

  line(x0 + 10, y0 + 35, x1 - 10, y0 + 35, pal.card_in)
  cprint("\142 play again", y0 + 39, pal.ui_sub)

  if state.winner ~= "tie" then
    local hop = abs(sin(time() * 1.2)) * 3
    local lx, ly = glance(0)
    dish_shadow(x0 + 14, y0 + 26, 4, hop)
    draw_solo_orb(x0 + 14, y0 + 22 - hop, state.winner, 5, lx, ly, false, false)
    local rx, ry = glance(3)
    dish_shadow(x1 - 14, y0 + 26, 4, hop)
    draw_solo_orb(x1 - 14, y0 + 22 - hop, state.winner, 5, rx, ry, false, false)
  end
end

-------------------------------------------------------------
-- title screen
-------------------------------------------------------------

local function draw_title_backdrop()
  local p = th()
  cls(p.bg_out)
  -- soft dithered petri-dish radial spotlight
  fillp(0x5f5f + 0.5)
  circfill(64, 62, 74, p.bg)
  fillp(0x5a5a + 0.5)
  circfill(64, 62, 60, p.bg)
  fillp()
  circfill(64, 62, 46, p.bg)

  -- subtle drifting background micro-spores around the margins
  local tm = time()
  for i = 1, 10 do
    local x = (i % 2 == 1 and 6 or 116) + (i * 5) % 7
    local y = 16 + i * 9
    local spd = 0.11 + (i % 4) * 0.025
    pset(x + sin(tm * spd + i * 0.17) * 2,
      y + cos(tm * spd * 0.8 + i * 0.23) * 2,
      p.spore_c[i % 3 + 1])
  end
end

local function draw_logo(word, ox, oy, pal)
  -- crisp 1px-resolution 9px-tall pixel wordmark with 3d drop shadow
  local function render(dx, dy, flat_col)
    local cx = ox
    for k = 1, #word do
      local g = logo_glyphs[sub(word, k, k)]
      local w, bits = g[1], g[2]
      for r = 0, 8 do
        for c = 0, w - 1 do
          if sub(bits, r * w + c + 1, r * w + c + 1) == "1" then
            local col = flat_col
            if not col then
              if pal.plaque and r == 0 then
                col = 7
              elseif r < 5 then
                col = 11
              elseif r < 8 then
                col = (c + r) % 2 == 0 and 11 or 3
              else
                col = 3
              end
            end
            pset(cx + c + dx, oy + r + dy, col)
          end
        end
      end
      cx = cx + w + 3
    end
  end

  render(1, 2, pal.logo_out)
  render(1, 1, pal.logo_out)
  render(0, 1, pal.logo_out)
  render(0, 0, nil)
end

local function draw_setting_row(y, label, val, val_col, active, x0, x1, pal)
  local ax0, ax1 = x0 + 36, x1 - 9
  local nudge = (active and sin(time() * 2) > 0.3) and 1 or 0
  if active then
    line(x0 + 4, y + 1, x0 + 4, y + 3, val_col)
    pset(x0 + 5, y + 2, val_col)
  end
  print(label, x0 + 8, y, active and pal.lbl_on or 13)
  local ac = active and pal.arr_on or pal.arr_off
  print("<", ax0 - nudge, y, ac)
  print(val, flr((ax0 + 3 + ax1 - text_w(val)) / 2), y, val_col)
  print(">", ax1 + nudge, y, ac)
end

-- 3d-shaded merged 2-lobe blob & solo orb for the petri-dish title stage
local function draw_title_peanut(cx, cy, side, lx, ly, blink)
  local c = looks[side]
  local spec = side == "player" and 7 or 15
  local function shape(ox, oy, r, col)
    circfill(cx - 6 + ox, cy + oy, r, col)
    circfill(cx + 6 + ox, cy + oy, r, col)
    for d = -5, 5 do
      local hh = max(2, waist[abs(d) + 1] - (7 - r))
      line(cx + ox + d, cy + oy - hh, cx + ox + d, cy + oy + hh, col)
    end
  end
  shape(0, 0, 5, c[2])
  shape(-1, -1, 4, c[1])
  pset(cx - 8, cy - 2, spec)
  pset(cx - 7, cy - 3, spec)
  pset(cx + 4, cy - 2, spec)
  pset(cx + 5, cy - 3, spec)
  draw_eyes(cx, cy, lx, ly, blink, false, false, c[2])
end

local function draw_title()
  local pal = th()
  draw_title_backdrop()

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

  -- two-tone rivalry underline + diamond centerpiece
  line(20, 34, 60, 34, 3)
  line(20, 33, 60, 33, 11)
  line(67, 34, 107, 34, 4)
  line(67, 33, 107, 33, 9)
  circfill(64, 33, 1, pal.diam_out)
  pset(64, 33, 10)

  -- shallow 3d glass petri-dish stage
  ovalfill(10, 58, 118, 72, pal.dish_sh)
  ovalfill(10, 56, 118, 70, pal.dish_rim)
  ovalfill(11, 57, 117, 69, pal.dish_bg)
  fillp(0x5a5a + 0.5)
  ovalfill(13, 58, 115, 68, pal.dish_dith)
  fillp()
  line(28, 57, 48, 57, pal.dish_hi)

  -- organic blobs hopping in a wave on the dish with ground shadows
  local tm = time()
  local h1 = abs(sin(tm * 0.6)) * 6
  local h2 = abs(sin(tm * 0.6 + 0.33)) * 8
  local h3 = abs(sin(tm * 0.6 + 0.66)) * 6
  local b1 = (flr(tm * 60) + 23) % 210 < 5
  local b2 = (flr(tm * 60) + 117) % 210 < 5

  dish_shadow(31, 63, 9, h1)
  draw_title_peanut(31, 57 - h1, "player", 1, 0, b1)

  dish_shadow(64, 63, 5, h2)
  draw_solo_orb(64, 57 - h2, sin(tm * 0.3) >= 0 and "player" or "enemy", 5,
    sin(tm * 0.6) >= 0 and 1 or -1, 0, false, false)

  dish_shadow(97, 63, 9, h3)
  draw_title_peanut(97, 57 - h3, "enemy", -1, 0, b2)

  -- framed 2-row settings card with bevel + drop shadow
  local x0, y0, x1, y1 = 18, 79, 109, 106
  draw_panel(x0, y0, x1, y1, pal.card_bg, pal.card_hi, pal.card_lo, pal.card_sh)
  rect(x0 + 1, y0 + 1, x1 - 1, y1 - 1, pal.card_in)

  draw_setting_row(y0 + 5, "bot", difficulties[diff_i], pal.diff[diff_i], menu_row == 1, x0, x1, pal)
  line(x0 + 6, y0 + 13, x1 - 6, y0 + 13, pal.card_in)
  draw_setting_row(y0 + 17, "theme", theme_names[theme_i], 12, menu_row == 2, x0, x1, pal)

  cprint("\139\145 set   \142 play", 116, pal.ui_sub)
end

function _draw()
  if scene == "title" then
    draw_title()
    return
  end
  cls(th().bg)
  draw_board()
  draw_hud()
  if state.winner and not anim then
    draw_game_over()
  end
end
