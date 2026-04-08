local board = require("src.board")
local rules = require("src.rules")

local Render = {}

local fonts = {}

local palette = {
  background_top = { 0.07, 0.09, 0.13, 1.0 },
  background_bottom = { 0.02, 0.03, 0.05, 1.0 },
  panel = { 0.09, 0.12, 0.17, 0.95 },
  panel_edge = { 0.24, 0.30, 0.38, 0.90 },
  board_shadow = { 0.00, 0.00, 0.00, 0.20 },
  cell = { 0.13, 0.16, 0.21, 1.0 },
  cell_edge = { 0.20, 0.24, 0.31, 1.0 },
  player = { 0.35, 0.86, 0.84, 1.0 },
  enemy = { 0.98, 0.47, 0.31, 1.0 },
  player_core = { 0.81, 0.98, 0.95, 1.0 },
  enemy_core = { 1.00, 0.88, 0.76, 1.0 },
  selected = { 0.97, 0.84, 0.34, 1.0 },
  grow = { 0.43, 0.87, 0.55, 0.35 },
  grow_edge = { 0.57, 0.97, 0.68, 0.95 },
  jump = { 0.43, 0.63, 0.99, 0.34 },
  jump_edge = { 0.62, 0.76, 1.00, 0.95 },
  text = { 0.93, 0.95, 0.98, 1.0 },
  text_muted = { 0.68, 0.73, 0.81, 1.0 },
  overlay = { 0.01, 0.02, 0.03, 0.70 },
}

local function set_color(color)
  love.graphics.setColor(color[1], color[2], color[3], color[4] or 1.0)
end

local function cell_key(x, y)
  return y .. ":" .. x
end

local function draw_background(width, height)
  local steps = 18

  for index = 0, steps - 1 do
    local t = index / (steps - 1)
    local r = palette.background_top[1] * (1 - t) + palette.background_bottom[1] * t
    local g = palette.background_top[2] * (1 - t) + palette.background_bottom[2] * t
    local b = palette.background_top[3] * (1 - t) + palette.background_bottom[3] * t
    local h = math.ceil(height / steps)

    love.graphics.setColor(r, g, b, 1.0)
    love.graphics.rectangle("fill", 0, index * h, width, h + 1)
  end

  love.graphics.setColor(1, 1, 1, 0.03)
  for x = -height, width, 32 do
    love.graphics.line(x, 0, x + height, height)
  end
end

local function build_move_lookup(state)
  local lookup = {}

  if state.winner or state.current_player ~= "player" or not state.selected_cell then
    return lookup
  end

  if board.get_cell(state, state.selected_cell.x, state.selected_cell.y) ~= "player" then
    return lookup
  end

  local moves = rules.get_piece_moves(
    state,
    "player",
    state.selected_cell.x,
    state.selected_cell.y
  )

  for _, move in ipairs(moves) do
    lookup[cell_key(move.to.x, move.to.y)] = move.kind
  end

  return lookup
end

local function cell_rect(layout, x, y)
  local px = layout.origin_x + (x - 1) * layout.cell_size
  local py = layout.origin_y + (y - 1) * layout.cell_size

  return px, py, layout.cell_size, layout.cell_size
end

local function draw_piece(px, py, size, side)
  local base = palette.player
  local core = palette.player_core

  if side == "enemy" then
    base = palette.enemy
    core = palette.enemy_core
  end

  local cx = px + size * 0.5
  local cy = py + size * 0.5
  local radius = size * 0.32

  love.graphics.setColor(0, 0, 0, 0.18)
  love.graphics.circle("fill", cx + 2, cy + 4, radius)

  set_color(base)
  love.graphics.circle("fill", cx, cy, radius)

  set_color(core)
  love.graphics.circle("fill", cx - radius * 0.22, cy - radius * 0.22, radius * 0.44)
end

local function draw_header(state, width)
  local player_count = board.count_cells(state, "player")
  local enemy_count = board.count_cells(state, "enemy")
  local turn_text = "Turn: Player"

  if state.current_player == "enemy" and not state.winner then
    turn_text = "Turn: Enemy"
  end

  if state.winner == "player" then
    turn_text = "Player Wins"
  elseif state.winner == "enemy" then
    turn_text = "Enemy Wins"
  elseif state.winner == "tie" then
    turn_text = "Tie Game"
  end

  love.graphics.setFont(fonts.title)
  set_color(palette.text)
  love.graphics.print("Bacteria Prototype", 48, 32)

  love.graphics.setFont(fonts.body)
  set_color(palette.text)
  love.graphics.print(turn_text, 48, 70)
  love.graphics.print(("Player %d  |  Enemy %d"):format(player_count, enemy_count), 220, 70)

  love.graphics.setFont(fonts.small)
  set_color(palette.text_muted)
  love.graphics.printf(
    "Click one of your bacteria, then click a highlighted cell. Green grows, blue jumps. R restarts. Esc quits.",
    48,
    97,
    width - 96,
    "left"
  )

  if state.status_text then
    set_color(palette.text_muted)
    love.graphics.printf(state.status_text, 48, 118, width - 96, "left")
  end
end

local function draw_legend(width, height)
  local y = height - 42
  local x = 48

  love.graphics.setFont(fonts.small)

  set_color(palette.grow)
  love.graphics.circle("fill", x, y + 9, 9)
  set_color(palette.grow_edge)
  love.graphics.circle("line", x, y + 9, 9)
  set_color(palette.text_muted)
  love.graphics.print("Grow", x + 18, y)

  x = x + 88
  set_color(palette.jump)
  love.graphics.circle("fill", x, y + 9, 9)
  set_color(palette.jump_edge)
  love.graphics.circle("line", x, y + 9, 9)
  set_color(palette.text_muted)
  love.graphics.print("Jump", x + 18, y)

  x = x + 88
  set_color(palette.selected)
  love.graphics.circle("line", x, y + 9, 9)
  set_color(palette.text_muted)
  love.graphics.print("Selected", x + 18, y)
end

local function draw_overlay(state, width, height)
  local title = "Tie"

  if state.winner == "player" then
    title = "Player Wins"
  elseif state.winner == "enemy" then
    title = "Enemy Wins"
  end

  love.graphics.setColor(
    palette.overlay[1],
    palette.overlay[2],
    palette.overlay[3],
    palette.overlay[4]
  )
  love.graphics.rectangle("fill", 0, 0, width, height)

  local panel_width = 420
  local panel_height = 180
  local panel_x = (width - panel_width) * 0.5
  local panel_y = (height - panel_height) * 0.5

  set_color(palette.panel)
  love.graphics.rectangle("fill", panel_x, panel_y, panel_width, panel_height, 18, 18)
  set_color(palette.panel_edge)
  love.graphics.setLineWidth(2)
  love.graphics.rectangle("line", panel_x, panel_y, panel_width, panel_height, 18, 18)

  love.graphics.setFont(fonts.title)
  set_color(palette.text)
  love.graphics.printf(title, panel_x, panel_y + 32, panel_width, "center")

  love.graphics.setFont(fonts.body)
  set_color(palette.text_muted)
  love.graphics.printf(state.status_text or "", panel_x + 24, panel_y + 84, panel_width - 48, "center")
  love.graphics.printf("Press R to restart.", panel_x, panel_y + 130, panel_width, "center")
end

function Render.load()
  fonts.title = love.graphics.newFont(28)
  fonts.body = love.graphics.newFont(16)
  fonts.small = love.graphics.newFont(13)
end

function Render.get_layout(width, height, state)
  local top_height = 162
  local bottom_margin = 72
  local max_board_width = width - 120
  local max_board_height = height - top_height - bottom_margin
  local cell_size = math.floor(math.min(max_board_width / state.width, max_board_height / state.height))

  if cell_size < 56 then
    cell_size = 56
  end

  local board_width = cell_size * state.width
  local board_height = cell_size * state.height
  local origin_x = math.floor((width - board_width) * 0.5)
  local origin_y = top_height + math.floor((max_board_height - board_height) * 0.5)

  return {
    columns = state.width,
    rows = state.height,
    cell_size = cell_size,
    board_width = board_width,
    board_height = board_height,
    origin_x = origin_x,
    origin_y = origin_y,
  }
end

function Render.draw(state)
  local width, height = love.graphics.getDimensions()
  local layout = Render.get_layout(width, height, state)
  local move_lookup = build_move_lookup(state)

  draw_background(width, height)
  draw_header(state, width)

  love.graphics.setColor(
    palette.board_shadow[1],
    palette.board_shadow[2],
    palette.board_shadow[3],
    palette.board_shadow[4]
  )
  love.graphics.rectangle(
    "fill",
    layout.origin_x + 10,
    layout.origin_y + 14,
    layout.board_width,
    layout.board_height,
    24,
    24
  )

  set_color(palette.panel)
  love.graphics.rectangle(
    "fill",
    layout.origin_x - 18,
    layout.origin_y - 18,
    layout.board_width + 36,
    layout.board_height + 36,
    28,
    28
  )
  set_color(palette.panel_edge)
  love.graphics.setLineWidth(2)
  love.graphics.rectangle(
    "line",
    layout.origin_x - 18,
    layout.origin_y - 18,
    layout.board_width + 36,
    layout.board_height + 36,
    28,
    28
  )

  for y = 1, state.height do
    for x = 1, state.width do
      local px, py, size = cell_rect(layout, x, y)
      local occupant = board.get_cell(state, x, y)
      local move_kind = move_lookup[cell_key(x, y)]
      local is_selected = state.selected_cell and board.same_cell(state.selected_cell, { x = x, y = y })
      local is_last_move = state.last_move and board.same_cell(state.last_move.to, { x = x, y = y })

      set_color(palette.cell)
      love.graphics.rectangle("fill", px + 3, py + 3, size - 6, size - 6, 16, 16)
      set_color(palette.cell_edge)
      love.graphics.setLineWidth(1)
      love.graphics.rectangle("line", px + 3, py + 3, size - 6, size - 6, 16, 16)

      if move_kind == "grow" then
        set_color(palette.grow)
        love.graphics.rectangle("fill", px + 8, py + 8, size - 16, size - 16, 14, 14)
        set_color(palette.grow_edge)
        love.graphics.rectangle("line", px + 8, py + 8, size - 16, size - 16, 14, 14)
      elseif move_kind == "jump" then
        set_color(palette.jump)
        love.graphics.rectangle("fill", px + 8, py + 8, size - 16, size - 16, 14, 14)
        set_color(palette.jump_edge)
        love.graphics.rectangle("line", px + 8, py + 8, size - 16, size - 16, 14, 14)
      end

      if is_selected then
        set_color(palette.selected)
        love.graphics.setLineWidth(3)
        love.graphics.rectangle("line", px + 5, py + 5, size - 10, size - 10, 16, 16)
      elseif is_last_move then
        set_color(palette.text_muted)
        love.graphics.setLineWidth(2)
        love.graphics.rectangle("line", px + 7, py + 7, size - 14, size - 14, 16, 16)
      end

      if occupant ~= "empty" then
        draw_piece(px, py, size, occupant)
      end
    end
  end

  draw_legend(width, height)

  if state.winner then
    draw_overlay(state, width, height)
  end
end

return Render
