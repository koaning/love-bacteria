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

local function score_move_one_ply(state, side, move)
  local opponent = side == "player" and "enemy" or "player"
  local simulated = rules.resolve_state(rules.apply_move(state, move))
  local converted = (simulated.last_move and simulated.last_move.converted) or 0

  if simulated.winner == side then
    return 100000 + converted
  end
  if simulated.winner == opponent then
    return -100000
  end

  local my_count = board.count_cells(simulated, side)
  local their_count = board.count_cells(simulated, opponent)
  local my_moves = #rules.get_legal_moves(simulated, side)
  local their_moves = #rules.get_legal_moves(simulated, opponent)

  return (converted * 100)
    + ((my_count - their_count) * 8)
    + (my_moves * 5)
    - (their_moves * 6)
end

local function greedy_one_ply_move(state, side)
  local legal_moves = rules.get_legal_moves(state, side)
  local best_move = nil
  local best_score = nil

  for _, move in ipairs(legal_moves) do
    local score = score_move_one_ply(state, side, move)
    if best_move == nil or score > best_score then
      best_move = move
      best_score = score
    end
  end

  return best_move
end

function Tests.hard_bot_looks_beyond_one_ply()
  -- Constructed 7x7 position reached after two plies of hard self-play
  -- from the default opening. Enemy to move from (6,2). The 1-ply
  -- greedy heuristic picks grow (6,2)->(5,3); 2-ply lookahead picks
  -- (6,2)->(6,3) because it values what the player can do in response.
  local state = board.new_state(7, 7)
  board.set_cell(state, 1, 1, "player")
  board.set_cell(state, 7, 1, "enemy")
  board.set_cell(state, 2, 2, "player")
  board.set_cell(state, 6, 2, "enemy")
  board.set_cell(state, 1, 7, "enemy")
  board.set_cell(state, 7, 7, "player")
  state.current_player = "enemy"

  local greedy = greedy_one_ply_move(state, "enemy")
  local hard = ai.choose_move(state, "enemy", "hard")

  assert_truthy(greedy, "1-ply greedy should return a move")
  assert_truthy(hard, "Hard bot should return a move")
  assert_equal(move_matches(greedy, hard), false, "Hard bot must look past one ply on this position")
end

function Tests.hard_bot_avoids_states_in_history()
  -- On the default 7x7 opening, capture Hard's preferred enemy move.
  -- Then ask again with that move's resulting state hashed into history.
  -- Hard must pick a different move to break the loop.
  local state = level.load(7)
  state.current_player = "enemy"

  local first_move = ai.choose_move(state, "enemy", "hard")
  assert_truthy(first_move, "Hard should return a move on the opening position")

  local resulting_state = rules.resolve_state(rules.apply_move(state, first_move))
  local history = { ai.state_hash(resulting_state) }

  local second_move = ai.choose_move(state, "enemy", "hard", history)
  assert_truthy(second_move, "Hard should still return a move when first choice is blocked by history")
  assert_equal(move_matches(first_move, second_move), false,
    "Hard must avoid producing a state already in history")
end

function Tests.bot_falls_back_when_every_move_repeats_history()
  -- If every legal move produces a state already in history, the AI must
  -- still return one of them (forced repeat) rather than nil.
  local state = level.load(7)
  state.current_player = "enemy"

  local legal_moves = rules.get_legal_moves(state, "enemy")
  local history = {}
  for _, move in ipairs(legal_moves) do
    local resulting_state = rules.resolve_state(rules.apply_move(state, move))
    history[#history + 1] = ai.state_hash(resulting_state)
  end

  local move = ai.choose_move(state, "enemy", "hard", history)
  assert_truthy(move, "AI must fall back to a legal move when history blocks every alternative")
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
