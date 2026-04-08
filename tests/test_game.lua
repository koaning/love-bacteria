local board = require("src.board")
local Game = require("src.game")
local rules = require("src.rules")

local Tests = {}

local function assert_equal(actual, expected, message)
  if actual ~= expected then
    error((message or "Values are not equal") .. ": expected " .. tostring(expected) .. ", got " .. tostring(actual), 2)
  end
end

local function assert_truthy(value, message)
  if not value then
    error(message or "Expected truthy value", 2)
  end
end

local function fill_board(state, side)
  for y = 1, state.height do
    for x = 1, state.width do
      board.set_cell(state, x, y, side)
    end
  end
end

local function blocked_player_state()
  local state = board.new_state(7, 7)
  fill_board(state, "enemy")
  board.set_cell(state, 1, 1, "player")
  board.set_cell(state, 7, 7, "empty")
  board.set_cell(state, 7, 6, "empty")
  board.set_cell(state, 6, 7, "empty")
  state.current_player = "player"
  return state
end

function Tests.update_auto_passes_blocked_player_without_input()
  local game = Game.new()
  game.ai_delay = 999
  game.state = blocked_player_state()
  game.screen = "playing"

  game:update(0)

  assert_equal(game.state.current_player, "enemy", "Update should auto-pass to enemy")
  assert_equal(#rules.get_legal_moves(game.state, "player"), 0, "Player should still be blocked")
end

function Tests.enemy_keeps_turn_when_player_remains_blocked()
  local game = Game.new()
  game.ai_delay = 0
  game.state = blocked_player_state()
  game.screen = "playing"

  game:update(0)

  assert_truthy(game.state.last_move, "Enemy should make a move after player pass")
  assert_equal(game.state.current_player, "enemy", "Turn should remain with enemy if player is still blocked")
  assert_equal(#rules.get_legal_moves(game.state, "player"), 0, "Player should still have no moves")
end

function Tests.start_game_uses_selected_board_size()
  local game = Game.new()

  game:start_game(5)
  assert_equal(game.screen, "playing", "Start game should enter playing screen")
  assert_equal(game.state.width, 5, "Board width should match configured size")
  assert_equal(game.state.height, 5, "Board height should match configured size")

  game:start_game(9)
  assert_equal(game.state.width, 9, "Board width should update to new configured size")
  assert_equal(game.state.height, 9, "Board height should update to new configured size")
end

return Tests
