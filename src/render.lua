local board = require("src.board")
local rules = require("src.rules")

local Render = {}

local fonts = {}
local font_files = {
  title = "assets/fonts/BebasNeue-Regular.ttf",
  body = "assets/fonts/AtkinsonHyperlegible-Regular.ttf",
}
local font_base_sizes = {
  title = 52,
  section = 19,
  button = 18,
  body = 16,
  hud = 14,
  small = 13,
}
local current_type_scale = nil

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
  audio_on = { 0.13, 0.28, 0.24, 0.92 },
  audio_off = { 0.31, 0.16, 0.13, 0.92 },
  overlay = { 0.01, 0.02, 0.03, 0.70 },
}

local function set_color(color, alpha_multiplier)
  local alpha = color[4] or 1.0
  local multiplier = alpha_multiplier or 1.0
  love.graphics.setColor(color[1], color[2], color[3], alpha * multiplier)
end

local function clamp(value, minimum, maximum)
  if value < minimum then
    return minimum
  end

  if value > maximum then
    return maximum
  end

  return value
end

local function tint(color, delta)
  return {
    clamp(color[1] + delta, 0, 1),
    clamp(color[2] + delta, 0, 1),
    clamp(color[3] + delta, 0, 1),
    color[4] or 1.0,
  }
end

local function cell_key(x, y)
  return y .. ":" .. x
end

local function point_in_rect(x, y, rect)
  return x >= rect.x
    and x <= rect.x + rect.width
    and y >= rect.y
    and y <= rect.y + rect.height
end

local function get_hovered_button_id(buttons)
  if not love or not love.mouse or not love.mouse.getPosition then
    return nil
  end

  local x, y = love.mouse.getPosition()

  for _, button in ipairs(buttons) do
    if point_in_rect(x, y, button) then
      return button.id
    end
  end

  return nil
end

local function load_font(path, size)
  if love and love.filesystem and love.filesystem.getInfo(path) then
    return love.graphics.newFont(path, size)
  end

  return love.graphics.newFont(size)
end

local function refresh_fonts_for_size(width, height)
  local min_dimension = math.min(width, height)
  local target_scale = clamp(min_dimension / 760, 0.90, 1.20)

  if current_type_scale and math.abs(target_scale - current_type_scale) < 0.03 then
    return
  end

  current_type_scale = target_scale

  fonts.title = load_font(font_files.title, math.floor((font_base_sizes.title * target_scale) + 0.5))
  fonts.section = load_font(font_files.body, math.floor((font_base_sizes.section * target_scale) + 0.5))
  fonts.button = load_font(font_files.body, math.floor((font_base_sizes.button * target_scale) + 0.5))
  fonts.body = load_font(font_files.body, math.floor((font_base_sizes.body * target_scale) + 0.5))
  fonts.hud = load_font(font_files.body, math.floor((font_base_sizes.hud * target_scale) + 0.5))
  fonts.small = load_font(font_files.body, math.floor((font_base_sizes.small * target_scale) + 0.5))
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
end

local function draw_panel(x, y, width, height, radius, alpha_multiplier)
  set_color(palette.panel, alpha_multiplier)
  love.graphics.rectangle("fill", x, y, width, height, radius, radius)
  set_color(palette.panel_edge, alpha_multiplier)
  love.graphics.setLineWidth(2)
  love.graphics.rectangle("line", x, y, width, height, radius, radius)
  love.graphics.setLineWidth(1)
end

local function draw_button(button, active, focused, hovered, pulse_time, y_offset, alpha_multiplier)
  local offset_y = y_offset or 0
  local pulse = (math.sin((pulse_time or 0) * 5.5) + 1) * 0.5
  local fill = palette.cell
  local edge = palette.cell_edge

  if active then
    fill = palette.grow
    edge = palette.grow_edge
  end

  local emphasize = 0
  if focused or hovered then
    emphasize = 0.03 + (pulse * 0.06)
  end

  local scale = 1 + (emphasize * 0.28)
  local draw_width = button.width * scale
  local draw_height = button.height * scale
  local draw_x = button.x + ((button.width - draw_width) * 0.5)
  local draw_y = button.y + offset_y + ((button.height - draw_height) * 0.5)

  set_color(tint(fill, emphasize), alpha_multiplier)
  love.graphics.rectangle("fill", draw_x, draw_y, draw_width, draw_height, 12, 12)
  set_color(tint(edge, emphasize * 0.5), alpha_multiplier)
  love.graphics.setLineWidth(focused and 3 or 2)
  love.graphics.rectangle("line", draw_x, draw_y, draw_width, draw_height, 12, 12)
  if focused then
    set_color(palette.selected, alpha_multiplier)
    love.graphics.rectangle("line", draw_x + 4, draw_y + 4, draw_width - 8, draw_height - 8, 10, 10)
  end
  love.graphics.setLineWidth(1)

  love.graphics.setFont(fonts.button)
  set_color(palette.text, alpha_multiplier)
  love.graphics.printf(
    button.label,
    draw_x,
    draw_y + math.floor((draw_height - fonts.button:getHeight()) * 0.5),
    draw_width,
    "center"
  )
end

local function draw_audio_status_badge(width, height, audio_status, alpha_multiplier, y_position)
  if not audio_status then
    return
  end

  local text = audio_status.text or "Audio"
  local hint = audio_status.hint or "M"
  local label = ("%s [%s]"):format(text, hint)
  local muted = audio_status.muted == true
  local y = y_position or 14

  love.graphics.setFont(fonts.small)

  local text_width = fonts.small:getWidth(label)
  local text_height = fonts.small:getHeight()
  local box_width = text_width + 26
  local box_height = text_height + 12
  local x = width - box_width - 18

  if y + box_height > height - 8 then
    y = math.max(8, height - box_height - 8)
  end

  if muted then
    set_color(palette.audio_off, alpha_multiplier)
  else
    set_color(palette.audio_on, alpha_multiplier)
  end
  love.graphics.rectangle("fill", x, y, box_width, box_height, 10, 10)

  if muted then
    set_color(palette.enemy, alpha_multiplier)
  else
    set_color(palette.grow_edge, alpha_multiplier)
  end
  love.graphics.setLineWidth(2)
  love.graphics.rectangle("line", x, y, box_width, box_height, 10, 10)
  love.graphics.setLineWidth(1)

  set_color(palette.text, alpha_multiplier)
  love.graphics.print(label, x + 13, y + math.floor((box_height - text_height) * 0.5))
end

local function build_move_lookup(state, preview_cell)
  local lookup = {}
  local source_cell = nil

  if state.winner or state.current_player ~= "player" then
    return lookup, source_cell
  end

  if state.selected_cell then
    source_cell = state.selected_cell
  elseif preview_cell then
    source_cell = preview_cell
  else
    return lookup, source_cell
  end

  if board.get_cell(state, source_cell.x, source_cell.y) ~= "player" then
    return lookup, nil
  end

  local moves = rules.get_piece_moves(
    state,
    "player",
    source_cell.x,
    source_cell.y
  )

  for _, move in ipairs(moves) do
    lookup[cell_key(move.to.x, move.to.y)] = move.kind
  end

  return lookup, source_cell
end

local function cell_rect(layout, x, y)
  local px = layout.origin_x + (x - 1) * layout.cell_size
  local py = layout.origin_y + (y - 1) * layout.cell_size

  return px, py, layout.cell_size, layout.cell_size
end

local function cell_center(layout, x, y)
  local px, py, size = cell_rect(layout, x, y)
  return px + (size * 0.5), py + (size * 0.5), size
end

local function smoothstep(t)
  local value = clamp(t, 0, 1)
  return value * value * (3 - (2 * value))
end

local function draw_piece(px, py, size, side, animation, alpha_multiplier, lift_amount)
  local base = palette.player
  local core = palette.player_core
  local lift = clamp(lift_amount or 0, 0, 1)

  if side == "enemy" then
    base = palette.enemy
    core = palette.enemy_core
  end

  local scale = 1.0
  local alpha = 1.0
  local animation_progress = 1.0

  if animation then
    animation_progress = clamp(animation.progress or 0, 0, 1)

    if animation.kind == "spawn" then
      scale = 0.84 + (animation_progress * 0.16)
      alpha = 0.45 + (animation_progress * 0.55)
    elseif animation.kind == "convert" then
      local pulse = math.sin(animation_progress * math.pi)
      scale = 1.0 + (pulse * 0.10)
    end
  end

  scale = scale * (1 + (lift * 0.12))
  alpha = alpha * (alpha_multiplier or 1.0)

  local cx = px + size * 0.5
  local cy = (py + size * 0.5) - (size * 0.16 * lift)
  local radius = size * 0.32 * scale

  if animation and animation.kind == "convert" and animation_progress < 1 then
    love.graphics.setColor(base[1], base[2], base[3], ((1 - animation_progress) * 0.22) * alpha)
    love.graphics.circle("fill", cx, cy, (size * 0.34) + (size * 0.20 * animation_progress))
  end

  local shadow_radius = radius * (1 + (lift * 0.12))
  local shadow_alpha = (0.18 * alpha) * (1 - (lift * 0.50))
  love.graphics.setColor(0, 0, 0, shadow_alpha)
  love.graphics.circle("fill", cx + 2, cy + 4 + (size * 0.07 * lift), shadow_radius)

  set_color(base, alpha)
  love.graphics.circle("fill", cx, cy, radius)

  set_color(core, alpha)
  love.graphics.circle("fill", cx - radius * 0.22, cy - radius * 0.22, radius * 0.44)
end

local function draw_blob(cx, cy, radius, side, alpha_multiplier, scale)
  local base = palette.player
  local core = palette.player_core
  local factor = scale or 1

  if side == "enemy" then
    base = palette.enemy
    core = palette.enemy_core
  end

  local r = radius * factor

  love.graphics.setColor(0, 0, 0, 0.18 * alpha_multiplier)
  love.graphics.circle("fill", cx + 2, cy + 4, r * 1.02)

  set_color(base, alpha_multiplier)
  love.graphics.circle("fill", cx, cy, r)

  set_color(core, alpha_multiplier)
  love.graphics.circle("fill", cx - (r * 0.20), cy - (r * 0.20), r * 0.42)
end

local function draw_blob_scaled(cx, cy, radius, side, alpha_multiplier, scale_x, scale_y)
  local base = palette.player
  local core = palette.player_core
  local sx = scale_x or 1
  local sy = scale_y or 1

  if side == "enemy" then
    base = palette.enemy
    core = palette.enemy_core
  end

  love.graphics.push()
  love.graphics.translate(cx, cy)
  love.graphics.scale(sx, sy)

  love.graphics.setColor(0, 0, 0, 0.16 * alpha_multiplier)
  love.graphics.circle("fill", 2, 4, radius * 1.02)

  set_color(base, alpha_multiplier)
  love.graphics.circle("fill", 0, 0, radius)

  set_color(core, alpha_multiplier)
  love.graphics.circle("fill", -(radius * 0.20), -(radius * 0.20), radius * 0.42)
  love.graphics.pop()
end

local function normalize(dx, dy)
  local length = math.sqrt((dx * dx) + (dy * dy))

  if length <= 0.0001 then
    return 0, 0, 0
  end

  return dx / length, dy / length, length
end

local function draw_capture_sparks(cx, cy, side, alpha_multiplier, energy, progress, cell_size)
  local count = 5 + math.floor(energy * 7)
  local radius = cell_size * (0.28 + (0.90 * progress))
  local core_color = palette.player_core

  if side == "enemy" then
    core_color = palette.enemy_core
  end

  love.graphics.setLineWidth(1.2 + (energy * 1.6))
  for index = 1, count do
    local step = index / count
    local angle = (step * math.pi * 2) + (progress * 6.8) + (index * 0.31)
    local inner_radius = radius * (0.48 + (0.10 * math.sin(progress * math.pi)))
    local outer_radius = radius * (0.94 + (0.15 * energy))
    local x1 = cx + (math.cos(angle) * inner_radius)
    local y1 = cy + (math.sin(angle) * inner_radius * 0.86)
    local x2 = cx + (math.cos(angle) * outer_radius)
    local y2 = cy + (math.sin(angle) * outer_radius * 0.86)
    local spark_alpha = alpha_multiplier * (1 - progress) * (0.55 + (energy * 0.30))

    love.graphics.setColor(core_color[1], core_color[2], core_color[3], spark_alpha)
    love.graphics.line(x1, y1, x2, y2)
  end
  love.graphics.setLineWidth(1)
end

local function draw_move_animation(layout, move_animation, alpha_multiplier)
  if not move_animation or not move_animation.from or not move_animation.to then
    return
  end

  local progress = clamp(move_animation.progress or 0, 0, 1)
  local eased = smoothstep(progress)
  local from_x, from_y, cell_size = cell_center(layout, move_animation.from.x, move_animation.from.y)
  local to_x, to_y = cell_center(layout, move_animation.to.x, move_animation.to.y)
  local side = move_animation.side or "player"
  local converted = move_animation.converted or 0
  local capture_energy = clamp((converted - 2) / 4, 0, 1)
  local radius = cell_size * 0.30
  local dx = to_x - from_x
  local dy = to_y - from_y
  local nx, ny = normalize(dx, dy)
  local px = -ny
  local py = nx

  if move_animation.kind == "grow" then
    local bud_x = from_x + ((to_x - from_x) * eased)
    local bud_y = from_y + ((to_y - from_y) * eased)
    local tether_alpha = alpha_multiplier * (0.30 + (0.25 * capture_energy)) * (1 - progress)
    local bridge_alpha = alpha_multiplier * (0.24 + (0.24 * capture_energy)) * (1 - (progress * 0.55))
    local source_width = radius * (0.16 + (0.12 * (1 - progress)))
    local bud_width = radius * (0.24 + (0.34 * eased))
    local wobble = math.sin(progress * math.pi * 2.2) * (radius * 0.08)

    if side == "enemy" then
      set_color(palette.enemy, tether_alpha)
    else
      set_color(palette.player, tether_alpha)
    end

    love.graphics.polygon(
      "fill",
      from_x + (px * source_width),
      from_y + (py * source_width),
      bud_x + (px * bud_width) + (nx * wobble),
      bud_y + (py * bud_width) + (ny * wobble),
      bud_x - (px * bud_width) + (nx * wobble),
      bud_y - (py * bud_width) + (ny * wobble),
      from_x - (px * source_width),
      from_y - (py * source_width)
    )

    if side == "enemy" then
      set_color(palette.enemy_core, bridge_alpha)
    else
      set_color(palette.player_core, bridge_alpha)
    end
    love.graphics.setLineWidth(math.max(1.2, cell_size * 0.09 * (1 - progress)))
    love.graphics.line(from_x, from_y, bud_x, bud_y)
    love.graphics.setLineWidth(1)

    draw_blob_scaled(
      from_x,
      from_y,
      radius,
      side,
      alpha_multiplier * (0.28 + ((1 - progress) * 0.50)),
      1.02 + (progress * 0.12),
      1.00 - (progress * 0.10)
    )

    draw_blob_scaled(
      bud_x,
      bud_y,
      radius,
      side,
      alpha_multiplier * (0.24 + (0.76 * progress)),
      0.38 + (0.76 * eased),
      0.46 + (0.66 * eased)
    )
  else
    local jump_x = from_x + ((to_x - from_x) * eased)
    local jump_y = from_y + ((to_y - from_y) * eased) - (math.sin(progress * math.pi) * cell_size * 0.28)
    local jump_stretch = 1.0 + (math.sin(progress * math.pi) * 0.24)
    local jump_squash = 1.0 - (math.sin(progress * math.pi) * 0.18)

    for trail_index = 1, 4 do
      local trail_progress = progress - (trail_index * 0.10)

      if trail_progress > 0 then
        local trail_eased = smoothstep(trail_progress)
        local trail_x = from_x + ((to_x - from_x) * trail_eased)
        local trail_y = from_y + ((to_y - from_y) * trail_eased)
          - (math.sin(trail_progress * math.pi) * cell_size * 0.24)
        local trail_alpha = alpha_multiplier * (0.18 - (trail_index * 0.03)) * (1 - progress)

        draw_blob(
          trail_x,
          trail_y,
          radius * (0.88 - (trail_index * 0.07)),
          side,
          trail_alpha,
          0.92
        )
      end
    end

    draw_blob_scaled(
      jump_x,
      jump_y,
      radius,
      side,
      alpha_multiplier * (0.30 + (0.60 * (1 - (progress * 0.20)))),
      0.92 * jump_stretch,
      0.98 * jump_squash
    )

    if progress > 0.72 then
      local land = clamp((progress - 0.72) / 0.28, 0, 1)
      local land_radius = (cell_size * 0.24) + (cell_size * 0.68 * land)
      local land_alpha = alpha_multiplier * (1 - land) * (0.34 + (capture_energy * 0.26))

      if side == "enemy" then
        set_color(palette.enemy, land_alpha)
      else
        set_color(palette.player, land_alpha)
      end
      love.graphics.setLineWidth(1.2 + ((1 - land) * 2.2))
      love.graphics.circle("line", to_x, to_y, land_radius)
      love.graphics.setLineWidth(1)
    end
  end

  if capture_energy > 0 then
    local burst = smoothstep(clamp((progress - 0.18) / 0.82, 0, 1))
    local ring_radius = (cell_size * 0.34) + (cell_size * 0.90 * burst)
    local ring_alpha = alpha_multiplier * capture_energy * (1 - burst) * 0.70

    if side == "enemy" then
      set_color(palette.enemy_core, ring_alpha)
    else
      set_color(palette.player_core, ring_alpha)
    end
    love.graphics.setLineWidth(1.2 + (capture_energy * 1.8))
    love.graphics.circle("line", to_x, to_y, ring_radius)
    love.graphics.setLineWidth(1)
    draw_capture_sparks(to_x, to_y, side, alpha_multiplier, capture_energy, burst, cell_size)
  end
end

local function mouse_to_cell(layout)
  if not love or not love.mouse or not love.mouse.getPosition then
    return nil
  end

  local x, y = love.mouse.getPosition()
  local local_x = x - layout.origin_x
  local local_y = y - layout.origin_y

  if local_x < 0 or local_y < 0 then
    return nil
  end

  if local_x >= layout.board_width or local_y >= layout.board_height then
    return nil
  end

  return {
    x = math.floor(local_x / layout.cell_size) + 1,
    y = math.floor(local_y / layout.cell_size) + 1,
  }
end

local function draw_progress_bar(state, layout, alpha_multiplier)
  local player_count = board.count_cells(state, "player")
  local enemy_count = board.count_cells(state, "enemy")
  local total_cells = state.width * state.height
  local player_ratio = player_count / total_cells
  local enemy_ratio = enemy_count / total_cells
  local player_percent = math.floor((player_ratio * 100) + 0.5)
  local enemy_percent = math.floor((enemy_ratio * 100) + 0.5)
  local bar_x = layout.origin_x - 18
  local bar_y = 42
  local bar_width = layout.board_width + 36
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

  love.graphics.setFont(fonts.hud)
  set_color(palette.player, alpha_multiplier)
  love.graphics.print(("%d%%"):format(player_percent), bar_x, bar_y - 20)
  set_color(palette.enemy, alpha_multiplier)
  love.graphics.printf(("%d%%"):format(enemy_percent), bar_x, bar_y - 20, bar_width, "right")

  set_color(palette.cell, alpha_multiplier)
  love.graphics.rectangle("fill", bar_x, bar_y, bar_width, bar_height, 8, 8)
  set_color(palette.player, alpha_multiplier)
  love.graphics.rectangle("fill", bar_x, bar_y, player_width, bar_height, 8, 8)
  set_color(palette.enemy, alpha_multiplier)
  love.graphics.rectangle("fill", bar_x + bar_width - enemy_width, bar_y, enemy_width, bar_height, 8, 8)

  set_color(palette.panel_edge, alpha_multiplier)
  love.graphics.setLineWidth(2)
  love.graphics.rectangle("line", bar_x, bar_y, bar_width, bar_height, 8, 8)
end

function Render.get_main_menu_ui(width, height)
  local panel_width = 420
  local panel_height = 272
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
        y = panel_y + 94,
        width = panel_width - 140,
        height = 50,
      },
      {
        id = "quit",
        label = "Quit",
        x = panel_x + 70,
        y = panel_y + 158,
        width = panel_width - 140,
        height = 50,
      },
    },
  }
end

function Render.get_play_menu_ui(width, height)
  local panel_width = 520
  local panel_height = 410
  local panel_x = math.floor((width - panel_width) * 0.5)
  local panel_y = math.floor((height - panel_height) * 0.5)
  local option_width = 120
  local option_height = 54
  local gap = 20
  local row_width = (option_width * 3) + (gap * 2)
  local options_x = panel_x + math.floor((panel_width - row_width) * 0.5)
  local options_y = panel_y + 116

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
        id = "difficulty_easy",
        label = "Easy",
        x = options_x,
        y = panel_y + 246,
        width = option_width,
        height = 50,
      },
      {
        id = "difficulty_medium",
        label = "Medium",
        x = options_x + option_width + gap,
        y = panel_y + 246,
        width = option_width,
        height = 50,
      },
      {
        id = "difficulty_hard",
        label = "Hard",
        x = options_x + ((option_width + gap) * 2),
        y = panel_y + 246,
        width = option_width,
        height = 50,
      },
      {
        id = "back",
        label = "Back",
        x = panel_x + 56,
        y = panel_y + 334,
        width = 180,
        height = 50,
      },
      {
        id = "start",
        label = "Start",
        x = panel_x + panel_width - 236,
        y = panel_y + 334,
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

  love.graphics.setFont(fonts.section)
  set_color(palette.text_muted)
  love.graphics.printf(("Player %d  |  Enemy %d"):format(
    board.count_cells(state, "player"),
    board.count_cells(state, "enemy")
  ), panel_x, panel_y + 96, panel_width, "center")
end

function Render.draw_main_menu(focused_button_id, menu_transition, pulse_time, audio_status)
  local width, height = love.graphics.getDimensions()
  local ui = Render.get_main_menu_ui(width, height)
  local transition = clamp(menu_transition or 1, 0, 1)
  local y_offset = 0
  local hovered_id = get_hovered_button_id(ui.buttons)

  refresh_fonts_for_size(width, height)
  draw_background(width, height)
  draw_panel(ui.panel.x, ui.panel.y + y_offset, ui.panel.width, ui.panel.height, 20, transition)

  love.graphics.setFont(fonts.title)
  set_color(palette.text, transition)
  love.graphics.printf("Sporeline", ui.panel.x, ui.panel.y + 34, ui.panel.width, "center")
  draw_audio_status_badge(width, height, audio_status, transition, 18)

  for _, button in ipairs(ui.buttons) do
    draw_button(
      button,
      false,
      button.id == focused_button_id,
      button.id == hovered_id,
      pulse_time,
      y_offset,
      transition
    )
  end

  if transition < 1 then
    love.graphics.setColor(0.01, 0.02, 0.03, (1 - transition) * 0.35)
    love.graphics.rectangle("fill", 0, 0, width, height)
  end
end

function Render.draw_play_menu(selected_size, selected_difficulty, focused_button_id, menu_transition, pulse_time, audio_status)
  local width, height = love.graphics.getDimensions()
  local ui = Render.get_play_menu_ui(width, height)
  local transition = clamp(menu_transition or 1, 0, 1)
  local y_offset = 0
  local hovered_id = get_hovered_button_id(ui.buttons)

  refresh_fonts_for_size(width, height)
  draw_background(width, height)
  draw_panel(ui.panel.x, ui.panel.y + y_offset, ui.panel.width, ui.panel.height, 20, transition)

  love.graphics.setFont(fonts.title)
  set_color(palette.text, transition)
  love.graphics.printf("Play", ui.panel.x, ui.panel.y + 30, ui.panel.width, "center")
  draw_audio_status_badge(width, height, audio_status, transition, 18)

  love.graphics.setFont(fonts.section)
  set_color(palette.text_muted, transition)
  love.graphics.printf("Board Size", ui.panel.x, ui.panel.y + 88, ui.panel.width, "center")
  love.graphics.printf("Bot Difficulty", ui.panel.x, ui.panel.y + 218, ui.panel.width, "center")

  for _, button in ipairs(ui.buttons) do
    local active = false

    if button.id == "size_5" then
      active = selected_size == 5
    elseif button.id == "size_7" then
      active = selected_size == 7
    elseif button.id == "size_9" then
      active = selected_size == 9
    elseif button.id == "difficulty_easy" then
      active = selected_difficulty == "easy"
    elseif button.id == "difficulty_medium" then
      active = selected_difficulty == "medium"
    elseif button.id == "difficulty_hard" then
      active = selected_difficulty == "hard"
    end

    draw_button(
      button,
      active,
      button.id == focused_button_id,
      button.id == hovered_id,
      pulse_time,
      y_offset,
      transition
    )
  end

  if transition < 1 then
    love.graphics.setColor(0.01, 0.02, 0.03, (1 - transition) * 0.35)
    love.graphics.rectangle("fill", 0, 0, width, height)
  end
end

function Render.load()
  local width, height = love.graphics.getDimensions()
  refresh_fonts_for_size(width, height)
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

function Render.draw(state, view)
  local width, height = love.graphics.getDimensions()
  local layout = Render.get_layout(width, height, state)
  local cursor_cell = nil
  local piece_animations = nil
  local transition = 1
  local ui_time = 0
  local hovered_cell = nil
  local preview_cell = nil
  local move_source = nil
  local move_animation = nil
  local audio_status = nil

  if view and view.cursor_cell then
    cursor_cell = view.cursor_cell
  end

  if view and view.piece_animations then
    piece_animations = view.piece_animations
  end

  if view and view.transition ~= nil then
    transition = clamp(view.transition, 0, 1)
  end

  if view and view.ui_time ~= nil then
    ui_time = view.ui_time
  end

  if view and view.audio_status then
    audio_status = view.audio_status
  end

  if view and view.move_animation then
    move_animation = view.move_animation
  end

  hovered_cell = mouse_to_cell(layout)
  if hovered_cell
    and not state.selected_cell
    and not state.winner
    and state.current_player == "player"
    and board.get_cell(state, hovered_cell.x, hovered_cell.y) == "player" then
    preview_cell = hovered_cell
  end

  local move_lookup
  move_lookup, move_source = build_move_lookup(state, preview_cell)

  local highlight_pulse = (math.sin(ui_time * 5.4) + 1) * 0.5

  refresh_fonts_for_size(width, height)
  draw_background(width, height)
  draw_progress_bar(state, layout, transition)
  draw_audio_status_badge(width, height, audio_status, transition, height - 46)

  love.graphics.setColor(
    palette.board_shadow[1],
    palette.board_shadow[2],
    palette.board_shadow[3],
    palette.board_shadow[4] * transition
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

  set_color(palette.panel, transition)
  love.graphics.rectangle(
    "fill",
    layout.origin_x - 18,
    layout.origin_y - 18,
    layout.board_width + 36,
    layout.board_height + 36,
    28,
    28
  )
  set_color(palette.panel_edge, transition)
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
      local is_cursor = cursor_cell and cursor_cell.x == x and cursor_cell.y == y
      local is_preview_source = preview_cell and preview_cell.x == x and preview_cell.y == y
      local is_move_source = move_source and move_source.x == x and move_source.y == y
      local can_hover_lift = not state.winner and state.current_player == "player" and occupant == "player"
      local is_hovered_piece = can_hover_lift
        and hovered_cell
        and hovered_cell.x == x
        and hovered_cell.y == y
      local is_keyboard_hovered_piece = can_hover_lift and is_cursor and not state.selected_cell
      local piece_animation = nil
      local piece_lift = 0

      if piece_animations then
        piece_animation = piece_animations[cell_key(x, y)]
      end

      if is_preview_source and is_move_source then
        local pickup_pulse = (math.sin((ui_time * 7.4) + ((x + y) * 0.35)) + 1) * 0.5
        piece_lift = 0.58 + (pickup_pulse * 0.12)
      elseif is_selected then
        local selected_pulse = (math.sin((ui_time * 6.2) + ((x + y) * 0.28)) + 1) * 0.5
        piece_lift = 0.52 + (selected_pulse * 0.10)
      elseif is_hovered_piece or is_keyboard_hovered_piece then
        local hover_pulse = (math.sin((ui_time * 6.8) + ((x + y) * 0.25)) + 1) * 0.5
        piece_lift = 0.42 + (hover_pulse * 0.12)
      end

      set_color(palette.cell, transition)
      love.graphics.rectangle("fill", px + 3, py + 3, size - 6, size - 6, 16, 16)
      set_color(palette.cell_edge, transition)
      love.graphics.setLineWidth(1)
      love.graphics.rectangle("line", px + 3, py + 3, size - 6, size - 6, 16, 16)

      if move_kind == "grow" then
        local phase = ((x * 13) + (y * 7)) * 0.15
        local bob = math.sin((ui_time * 4.8) + phase) * 1.3
        local breathe = math.sin((ui_time * 3.6) + phase) * 0.7
        local inset = 8 - (breathe * 0.45)
        local rect_size = size - (inset * 2)
        local move_alpha = 0.72 + (highlight_pulse * 0.28)
        set_color(palette.grow, transition * move_alpha)
        love.graphics.rectangle("fill", px + inset, py + inset + bob, rect_size, rect_size, 14, 14)
        set_color(palette.grow_edge, transition * (0.80 + (highlight_pulse * 0.20)))
        love.graphics.rectangle("line", px + inset, py + inset + bob, rect_size, rect_size, 14, 14)
      elseif move_kind == "jump" then
        local phase = ((x * 11) + (y * 5)) * 0.17
        local bob = math.sin((ui_time * 4.5) + phase) * 1.2
        local breathe = math.sin((ui_time * 3.1) + phase) * 0.65
        local inset = 8 - (breathe * 0.40)
        local rect_size = size - (inset * 2)
        local move_alpha = 0.72 + (highlight_pulse * 0.28)
        set_color(palette.jump, transition * move_alpha)
        love.graphics.rectangle("fill", px + inset, py + inset + bob, rect_size, rect_size, 14, 14)
        set_color(palette.jump_edge, transition * (0.80 + (highlight_pulse * 0.20)))
        love.graphics.rectangle("line", px + inset, py + inset + bob, rect_size, rect_size, 14, 14)
      end

      if is_selected then
        set_color(palette.selected, transition * (0.84 + (highlight_pulse * 0.16)))
        love.graphics.setLineWidth(2 + (highlight_pulse * 2))
        love.graphics.rectangle("line", px + 5, py + 5, size - 10, size - 10, 16, 16)
      elseif is_cursor and not state.winner then
        set_color(palette.text_muted, transition * (0.75 + (highlight_pulse * 0.25)))
        love.graphics.setLineWidth(1.5 + (highlight_pulse * 1.2))
        love.graphics.rectangle("line", px + 10, py + 10, size - 20, size - 20, 14, 14)
      elseif is_last_move then
        set_color(palette.text_muted, transition * (0.68 + (highlight_pulse * 0.20)))
        love.graphics.setLineWidth(1.6 + (highlight_pulse * 1.0))
        love.graphics.rectangle("line", px + 7, py + 7, size - 14, size - 14, 16, 16)
      end

      if occupant ~= "empty" then
        draw_piece(px, py, size, occupant, piece_animation, transition, piece_lift)
      end
    end
  end

  draw_move_animation(layout, move_animation, transition)

  if transition < 1 and not state.winner then
    love.graphics.setColor(0.01, 0.02, 0.03, (1 - transition) * 0.42)
    love.graphics.rectangle("fill", 0, 0, width, height)
  end

  if state.winner then
    draw_overlay(state, width, height)
  end
end

return Render
