local ai = require("src.ai")
local board = require("src.board")
local input = require("src.input")
local level = require("src.level")
local render = require("src.render")
local rules = require("src.rules")

local Game = {}
Game.__index = Game

function Game.new()
  local self = setmetatable({}, Game)

  self.ai_delay = 0.45
  self.ai_timer = 0
  self.state = rules.resolve_state(level.load())

  return self
end

function Game:restart()
  self.state = rules.resolve_state(level.load())
  self.ai_timer = 0
end

function Game:commit_move(move)
  self.state = rules.resolve_state(rules.apply_move(self.state, move))
  self.ai_timer = 0
end

function Game:run_enemy_turn()
  if self.state.winner or self.state.current_player ~= "enemy" then
    return
  end

  local move = ai.choose_move(self.state, "enemy")

  if not move then
    self.state = rules.resolve_state(self.state)
    self.ai_timer = 0
    return
  end

  self:commit_move(move)
end

function Game:resolve_forced_pass()
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
  if input.is_restart_key(key) then
    self:restart()
    return
  end

  if input.is_quit_key(key) then
    love.event.quit()
  end
end

function Game:draw()
  render.draw(self.state)
end

return Game
