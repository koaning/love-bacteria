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

local function move_matches(a, b)
  return a.kind == b.kind
    and a.from.x == b.from.x
    and a.from.y == b.from.y
    and a.to.x == b.to.x
    and a.to.y == b.to.y
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

function Tests.medium_bot_returns_legal_move()
  local state = level.load(7)
  state.current_player = "enemy"
  local legal_moves = rules.get_legal_moves(state, "enemy")
  local move = ai.choose_move(state, "enemy", "medium")

  assert_truthy(move, "Medium bot should pick a move when legal moves exist")
  assert_equal(move_exists(legal_moves, move), true, "Medium bot move should be legal")
end

function Tests.medium_bot_can_choose_greedy_and_random_moves_over_runs()
  local state = level.load(7)
  state.current_player = "enemy"
  local legal_moves = rules.get_legal_moves(state, "enemy")
  local greedy_move = ai.choose_move(state, "enemy", "hard")
  local random_branch_move = nil
  local random_branch_index = nil

  for index, move in ipairs(legal_moves) do
    if not move_matches(move, greedy_move) then
      random_branch_move = move
      random_branch_index = index
      break
    end
  end

  assert_truthy(random_branch_move, "Expected at least one legal move that differs from greedy choice")

  local previous_love = love
  local sequence = {
    2,
    1, random_branch_index,
    2,
    1, random_branch_index,
  }
  local cursor = 0
  local saw_greedy = false
  local saw_random_style = false

  local ok, err = pcall(function()
    love = {
      math = {
        random = function(maximum)
          cursor = cursor + 1
          local value = sequence[cursor] or 2

          if value > maximum then
            return ((value - 1) % maximum) + 1
          end

          return value
        end,
      },
    }

    for _ = 1, 4 do
      local move = ai.choose_move(state, "enemy", "medium")
      if move_matches(move, greedy_move) then
        saw_greedy = true
      end
      if move_matches(move, random_branch_move) then
        saw_random_style = true
      end
    end
  end)

  love = previous_love

  if not ok then
    error(err, 2)
  end

  assert_equal(saw_greedy, true, "Medium bot should produce greedy outcome across repeated runs")
  assert_equal(saw_random_style, true, "Medium bot should produce random-style outcome across repeated runs")
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
  assert_equal(ai.choose_move(state, "enemy", "medium"), nil, "Medium bot should return nil when no moves exist")
  assert_equal(ai.choose_move(state, "enemy", "hard"), nil, "Hard bot should return nil when no moves exist")
end

return Tests
