local ai = require("src.ai")
local board = require("src.board")
local input = require("src.input")
local level = require("src.level")
local render = require("src.render")
local rules = require("src.rules")

local Game = {}
Game.__index = Game

local RESOLUTION_OPTIONS = {
  { id = "res_700_700", width = 700, height = 700 },
  { id = "res_840_760", width = 840, height = 760 },
  { id = "res_960_800", width = 960, height = 800 },
}
local DEFAULT_RESOLUTION_ID = "res_840_760"

local function point_in_rect(x, y, rect)
  return x >= rect.x
    and x <= rect.x + rect.width
    and y >= rect.y
    and y <= rect.y + rect.height
end

local function find_resolution_option(id)
  for _, option in ipairs(RESOLUTION_OPTIONS) do
    if option.id == id then
      return option
    end
  end

  return nil
end

function Game.new()
  local self = setmetatable({}, Game)

  self.ai_delay = 0.45
  self.ai_timer = 0
  self.state = nil
  self.screen = "main_menu"
  self.selected_board_size = 7
  self.board_size = 7
  self.selected_bot_difficulty = "hard"
  self.bot_difficulty = "hard"
  self.selected_resolution_id = DEFAULT_RESOLUTION_ID

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
  self.screen = "playing"
  self.ai_timer = 0
end

function Game:apply_resolution(option_id)
  local option = find_resolution_option(option_id)

  if not option then
    return false
  end

  if love and love.window and love.window.setMode then
    local ok = love.window.setMode(option.width, option.height, {
      resizable = false,
      vsync = 1,
      msaa = 4,
    })

    if not ok then
      return false
    end
  end

  self.selected_resolution_id = option.id
  return true
end

function Game:restart()
  if self.screen ~= "playing" then
    return
  end

  self.state = rules.resolve_state(level.load(self.board_size))
  self.ai_timer = 0
end

function Game:commit_move(move)
  self.state = rules.resolve_state(rules.apply_move(self.state, move))
  self.ai_timer = 0
end

function Game:find_clicked_button(buttons, x, y)
  for _, button in ipairs(buttons) do
    if point_in_rect(x, y, button) then
      return button.id
    end
  end

  return nil
end

function Game:handle_main_menu_click(x, y)
  local width, height = love.graphics.getDimensions()
  local ui = render.get_main_menu_ui(width, height)
  local button_id = self:find_clicked_button(ui.buttons, x, y)

  if button_id == "play" then
    self.screen = "play_menu"
    return
  end

  if button_id == "settings" then
    self.screen = "settings_menu"
    return
  end

  if button_id == "quit" then
    love.event.quit()
  end
end

function Game:handle_play_menu_click(x, y)
  local width, height = love.graphics.getDimensions()
  local ui = render.get_play_menu_ui(width, height)
  local button_id = self:find_clicked_button(ui.buttons, x, y)

  if button_id == "size_5" then
    self.selected_board_size = 5
    return
  end

  if button_id == "size_7" then
    self.selected_board_size = 7
    return
  end

  if button_id == "size_9" then
    self.selected_board_size = 9
    return
  end

  if button_id == "difficulty_easy" then
    self.selected_bot_difficulty = "easy"
    return
  end

  if button_id == "difficulty_hard" then
    self.selected_bot_difficulty = "hard"
    return
  end

  if button_id == "back" then
    self.screen = "main_menu"
    return
  end

  if button_id == "start" then
    self:start_game(self.selected_board_size, self.selected_bot_difficulty)
  end
end

function Game:handle_settings_menu_click(x, y)
  local width, height = love.graphics.getDimensions()
  local ui = render.get_settings_menu_ui(width, height)
  local button_id = self:find_clicked_button(ui.buttons, x, y)

  if not button_id then
    return
  end

  if button_id == "back" then
    self.screen = "main_menu"
    return
  end

  self:apply_resolution(button_id)
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

  if self.screen == "settings_menu" then
    self:handle_settings_menu_click(x, y)
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
    if input.is_quit_key(key) then
      love.event.quit()
    end
    return
  end

  if self.screen == "play_menu" then
    if input.is_quit_key(key) then
      self.screen = "main_menu"
    end
    return
  end

  if self.screen == "settings_menu" then
    if input.is_quit_key(key) then
      self.screen = "main_menu"
    end
    return
  end

  if input.is_restart_key(key) then
    self:restart()
    return
  end

  if input.is_quit_key(key) then
    self.screen = "main_menu"
    self.state = nil
    self.ai_timer = 0
  end
end

function Game:draw()
  if self.screen == "main_menu" then
    render.draw_main_menu()
    return
  end

  if self.screen == "play_menu" then
    render.draw_play_menu(self.selected_board_size, self.selected_bot_difficulty)
    return
  end

  if self.screen == "settings_menu" then
    render.draw_settings_menu(self.selected_resolution_id)
    return
  end

  if self.state then
    render.draw(self.state)
  end
end

return Game
