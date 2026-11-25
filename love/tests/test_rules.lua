local board = require("src.board")
local rules = require("src.rules")

local Tests = {}

local function assert_equal(actual, expected, message)
  if actual ~= expected then
    error((message or "Values are not equal") .. ": expected " .. tostring(expected) .. ", got " .. tostring(actual), 2)
  end
end

local function fill_board(state, side)
  for y = 1, state.height do
    for x = 1, state.width do
      board.set_cell(state, x, y, side)
    end
  end
end

function Tests.resolve_state_passes_when_active_side_is_stuck()
  local state = board.new_state(7, 7)
  fill_board(state, "enemy")
  board.set_cell(state, 1, 1, "player")
  board.set_cell(state, 7, 7, "empty")
  board.set_cell(state, 7, 6, "empty")
  board.set_cell(state, 6, 7, "empty")
  state.current_player = "player"

  local resolved = rules.resolve_state(state)

  assert_equal(resolved.current_player, "enemy", "Stuck player should pass to enemy")
  assert_equal(resolved.winner, nil, "Game should continue when enemy still has moves")
  assert_equal(#rules.get_legal_moves(resolved, "player"), 0, "Player should still have no legal moves")
end

function Tests.resolve_state_declares_winner_when_both_sides_are_stuck()
  local state = board.new_state(3, 3)
  fill_board(state, "enemy")
  board.set_cell(state, 1, 1, "player")
  state.current_player = "player"

  local resolved = rules.resolve_state(state)

  assert_equal(resolved.winner, "enemy", "Enemy should win on piece count when no legal moves remain")
end

return Tests
