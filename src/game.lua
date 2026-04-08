local ai = require("src.ai")
local board = require("src.board")
local input = require("src.input")
local level = require("src.level")
local render = require("src.render")
local rules = require("src.rules")

local Game = {}
Game.__index = Game

local MAIN_MENU_FOCUS = {
  play = { up = "quit", down = "quit", left = "quit", right = "quit" },
  quit = { up = "play", down = "play", left = "play", right = "play" },
}

local PLAY_MENU_FOCUS = {
  size_5 = { up = "back", down = "difficulty_easy", left = "size_9", right = "size_7" },
  size_7 = { up = "start", down = "difficulty_easy", left = "size_5", right = "size_9" },
  size_9 = { up = "start", down = "difficulty_hard", left = "size_7", right = "size_5" },
  difficulty_easy = { up = "size_5", down = "back", left = "difficulty_hard", right = "difficulty_hard" },
  difficulty_hard = { up = "size_9", down = "start", left = "difficulty_easy", right = "difficulty_easy" },
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

function Game.new()
  local self = setmetatable({}, Game)

  self.ai_delay = 0.45
  self.ai_timer = 0
  self.state = nil
  self.selected_board_size = 7
  self.board_size = 7
  self.selected_bot_difficulty = "hard"
  self.bot_difficulty = "hard"
  self.cursor_cell = nil
  self.menu_focus_index = nil
  self.screen = nil
  self:set_screen("main_menu")

  return self
end

function Game:start_game(board_size, bot_difficulty)
  local size = board_size or self.selected_board_size or 7
  local difficulty = bot_difficulty or self.selected_bot_difficulty or "hard"
  self.selected_board_size = size
  self.selected_bot_difficulty = difficulty
  self.board_size = size
  self.bot_difficulty = difficulty
  self.state = rules.resolve_state(level.load(size))
  self:set_screen("playing")
  self.ai_timer = 0
  self.cursor_cell = find_first_player_cell(self.state)
end

function Game:restart()
  if self.screen ~= "playing" then
    return
  end

  self.state = rules.resolve_state(level.load(self.board_size))
  self.ai_timer = 0
  self.cursor_cell = find_first_player_cell(self.state)
end

function Game:commit_move(move)
  self.state = rules.resolve_state(rules.apply_move(self.state, move))
  self.ai_timer = 0
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

function Game:set_screen(screen)
  self.screen = screen

  if screen == "playing" then
    self.menu_focus_index = nil
    return
  end

  self.menu_focus_index = self:default_menu_focus_index(screen)
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
  end
end

function Game:activate_focused_menu_button()
  local button_id = self:get_focused_menu_button_id()

  if not button_id then
    return
  end

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
  local button_id, button_index = self:find_clicked_button(ui.buttons, x, y)

  if not button_id then
    return
  end

  self.menu_focus_index = button_index
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
  local button_id, button_index = self:find_clicked_button(ui.buttons, x, y)

  if not button_id then
    return
  end

  self.menu_focus_index = button_index
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

  self.cursor_cell = { x = next_x, y = next_y }
end

function Game:activate_cursor_cell()
  if self.screen ~= "playing" or not self.state or not self.cursor_cell then
    return
  end

  if self.state.winner or self.state.current_player ~= "player" then
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
    end
  else
    self.state.selected_cell = nil
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
    self.state = rules.resolve_state(self.state)
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

  self.state = rules.resolve_state(self.state)
  self.ai_timer = 0
end

function Game:update(dt)
  if self.screen ~= "playing" or not self.state then
    return
  end

  self:resolve_forced_pass()

  if self.state.winner then
    return
  end

  if self.state.current_player == "enemy" then
    self.ai_timer = self.ai_timer + dt

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
    end
  else
    self.state.selected_cell = nil
  end
end

function Game:keypressed(key)
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
    self.ai_timer = 0
    self.cursor_cell = nil
  end
end

function Game:draw()
  if self.screen == "main_menu" then
    render.draw_main_menu(self:get_focused_menu_button_id())
    return
  end

  if self.screen == "play_menu" then
    render.draw_play_menu(
      self.selected_board_size,
      self.selected_bot_difficulty,
      self:get_focused_menu_button_id()
    )
    return
  end

  if self.state then
    render.draw(self.state, {
      cursor_cell = self.cursor_cell,
    })
  end
end

return Game
