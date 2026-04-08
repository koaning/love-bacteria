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

local function draw_panel(x, y, width, height, radius)
  set_color(palette.panel)
  love.graphics.rectangle("fill", x, y, width, height, radius, radius)
  set_color(palette.panel_edge)
  love.graphics.setLineWidth(2)
  love.graphics.rectangle("line", x, y, width, height, radius, radius)
  love.graphics.setLineWidth(1)
end

local function draw_button(button, active)
  local fill = palette.cell
  local edge = palette.cell_edge

  if active then
    fill = palette.grow
    edge = palette.grow_edge
  end

  set_color(fill)
  love.graphics.rectangle("fill", button.x, button.y, button.width, button.height, 12, 12)
  set_color(edge)
  love.graphics.setLineWidth(2)
  love.graphics.rectangle("line", button.x, button.y, button.width, button.height, 12, 12)
  love.graphics.setLineWidth(1)

  love.graphics.setFont(fonts.body)
  set_color(palette.text)
  love.graphics.printf(
    button.label,
    button.x,
    button.y + math.floor((button.height - 16) * 0.5),
    button.width,
    "center"
  )
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

local function draw_progress_bar(state, layout)
  local player_count = board.count_cells(state, "player")
  local enemy_count = board.count_cells(state, "enemy")
  local total_cells = state.width * state.height
  local player_ratio = player_count / total_cells
  local enemy_ratio = enemy_count / total_cells
  local player_percent = math.floor((player_ratio * 100) + 0.5)
  local enemy_percent = math.floor((enemy_ratio * 100) + 0.5)
  local bar_x = layout.origin_x
  local bar_y = 42
  local bar_width = layout.board_width
  local bar_height = 16
  local player_width = math.floor((bar_width * player_ratio) + 0.5)
  local enemy_width = math.floor((bar_width * enemy_ratio) + 0.5)

  if player_width + enemy_width > bar_width then
    local overflow = player_width + enemy_width - bar_width
    if enemy_width >= overflow then
      enemy_width = enemy_width - overflow
    else
      player_width = player_width - (overflow - enemy_width)
      enemy_width = 0
    end
  end

  love.graphics.setFont(fonts.small)
  set_color(palette.player)
  love.graphics.print(("%d%%"):format(player_percent), bar_x, bar_y - 20)
  set_color(palette.enemy)
  love.graphics.printf(("%d%%"):format(enemy_percent), bar_x, bar_y - 20, bar_width, "right")

  set_color(palette.cell)
  love.graphics.rectangle("fill", bar_x, bar_y, bar_width, bar_height, 8, 8)
  set_color(palette.player)
  love.graphics.rectangle("fill", bar_x, bar_y, player_width, bar_height, 8, 8)
  set_color(palette.enemy)
  love.graphics.rectangle("fill", bar_x + bar_width - enemy_width, bar_y, enemy_width, bar_height, 8, 8)

  set_color(palette.panel_edge)
  love.graphics.setLineWidth(2)
  love.graphics.rectangle("line", bar_x, bar_y, bar_width, bar_height, 8, 8)
end

function Render.get_main_menu_ui(width, height)
  local panel_width = 420
  local panel_height = 336
  local panel_x = math.floor((width - panel_width) * 0.5)
  local panel_y = math.floor((height - panel_height) * 0.5)

  return {
    panel = {
      x = panel_x,
      y = panel_y,
      width = panel_width,
      height = panel_height,
    },
    buttons = {
      {
        id = "play",
        label = "Play",
        x = panel_x + 70,
        y = panel_y + 110,
        width = panel_width - 140,
        height = 50,
      },
      {
        id = "settings",
        label = "Settings",
        x = panel_x + 70,
        y = panel_y + 174,
        width = panel_width - 140,
        height = 50,
      },
      {
        id = "quit",
        label = "Quit",
        x = panel_x + 70,
        y = panel_y + 238,
        width = panel_width - 140,
        height = 50,
      },
    },
  }
end

function Render.get_play_menu_ui(width, height)
  local panel_width = 520
  local panel_height = 330
  local panel_x = math.floor((width - panel_width) * 0.5)
  local panel_y = math.floor((height - panel_height) * 0.5)
  local option_width = 120
  local option_height = 54
  local gap = 20
  local options_x = panel_x + math.floor((panel_width - ((option_width * 3) + (gap * 2))) * 0.5)
  local options_y = panel_y + 130

  return {
    panel = {
      x = panel_x,
      y = panel_y,
      width = panel_width,
      height = panel_height,
    },
    buttons = {
      {
        id = "size_5",
        label = "5x5",
        x = options_x,
        y = options_y,
        width = option_width,
        height = option_height,
      },
      {
        id = "size_7",
        label = "7x7",
        x = options_x + option_width + gap,
        y = options_y,
        width = option_width,
        height = option_height,
      },
      {
        id = "size_9",
        label = "9x9",
        x = options_x + ((option_width + gap) * 2),
        y = options_y,
        width = option_width,
        height = option_height,
      },
      {
        id = "back",
        label = "Back",
        x = panel_x + 56,
        y = panel_y + 242,
        width = 180,
        height = 50,
      },
      {
        id = "start",
        label = "Start",
        x = panel_x + panel_width - 236,
        y = panel_y + 242,
        width = 180,
        height = 50,
      },
    },
  }
end

function Render.get_settings_menu_ui(width, height)
  local panel_width = 520
  local panel_height = 330
  local panel_x = math.floor((width - panel_width) * 0.5)
  local panel_y = math.floor((height - panel_height) * 0.5)
  local option_width = 140
  local option_height = 54
  local gap = 14
  local options_x = panel_x + math.floor((panel_width - ((option_width * 3) + (gap * 2))) * 0.5)
  local options_y = panel_y + 130

  return {
    panel = {
      x = panel_x,
      y = panel_y,
      width = panel_width,
      height = panel_height,
    },
    buttons = {
      {
        id = "res_800_600",
        label = "800x600",
        x = options_x,
        y = options_y,
        width = option_width,
        height = option_height,
      },
      {
        id = "res_960_720",
        label = "960x720",
        x = options_x + option_width + gap,
        y = options_y,
        width = option_width,
        height = option_height,
      },
      {
        id = "res_1280_900",
        label = "1280x900",
        x = options_x + ((option_width + gap) * 2),
        y = options_y,
        width = option_width,
        height = option_height,
      },
      {
        id = "back",
        label = "Back",
        x = panel_x + math.floor((panel_width - 180) * 0.5),
        y = panel_y + 242,
        width = 180,
        height = 50,
      },
    },
  }
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
  love.graphics.printf(("Player %d  |  Enemy %d"):format(
    board.count_cells(state, "player"),
    board.count_cells(state, "enemy")
  ), panel_x, panel_y + 96, panel_width, "center")
end

function Render.draw_main_menu()
  local width, height = love.graphics.getDimensions()
  local ui = Render.get_main_menu_ui(width, height)

  draw_background(width, height)
  draw_panel(ui.panel.x, ui.panel.y, ui.panel.width, ui.panel.height, 20)

  love.graphics.setFont(fonts.title)
  set_color(palette.text)
  love.graphics.printf("Bacteria", ui.panel.x, ui.panel.y + 42, ui.panel.width, "center")

  for _, button in ipairs(ui.buttons) do
    draw_button(button, false)
  end
end

function Render.draw_play_menu(selected_size)
  local width, height = love.graphics.getDimensions()
  local ui = Render.get_play_menu_ui(width, height)

  draw_background(width, height)
  draw_panel(ui.panel.x, ui.panel.y, ui.panel.width, ui.panel.height, 20)

  love.graphics.setFont(fonts.title)
  set_color(palette.text)
  love.graphics.printf("Play", ui.panel.x, ui.panel.y + 32, ui.panel.width, "center")

  love.graphics.setFont(fonts.body)
  set_color(palette.text_muted)
  love.graphics.printf("Board Size", ui.panel.x, ui.panel.y + 92, ui.panel.width, "center")

  for _, button in ipairs(ui.buttons) do
    local active = false

    if button.id == "size_5" then
      active = selected_size == 5
    elseif button.id == "size_7" then
      active = selected_size == 7
    elseif button.id == "size_9" then
      active = selected_size == 9
    end

    draw_button(button, active)
  end
end

function Render.draw_settings_menu(selected_resolution_id)
  local width, height = love.graphics.getDimensions()
  local ui = Render.get_settings_menu_ui(width, height)

  draw_background(width, height)
  draw_panel(ui.panel.x, ui.panel.y, ui.panel.width, ui.panel.height, 20)

  love.graphics.setFont(fonts.title)
  set_color(palette.text)
  love.graphics.printf("Settings", ui.panel.x, ui.panel.y + 32, ui.panel.width, "center")

  love.graphics.setFont(fonts.body)
  set_color(palette.text_muted)
  love.graphics.printf("Resolution", ui.panel.x, ui.panel.y + 92, ui.panel.width, "center")

  for _, button in ipairs(ui.buttons) do
    local active = button.id == selected_resolution_id
    draw_button(button, active)
  end
end

function Render.load()
  fonts.title = love.graphics.newFont(28)
  fonts.body = love.graphics.newFont(16)
  fonts.small = love.graphics.newFont(13)
end

function Render.get_layout(width, height, state)
  local top_height = 76
  local bottom_margin = 20
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
  draw_progress_bar(state, layout)

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

  if state.winner then
    draw_overlay(state, width, height)
  end
end

return Render
