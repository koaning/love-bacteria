local board = require("src.board")
local rules = require("src.rules")

local AI = {}

local HARD_SEARCH_DEPTH = 2
local INFINITY = math.huge
local WIN_SCORE = 100000

function AI.state_hash(state)
  if not state then
    return nil
  end

  local parts = {}

  for y = 1, state.height do
    for x = 1, state.width do
      local cell = board.get_cell(state, x, y)

      if cell == "player" then
        parts[#parts + 1] = "P"
      elseif cell == "enemy" then
        parts[#parts + 1] = "E"
      else
        parts[#parts + 1] = "."
      end
    end
  end

  parts[#parts + 1] = ":"
  parts[#parts + 1] = state.current_player or "?"

  return table.concat(parts)
end

local function hash_in_history(history, hash)
  if not history then
    return false
  end

  for _, entry in ipairs(history) do
    if entry == hash then
      return true
    end
  end

  return false
end

local function filter_non_repeating(state, legal_moves, history)
  if not history or #history == 0 then
    return legal_moves
  end

  local kept = {}

  for _, move in ipairs(legal_moves) do
    local next_state = rules.resolve_state(rules.apply_move(state, move))

    if not hash_in_history(history, AI.state_hash(next_state)) then
      kept[#kept + 1] = move
    end
  end

  if #kept == 0 then
    return legal_moves
  end

  return kept
end

local function other_side(side)
  if side == "player" then
    return "enemy"
  end

  return "player"
end

local function center_bonus(x, y, width, height)
  local center_x = (width + 1) / 2
  local center_y = (height + 1) / 2
  local distance = math.abs(x - center_x) + math.abs(y - center_y)

  return 8 - distance
end

local function compare_moves(candidate_move, candidate_score, best_move, best_score)
  if not best_move then
    return true
  end

  if candidate_score ~= best_score then
    return candidate_score > best_score
  end

  if candidate_move.kind ~= best_move.kind then
    return candidate_move.kind == "grow"
  end

  if candidate_move.to.y ~= best_move.to.y then
    return candidate_move.to.y < best_move.to.y
  end

  if candidate_move.to.x ~= best_move.to.x then
    return candidate_move.to.x < best_move.to.x
  end

  if candidate_move.from.y ~= best_move.from.y then
    return candidate_move.from.y < best_move.from.y
  end

  return candidate_move.from.x < best_move.from.x
end

local function evaluate_state(state, perspective)
  local opponent = other_side(perspective)

  if state.winner == perspective then
    return WIN_SCORE
  end

  if state.winner == opponent then
    return -WIN_SCORE
  end

  if state.winner == "tie" then
    return 0
  end

  local my_count = board.count_cells(state, perspective)
  local their_count = board.count_cells(state, opponent)
  local my_moves = #rules.get_legal_moves(state, perspective)
  local their_moves = #rules.get_legal_moves(state, opponent)

  return ((my_count - their_count) * 8)
    + (my_moves * 5)
    - (their_moves * 6)
end

local function score_move(state, side, move)
  local opponent = other_side(side)
  local simulated = rules.resolve_state(rules.apply_move(state, move))
  local converted = 0

  if simulated.last_move then
    converted = simulated.last_move.converted or 0
  end

  if simulated.winner == side then
    return WIN_SCORE + converted
  end

  if simulated.winner == opponent then
    return -WIN_SCORE
  end

  local my_count = board.count_cells(simulated, side)
  local their_count = board.count_cells(simulated, opponent)
  local my_moves = #rules.get_legal_moves(simulated, side)
  local their_moves = #rules.get_legal_moves(simulated, opponent)

  return (converted * 100)
    + ((my_count - their_count) * 8)
    + (my_moves * 5)
    - (their_moves * 6)
    + center_bonus(move.to.x, move.to.y, state.width, state.height)
end

local function random_index(maximum)
  if love and love.math and love.math.random then
    return love.math.random(maximum)
  end

  return math.random(maximum)
end

local function choose_best_move(state, side, legal_moves)
  local best_move = nil
  local best_score = nil

  for _, move in ipairs(legal_moves) do
    local score = score_move(state, side, move)

    if compare_moves(move, score, best_move, best_score) then
      best_move = move
      best_score = score
    end
  end

  return best_move
end

local function minimax_score(state, perspective, depth, alpha, beta)
  if state.winner or depth == 0 then
    return evaluate_state(state, perspective)
  end

  local current_side = state.current_player
  local legal_moves = rules.get_legal_moves(state, current_side)

  if #legal_moves == 0 then
    return evaluate_state(state, perspective)
  end

  if current_side == perspective then
    local best = -INFINITY

    for _, move in ipairs(legal_moves) do
      local next_state = rules.resolve_state(rules.apply_move(state, move))
      local score = minimax_score(next_state, perspective, depth - 1, alpha, beta)

      if score > best then
        best = score
      end

      if best > alpha then
        alpha = best
      end

      if alpha >= beta then
        break
      end
    end

    return best
  end

  local best = INFINITY

  for _, move in ipairs(legal_moves) do
    local next_state = rules.resolve_state(rules.apply_move(state, move))
    local score = minimax_score(next_state, perspective, depth - 1, alpha, beta)

    if score < best then
      best = score
    end

    if best < beta then
      beta = best
    end

    if alpha >= beta then
      break
    end
  end

  return best
end

local function choose_lookahead_move(state, side, legal_moves, depth)
  local best_move = nil
  local best_score = nil

  for _, move in ipairs(legal_moves) do
    local next_state = rules.resolve_state(rules.apply_move(state, move))
    local score = minimax_score(next_state, side, depth - 1, -INFINITY, INFINITY)

    if compare_moves(move, score, best_move, best_score) then
      best_move = move
      best_score = score
    end
  end

  return best_move
end

function AI.choose_move(state, side, difficulty, history)
  local legal_moves = rules.get_legal_moves(state, side)
  local bot_difficulty = difficulty or "hard"

  if #legal_moves == 0 then
    return nil
  end

  legal_moves = filter_non_repeating(state, legal_moves, history)

  if bot_difficulty == "easy" then
    local grow_moves = {}

    for _, move in ipairs(legal_moves) do
      if move.kind == "grow" then
        grow_moves[#grow_moves + 1] = move
      end
    end

    if #grow_moves > 0 then
      return grow_moves[random_index(#grow_moves)]
    end

    return legal_moves[random_index(#legal_moves)]
  end

  if bot_difficulty == "medium" then
    local best_move = choose_best_move(state, side, legal_moves)

    if random_index(3) == 1 then
      return legal_moves[random_index(#legal_moves)]
    end

    return best_move
  end

  return choose_lookahead_move(state, side, legal_moves, HARD_SEARCH_DEPTH)
end

return AI
