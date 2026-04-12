local ai = require("src.ai")
local audio = require("src.audio")
local board = require("src.board")
local input = require("src.input")
local level = require("src.level")
local render = require("src.render")
local rules = require("src.rules")

local Game = {}
Game.__index = Game

local MENU_FADE_DURATION = 0.80
local PLAY_FADE_DURATION = 0.24
local PIECE_SPAWN_DURATION = 0.18
local PIECE_CONVERT_DURATION = 0.24
local MOVE_GROW_DURATION = 0.34
local MOVE_JUMP_DURATION = 0.30
local BIG_CAPTURE_THRESHOLD = 3
local BIG_CAPTURE_SHAKE_DURATION = 0.22
local OPENING_SCENE_DURATION = 0.82
local OPENING_SCENE_MUSIC_DELAY = 0.60
local SETTINGS_VOLUME_STEP = 0.05
local CURSOR_REPEAT_DELAY = 0.22
local CURSOR_REPEAT_INTERVAL = 0.07

local MAIN_MENU_FOCUS = {
  play = { up = "quit", down = "quit", left = "quit", right = "quit" },
  quit = { up = "play", down = "play", left = "play", right = "play" },
}

local PLAY_MENU_FOCUS = {
  size_5 = { up = "back", down = "difficulty_easy", left = "size_9", right = "size_7" },
  size_7 = { up = "start", down = "difficulty_medium", left = "size_5", right = "size_9" },
  size_9 = { up = "start", down = "difficulty_hard", left = "size_7", right = "size_5" },
  difficulty_easy = { up = "size_5", down = "back", left = "difficulty_hard", right = "difficulty_medium" },
  difficulty_medium = { up = "size_7", down = "start", left = "difficulty_easy", right = "difficulty_hard" },
  difficulty_hard = { up = "size_9", down = "start", left = "difficulty_medium", right = "difficulty_easy" },
  back = { up = "difficulty_easy", down = "size_5", left = "start", right = "start" },
  start = { up = "difficulty_hard", down = "size_7", left = "back", right = "back" },
}

local function point_in_rect(x, y, rect)
  return x >= rect.x
    and x <= rect.x + rect.width
    and y >= rect.y
    and y <= rect.y + rect.height
end

local function is_confirm_key(key)
  return key == "return" or key == "kpenter" or key == "space"
end

local function is_shift_down()
  if not love or not love.keyboard or not love.keyboard.isDown then
    return false
  end

  return love.keyboard.isDown("lshift") or love.keyboard.isDown("rshift")
end

local function find_button_index(buttons, button_id)
  for index, button in ipairs(buttons) do
    if button.id == button_id then
      return index
    end
  end

  return nil
end

local function find_first_player_cell(state)
  for y = 1, state.height do
    for x = 1, state.width do
      if board.get_cell(state, x, y) == "player" then
        return { x = x, y = y }
      end
    end
  end

  return { x = 1, y = 1 }
end

local CURSOR_REPEAT_DIRECTIONS = {
  { key = "up", dx = 0, dy = -1 },
  { key = "down", dx = 0, dy = 1 },
  { key = "left", dx = -1, dy = 0 },
  { key = "right", dx = 1, dy = 0 },
}

local function animation_key(x, y)
  return y .. ":" .. x
end

local function build_piece_animations(previous_state, next_state)
  local animations = {}

  if not next_state then
    return animations
  end

  for y = 1, next_state.height do
    for x = 1, next_state.width do
      local before = "empty"
      local after = board.get_cell(next_state, x, y)

      if previous_state then
        before = board.get_cell(previous_state, x, y) or "empty"
      end

      if after ~= "empty" and before ~= after then
        local kind = "convert"
        local duration = PIECE_CONVERT_DURATION

        if before == "empty" then
          kind = "spawn"
          duration = PIECE_SPAWN_DURATION
        end

        animations[animation_key(x, y)] = {
          kind = kind,
          progress = 0,
          duration = duration,
        }
      end
    end
  end

  return animations
end

function Game.new()
  local self = setmetatable({}, Game)

  self.audio = audio.new()
  self.ai_delay = 0.45
  self.ai_timer = 0
  self.state = nil
  self.selected_board_size = 7
  self.board_size = 7
  self.selected_bot_difficulty = "hard"
  self.bot_difficulty = "hard"
  self.cursor_cell = nil
  self.menu_transition = 1
  self.menu_pulse_time = 0
  self.play_transition = 1
  self.visual_time = 0
  self.piece_animations = {}
  self.move_animation = nil
  self.opening_scene = nil
  self.screen_shake = {
    x = 0,
    y = 0,
    elapsed = 0,
    duration = 0,
    amplitude = 0,
  }
  self.cursor_repeat = {
    up = { held = false, elapsed = 0 },
    down = { held = false, elapsed = 0 },
    left = { held = false, elapsed = 0 },
    right = { held = false, elapsed = 0 },
  }
  self.menu_focus_index = nil
  self.settings_visible = false
  self.screen = nil
  self:set_screen("main_menu")

  return self
end

function Game:set_state(next_state, previous_state)
  local prior_state = previous_state

  if prior_state == nil then
    prior_state = self.state
  elseif prior_state == false then
    prior_state = nil
  end

  self.state = next_state
  self.piece_animations = build_piece_animations(prior_state, next_state)
  self:handle_state_audio_events(prior_state, next_state)
end

function Game:handle_state_audio_events(previous_state, next_state)
  if not previous_state or not next_state then
    return
  end

  local previous_pass_count = previous_state.pass_count or 0
  local next_pass_count = next_state.pass_count or 0

  if next_pass_count > previous_pass_count then
    self.audio:play("pass")
  end

  if not previous_state.winner and next_state.winner then
    if next_state.winner == "player" then
      self.audio:play("win")
      return
    end

    if next_state.winner == "enemy" then
      self.audio:play("lose")
      return
    end

    self.audio:play("tie")
  end
end

function Game:reset_cursor_repeat()
  for _, direction in ipairs(CURSOR_REPEAT_DIRECTIONS) do
    local repeat_state = self.cursor_repeat[direction.key]
    repeat_state.held = false
    repeat_state.elapsed = 0
  end
end

function Game:start_game(board_size, bot_difficulty)
  local size = board_size or self.selected_board_size or 7
  local difficulty = bot_difficulty or self.selected_bot_difficulty or "hard"
  local with_intro = self.screen == "main_menu" or self.screen == "play_menu"
  self.selected_board_size = size
  self.selected_bot_difficulty = difficulty
  self.board_size = size
  self.bot_difficulty = difficulty
  local next_state = rules.resolve_state(level.load(size))
  self:set_state(next_state, false)
  self:set_screen("playing", { with_intro = with_intro })
  self.ai_timer = 0
  self.move_animation = nil
  self.screen_shake.x = 0
  self.screen_shake.y = 0
  self.screen_shake.elapsed = 0
  self.screen_shake.duration = 0
  self.screen_shake.amplitude = 0
  self.cursor_cell = find_first_player_cell(self.state)
end

function Game:restart()
  if self.screen ~= "playing" then
    return
  end

  local next_state = rules.resolve_state(level.load(self.board_size))
  self:set_state(next_state, false)
  self.ai_timer = 0
  self.move_animation = nil
  self.screen_shake.x = 0
  self.screen_shake.y = 0
  self.screen_shake.elapsed = 0
  self.screen_shake.duration = 0
  self.screen_shake.amplitude = 0
  self.cursor_cell = find_first_player_cell(self.state)
end

function Game:start_move_animation(side, last_move)
  if not last_move then
    self.move_animation = nil
    return
  end

  local duration = MOVE_GROW_DURATION
  if last_move.kind == "jump" then
    duration = MOVE_JUMP_DURATION
  end

  self.move_animation = {
    kind = last_move.kind,
    side = side or "player",
    from = { x = last_move.from.x, y = last_move.from.y },
    to = { x = last_move.to.x, y = last_move.to.y },
    converted = last_move.converted or 0,
    progress = 0,
    duration = duration,
  }
end

function Game:trigger_screen_shake(amplitude, duration)
  local next_amplitude = amplitude or 0

  if next_amplitude <= 0 then
    return
  end

  local next_duration = duration or BIG_CAPTURE_SHAKE_DURATION

  if self.screen_shake.amplitude < next_amplitude then
    self.screen_shake.amplitude = next_amplitude
  end

  if self.screen_shake.duration < next_duration then
    self.screen_shake.duration = next_duration
  end

  self.screen_shake.elapsed = 0
end

function Game:commit_move(move)
  local moving_side = self.state and self.state.current_player
  local next_state = rules.resolve_state(rules.apply_move(self.state, move))
  self:set_state(next_state, self.state)
  self.ai_timer = 0

  if moving_side == "player" then
    self.audio:play("player_move")
  elseif moving_side == "enemy" then
    self.audio:play("enemy_move")
  end

  local converted = self.state
    and self.state.last_move
    and self.state.last_move.converted
    or 0

  if converted > 0 then
    self.audio:play("convert")
  end

  if converted >= BIG_CAPTURE_THRESHOLD then
    self.audio:play("big_capture")
    local shake_intensity = 2.3 + math.min(3.8, converted * 0.85)
    self:trigger_screen_shake(shake_intensity, BIG_CAPTURE_SHAKE_DURATION + (converted * 0.015))
  end

  self:start_move_animation(moving_side, self.state and self.state.last_move)
end

function Game:update_piece_animations(dt)
  if not self.piece_animations then
    return
  end

  local delta = dt or 0

  if delta <= 0 then
    return
  end

  for key, animation in pairs(self.piece_animations) do
    local duration = animation.duration or PIECE_SPAWN_DURATION
    local progress = animation.progress + (delta / duration)
    animation.progress = progress

    if progress >= 1 then
      self.piece_animations[key] = nil
    end
  end
end

function Game:update_move_animation(dt)
  if not self.move_animation then
    return
  end

  local delta = dt or 0
  local duration = self.move_animation.duration or MOVE_GROW_DURATION
  local progress = self.move_animation.progress + (delta / duration)
  self.move_animation.progress = progress

  if progress >= 1 then
    self.move_animation = nil
  end
end

function Game:update_screen_shake(dt)
  if not self.screen_shake then
    return
  end

  local duration = self.screen_shake.duration or 0
  local amplitude = self.screen_shake.amplitude or 0

  if duration <= 0 or amplitude <= 0 then
    self.screen_shake.x = 0
    self.screen_shake.y = 0
    return
  end

  local delta = dt or 0
  self.screen_shake.elapsed = self.screen_shake.elapsed + delta
  local progress = self.screen_shake.elapsed / duration

  if progress >= 1 then
    self.screen_shake.elapsed = 0
    self.screen_shake.duration = 0
    self.screen_shake.amplitude = 0
    self.screen_shake.x = 0
    self.screen_shake.y = 0
    return
  end

  local decay = (1 - progress) * (1 - progress)
  local live_amplitude = amplitude * decay
  local rand = math.random

  if love and love.math and love.math.random then
    rand = love.math.random
  end

  self.screen_shake.x = ((rand() * 2) - 1) * live_amplitude
  self.screen_shake.y = ((rand() * 2) - 1) * live_amplitude
end

function Game:get_screen_shake_offset()
  if not self.screen_shake then
    return { x = 0, y = 0 }
  end

  return {
    x = self.screen_shake.x or 0,
    y = self.screen_shake.y or 0,
  }
end

function Game:update_cursor_repeat(delta)
  if not love or not love.keyboard or not love.keyboard.isDown then
    return
  end

  for _, direction in ipairs(CURSOR_REPEAT_DIRECTIONS) do
    local key = direction.key
    local repeat_state = self.cursor_repeat[key]
    local is_down = love.keyboard.isDown(key)

    if not is_down then
      repeat_state.held = false
      repeat_state.elapsed = 0
    else
      if not repeat_state.held then
        repeat_state.held = true
      end

      repeat_state.elapsed = repeat_state.elapsed + delta

      if repeat_state.elapsed >= CURSOR_REPEAT_DELAY then
        local overflow = repeat_state.elapsed - CURSOR_REPEAT_DELAY
        local steps = math.floor(overflow / CURSOR_REPEAT_INTERVAL)

        if steps > 0 then
          for _ = 1, steps do
            self:move_cursor(direction.dx, direction.dy)
          end

          repeat_state.elapsed = CURSOR_REPEAT_DELAY + (overflow - (steps * CURSOR_REPEAT_INTERVAL))
        end
      end
    end
  end
end

function Game:get_window_dimensions()
  if love and love.graphics and love.graphics.getDimensions then
    return love.graphics.getDimensions()
  end

  return 700, 700
end

function Game:get_menu_ui(screen)
  local width, height = self:get_window_dimensions()
  local target_screen = screen or self.screen

  if target_screen == "main_menu" then
    return render.get_main_menu_ui(width, height)
  end

  if target_screen == "play_menu" then
    return render.get_play_menu_ui(width, height)
  end

  return nil
end

function Game:get_menu_buttons(screen)
  local ui = self:get_menu_ui(screen)

  if not ui then
    return nil
  end

  return ui.buttons
end

function Game:get_menu_settings_controls(screen)
  local ui = self:get_menu_ui(screen)

  if not ui then
    return nil
  end

  return ui.settings_controls
end

function Game:default_menu_focus_index(screen)
  local target_screen = screen or self.screen
  local buttons = self:get_menu_buttons(target_screen)

  if not buttons or #buttons == 0 then
    return nil
  end

  if target_screen == "play_menu" then
    return find_button_index(buttons, "start") or 1
  end

  return find_button_index(buttons, "play") or 1
end

function Game:start_opening_scene()
  self.opening_scene = {
    active = true,
    elapsed = 0,
    duration = OPENING_SCENE_DURATION,
    music_delay = OPENING_SCENE_MUSIC_DELAY,
    music_started = false,
  }
end

function Game:clear_opening_scene()
  self.opening_scene = nil
end

function Game:update_opening_scene(dt)
  local scene = self.opening_scene

  if not scene or not scene.active then
    return
  end

  scene.elapsed = scene.elapsed + (dt or 0)

  if not scene.music_started and scene.elapsed >= (scene.music_delay or OPENING_SCENE_MUSIC_DELAY) then
    self.audio:set_context("game")
    scene.music_started = true
  end

  if scene.elapsed >= (scene.duration or OPENING_SCENE_DURATION) then
    scene.active = false
    scene.elapsed = scene.duration or OPENING_SCENE_DURATION

    if not scene.music_started then
      self.audio:set_context("game")
      scene.music_started = true
    end
  end
end

function Game:get_opening_scene_view()
  local scene = self.opening_scene

  if not scene then
    return nil
  end

  local duration = math.max(scene.duration or OPENING_SCENE_DURATION, 0.0001)

  return {
    active = scene.active == true,
    progress = math.min(1, math.max(0, (scene.elapsed or 0) / duration)),
  }
end

function Game:set_screen(screen, options)
  local opts = options or {}
  self.screen = screen

  if screen == "playing" then
    self.menu_focus_index = nil
    self.menu_transition = 1
    self.play_transition = 0
    self:reset_cursor_repeat()

    if opts.with_intro then
      self:start_opening_scene()
    else
      self:clear_opening_scene()
      self.audio:set_context("game")
    end

    return
  end

  self:clear_opening_scene()
  self.play_transition = 1
  self.menu_transition = 0
  self.menu_pulse_time = 0
  self.screen_shake.x = 0
  self.screen_shake.y = 0
  self.screen_shake.elapsed = 0
  self.screen_shake.duration = 0
  self.screen_shake.amplitude = 0
  self:reset_cursor_repeat()
  self.menu_focus_index = self:default_menu_focus_index(screen)
  self.audio:set_context("menu")
end

function Game:toggle_fullscreen()
  if not love or not love.window or not love.window.getFullscreen or not love.window.setFullscreen then
    return
  end

  local is_fullscreen = love.window.getFullscreen()
  local ok = pcall(love.window.setFullscreen, not is_fullscreen, "desktop")

  if not ok then
    pcall(love.window.setFullscreen, not is_fullscreen)
  end
end

function Game:is_fullscreen()
  if not love or not love.window or not love.window.getFullscreen then
    return false
  end

  return love.window.getFullscreen()
end

function Game:can_toggle_mute()
  if self.screen ~= "play_menu" then
    return true
  end

  return is_shift_down()
end

function Game:toggle_mute()
  local muted = self.audio:toggle_muted()

  if not muted then
    self.audio:play("navigate")
  end
end

function Game:adjust_sfx_volume(delta)
  local current_volume = self.audio:get_sfx_volume()
  local next_volume = self.audio:adjust_sfx_volume(delta)

  if math.abs(next_volume - current_volume) > 0.0001 then
    self.audio:play("navigate")
  end
end

function Game:adjust_music_volume(delta)
  local current_volume = self.audio:get_music_volume()
  local next_volume = self.audio:adjust_music_volume(delta)

  if math.abs(next_volume - current_volume) > 0.0001 then
    self.audio:play("navigate")
  end
end

function Game:handle_settings_action(control_id)
  if control_id == "fullscreen" then
    self:toggle_fullscreen()
    return true
  end

  if control_id == "mute" then
    self:toggle_mute()
    return true
  end

  if control_id == "sfx_down" then
    self:adjust_sfx_volume(-SETTINGS_VOLUME_STEP)
    return true
  end

  if control_id == "sfx_up" then
    self:adjust_sfx_volume(SETTINGS_VOLUME_STEP)
    return true
  end

  if control_id == "music_down" then
    self:adjust_music_volume(-SETTINGS_VOLUME_STEP)
    return true
  end

  if control_id == "music_up" then
    self:adjust_music_volume(SETTINGS_VOLUME_STEP)
    return true
  end

  return false
end

function Game:handle_settings_click(x, y, screen)
  if not self.settings_visible then
    return false
  end

  local controls = self:get_menu_settings_controls(screen)

  if not controls then
    return false
  end

  local control_id = self:find_clicked_button(controls, x, y)

  if not control_id then
    return false
  end

  return self:handle_settings_action(control_id)
end

function Game:get_audio_status()
  local hint = "M"

  if self.screen == "play_menu" then
    hint = "Shift+M"
  end

  return {
    text = self.audio:get_status_text(),
    muted = self.audio:is_muted(),
    sfx_volume = self.audio:get_sfx_volume(),
    music_volume = self.audio:get_music_volume(),
    fullscreen = self:is_fullscreen(),
    settings_visible = self.settings_visible == true,
    hint = hint,
  }
end

function Game:toggle_settings_visibility()
  self.settings_visible = not self.settings_visible
  self.audio:play("navigate")
end

function Game:get_focused_menu_button_id()
  local buttons = self:get_menu_buttons()

  if not buttons or #buttons == 0 then
    return nil
  end

  local focus_index = self.menu_focus_index or self:default_menu_focus_index()

  if not focus_index then
    return nil
  end

  local button = buttons[focus_index]
  if not button then
    return nil
  end

  return button.id
end

function Game:set_menu_focus_by_id(button_id)
  local buttons = self:get_menu_buttons()

  if not buttons then
    return
  end

  local index = find_button_index(buttons, button_id)
  if index then
    self.menu_focus_index = index
  end
end

function Game:move_menu_focus(direction)
  local current_id = self:get_focused_menu_button_id()

  if not current_id then
    return
  end

  local mapping = nil
  if self.screen == "main_menu" then
    mapping = MAIN_MENU_FOCUS
  elseif self.screen == "play_menu" then
    mapping = PLAY_MENU_FOCUS
  end

  if not mapping or not mapping[current_id] then
    return
  end

  local next_id = mapping[current_id][direction]
  if next_id then
    self:set_menu_focus_by_id(next_id)

    if next_id ~= current_id then
      self.audio:play("navigate")
    end
  end
end

function Game:activate_focused_menu_button()
  local button_id = self:get_focused_menu_button_id()

  if not button_id then
    return
  end

  self.audio:play("confirm")

  if self.screen == "main_menu" then
    self:handle_main_menu_action(button_id)
    return
  end

  if self.screen == "play_menu" then
    self:handle_play_menu_action(button_id)
  end
end

function Game:find_clicked_button(buttons, x, y)
  for index, button in ipairs(buttons) do
    if point_in_rect(x, y, button) then
      return button.id, index
    end
  end

  return nil, nil
end

function Game:handle_main_menu_action(button_id)
  if button_id == "play" then
    self:set_screen("play_menu")
    return
  end

  if button_id == "quit" and love and love.event then
    love.event.quit()
  end
end

function Game:handle_main_menu_click(x, y)
  local ui = self:get_menu_ui("main_menu")

  if self:handle_settings_click(x, y, "main_menu") then
    return
  end

  local button_id, button_index = self:find_clicked_button(ui.buttons, x, y)

  if not button_id then
    return
  end

  self.menu_focus_index = button_index
  self.audio:play("confirm")
  self:handle_main_menu_action(button_id)
end

function Game:handle_play_menu_action(button_id)
  if button_id == "size_5" then
    self.selected_board_size = 5
    self:set_menu_focus_by_id(button_id)
    return
  end

  if button_id == "size_7" then
    self.selected_board_size = 7
    self:set_menu_focus_by_id(button_id)
    return
  end

  if button_id == "size_9" then
    self.selected_board_size = 9
    self:set_menu_focus_by_id(button_id)
    return
  end

  if button_id == "difficulty_easy" then
    self.selected_bot_difficulty = "easy"
    self:set_menu_focus_by_id(button_id)
    return
  end

  if button_id == "difficulty_medium" then
    self.selected_bot_difficulty = "medium"
    self:set_menu_focus_by_id(button_id)
    return
  end

  if button_id == "difficulty_hard" then
    self.selected_bot_difficulty = "hard"
    self:set_menu_focus_by_id(button_id)
    return
  end

  if button_id == "back" then
    self:set_screen("main_menu")
    return
  end

  if button_id == "start" then
    self:start_game(self.selected_board_size, self.selected_bot_difficulty)
    return
  end
end

function Game:handle_play_menu_click(x, y)
  local ui = self:get_menu_ui("play_menu")

  if self:handle_settings_click(x, y, "play_menu") then
    return
  end

  local button_id, button_index = self:find_clicked_button(ui.buttons, x, y)

  if not button_id then
    return
  end

  self.menu_focus_index = button_index
  self.audio:play("confirm")
  self:handle_play_menu_action(button_id)
end

function Game:move_cursor(dx, dy)
  if self.screen ~= "playing" or not self.state then
    return
  end

  if not self.cursor_cell then
    self.cursor_cell = find_first_player_cell(self.state)
  end

  local next_x = self.cursor_cell.x + dx
  local next_y = self.cursor_cell.y + dy

  if next_x < 1 then
    next_x = 1
  elseif next_x > self.state.width then
    next_x = self.state.width
  end

  if next_y < 1 then
    next_y = 1
  elseif next_y > self.state.height then
    next_y = self.state.height
  end

  local changed = self.cursor_cell.x ~= next_x or self.cursor_cell.y ~= next_y
  self.cursor_cell = { x = next_x, y = next_y }

  if changed then
    self.audio:play("cursor_move")
  end
end

function Game:activate_cursor_cell()
  if self.screen ~= "playing" or not self.state or not self.cursor_cell then
    return
  end

  if self.state.winner or self.state.current_player ~= "player" then
    self.audio:play("invalid")
    return
  end

  local cell = self.cursor_cell

  if self.state.selected_cell then
    local selected_move = rules.find_move(self.state, "player", self.state.selected_cell, cell)

    if selected_move then
      self:commit_move(selected_move)
      return
    end
  end

  if board.get_cell(self.state, cell.x, cell.y) == "player" then
    if board.same_cell(self.state.selected_cell, cell) then
      self.state.selected_cell = nil
    else
      self.state.selected_cell = { x = cell.x, y = cell.y }
      self.audio:play("select")
    end
  else
    self.state.selected_cell = nil
    self.audio:play("invalid")
  end
end

function Game:run_enemy_turn()
  if self.screen ~= "playing" or not self.state then
    return
  end

  if self.state.winner or self.state.current_player ~= "enemy" then
    return
  end

  local move = ai.choose_move(self.state, "enemy", self.bot_difficulty)

  if not move then
    local next_state = rules.resolve_state(self.state)
    self:set_state(next_state, self.state)
    self.ai_timer = 0
    return
  end

  self:commit_move(move)
end

function Game:resolve_forced_pass()
  if self.screen ~= "playing" or not self.state then
    return
  end

  if self.state.winner then
    return
  end

  local active_side = self.state.current_player
  local active_moves = rules.get_legal_moves(self.state, active_side)

  if #active_moves > 0 then
    return
  end

  local next_state = rules.resolve_state(self.state)
  self:set_state(next_state, self.state)
  self.ai_timer = 0
end

function Game:update(dt)
  local delta = dt or 0
  self.visual_time = self.visual_time + delta
  self.audio:update(delta)

  if self.screen == "main_menu" or self.screen == "play_menu" then
    self.menu_pulse_time = self.menu_pulse_time + delta
    if self.menu_transition < 1 then
      self.menu_transition = math.min(1, self.menu_transition + (delta / MENU_FADE_DURATION))
    end
    return
  end

  if self.screen ~= "playing" or not self.state then
    return
  end

  if self.play_transition < 1 then
    self.play_transition = math.min(1, self.play_transition + (delta / PLAY_FADE_DURATION))
  end
  self:update_opening_scene(delta)

  if not self.state.winner and self.state.current_player == "player" then
    self:update_cursor_repeat(delta)
  else
    self:reset_cursor_repeat()
  end

  self:update_piece_animations(delta)
  self:update_move_animation(delta)
  self:update_screen_shake(delta)
  self:resolve_forced_pass()

  if self.state.winner then
    return
  end

  if self.state.current_player == "enemy" then
    self.ai_timer = self.ai_timer + delta

    if self.ai_timer >= self.ai_delay then
      self:run_enemy_turn()
    end
  else
    self.ai_timer = 0
  end
end

function Game:mousepressed(x, y, button)
  if not input.is_primary_click(button) then
    return
  end

  if self.screen == "main_menu" then
    self:handle_main_menu_click(x, y)
    return
  end

  if self.screen == "play_menu" then
    self:handle_play_menu_click(x, y)
    return
  end

  if self.screen ~= "playing" or not self.state then
    return
  end

  if self.state.winner or self.state.current_player ~= "player" then
    return
  end

  local width, height = love.graphics.getDimensions()
  local layout = render.get_layout(width, height, self.state)
  local cell = input.screen_to_cell(layout, x, y)

  if not cell then
    self.state.selected_cell = nil
    return
  end

  self.cursor_cell = { x = cell.x, y = cell.y }

  if self.state.selected_cell then
    local selected_move = rules.find_move(self.state, "player", self.state.selected_cell, cell)

    if selected_move then
      self:commit_move(selected_move)
      return
    end
  end

  if board.get_cell(self.state, cell.x, cell.y) == "player" then
    if board.same_cell(self.state.selected_cell, cell) then
      self.state.selected_cell = nil
    else
      self.state.selected_cell = { x = cell.x, y = cell.y }
      self.audio:play("select")
    end
  else
    self.state.selected_cell = nil
  end
end

function Game:keypressed(key)
  if input.is_toggle_settings_key(key) and (self.screen == "main_menu" or self.screen == "play_menu") then
    self:toggle_settings_visibility()
    return
  end

  if input.is_fullscreen_key(key) then
    self:toggle_fullscreen()
    return
  end

  if input.is_mute_key(key) and self:can_toggle_mute() then
    self:toggle_mute()
    return
  end

  if self.screen == "main_menu" then
    if key == "up" then
      self:move_menu_focus("up")
      return
    end

    if key == "down" then
      self:move_menu_focus("down")
      return
    end

    if key == "left" then
      self:move_menu_focus("left")
      return
    end

    if key == "right" then
      self:move_menu_focus("right")
      return
    end

    if key == "p" then
      self:handle_main_menu_action("play")
      return
    end

    if is_confirm_key(key) then
      self:activate_focused_menu_button()
      return
    end

    if input.is_quit_key(key) then
      love.event.quit()
    end
    return
  end

  if self.screen == "play_menu" then
    if key == "up" then
      self:move_menu_focus("up")
      return
    end

    if key == "down" then
      self:move_menu_focus("down")
      return
    end

    if key == "left" then
      self:move_menu_focus("left")
      return
    end

    if key == "right" then
      self:move_menu_focus("right")
      return
    end

    if key == "5" then
      self.selected_board_size = 5
      return
    end

    if key == "7" then
      self.selected_board_size = 7
      return
    end

    if key == "9" then
      self.selected_board_size = 9
      return
    end

    if key == "e" then
      self.selected_bot_difficulty = "easy"
      return
    end

    if key == "m" then
      self.selected_bot_difficulty = "medium"
      return
    end

    if key == "h" then
      self.selected_bot_difficulty = "hard"
      return
    end

    if is_confirm_key(key) then
      self:activate_focused_menu_button()
      return
    end

    if input.is_quit_key(key) then
      self:set_screen("main_menu")
    end
    return
  end

  if key == "up" then
    self:move_cursor(0, -1)
    return
  end

  if key == "down" then
    self:move_cursor(0, 1)
    return
  end

  if key == "left" then
    self:move_cursor(-1, 0)
    return
  end

  if key == "right" then
    self:move_cursor(1, 0)
    return
  end

  if is_confirm_key(key) then
    self:activate_cursor_cell()
    return
  end

  if input.is_restart_key(key) then
    self:restart()
    return
  end

  if input.is_quit_key(key) then
    self:set_screen("main_menu")
    self.state = nil
    self.piece_animations = {}
    self.move_animation = nil
    self.screen_shake.x = 0
    self.screen_shake.y = 0
    self.screen_shake.elapsed = 0
    self.screen_shake.duration = 0
    self.screen_shake.amplitude = 0
    self.ai_timer = 0
    self.cursor_cell = nil
  end
end

function Game:draw()
  if self.screen == "main_menu" then
    render.draw_main_menu(
      self:get_focused_menu_button_id(),
      self.menu_transition,
      self.menu_pulse_time,
      self:get_audio_status(),
      self.settings_visible
    )
    return
  end

  if self.screen == "play_menu" then
    render.draw_play_menu(
      self.selected_board_size,
      self.selected_bot_difficulty,
      self:get_focused_menu_button_id(),
      self.menu_transition,
      self.menu_pulse_time,
      self:get_audio_status(),
      self.settings_visible
    )
    return
  end

  if self.state then
    render.draw(self.state, {
      cursor_cell = self.cursor_cell,
      piece_animations = self.piece_animations,
      move_animation = self.move_animation,
      opening_scene = self:get_opening_scene_view(),
      shake_offset = self:get_screen_shake_offset(),
      transition = self.play_transition,
      ui_time = self.visual_time,
      audio_status = self:get_audio_status(),
    })
  end
end

return Game
