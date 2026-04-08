local ai = require("src.ai")
local board = require("src.board")
local level = require("src.level")
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

local function move_exists(moves, candidate)
  for _, move in ipairs(moves) do
    if move.kind == candidate.kind
      and move.from.x == candidate.from.x
      and move.from.y == candidate.from.y
      and move.to.x == candidate.to.x
      and move.to.y == candidate.to.y then
      return true
    end
  end

  return false
end

function Tests.easy_bot_returns_legal_move()
  local state = level.load(7)
  state.current_player = "enemy"
  local legal_moves = rules.get_legal_moves(state, "enemy")
  local move = ai.choose_move(state, "enemy", "easy")

  assert_truthy(move, "Easy bot should pick a move when legal moves exist")
  assert_equal(move_exists(legal_moves, move), true, "Easy bot move should be legal")
end

function Tests.easy_bot_prefers_grow_moves()
  local state = level.load(7)
  state.current_player = "enemy"
  local move = ai.choose_move(state, "enemy", "easy")

  assert_equal(move.kind, "grow", "Easy bot should choose grow when grow moves are available")
end

function Tests.hard_bot_returns_legal_move()
  local state = level.load(7)
  state.current_player = "enemy"
  local legal_moves = rules.get_legal_moves(state, "enemy")
  local move = ai.choose_move(state, "enemy", "hard")

  assert_truthy(move, "Hard bot should pick a move when legal moves exist")
  assert_equal(move_exists(legal_moves, move), true, "Hard bot move should be legal")
end

function Tests.choose_move_returns_nil_without_legal_moves()
  local state = board.new_state(3, 3)

  for y = 1, state.height do
    for x = 1, state.width do
      board.set_cell(state, x, y, "enemy")
    end
  end

  state.current_player = "enemy"

  assert_equal(ai.choose_move(state, "enemy", "easy"), nil, "Easy bot should return nil when no moves exist")
  assert_equal(ai.choose_move(state, "enemy", "hard"), nil, "Hard bot should return nil when no moves exist")
end

return Tests
