-- ai.lua
-- easy / medium / hard bots for mossballs.
--
-- pico-8 notes:
--   * numbers are 16.16 fixed point, so scores stay < 32768
--   * abs()/rnd()/flr()/add()/all() instead of math./table.
--   * ai_tick() is called in the hot loops so the cart can
--     yield() from a coroutine and keep animating while the
--     bot thinks. the test sandbox makes it a no-op.

local infinity = 32000
local win_score = 10000

function ai_state_hash(state)
  if not state then
    return nil
  end

  local s = ""

  for y = 1, state.height do
    for x = 1, state.width do
      local cell = board_get_cell(state, x, y)

      if cell == "player" then
        s = s .. "P"
      elseif cell == "enemy" then
        s = s .. "E"
      else
        s = s .. "."
      end
    end
  end

  return s .. ":" .. (state.current_player or "?")
end

local function hash_in_history(history, hash)
  if not history then
    return false
  end

  for entry in all(history) do
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

  for move in all(legal_moves) do
    ai_tick()
    local next_state = rules_resolve_state(rules_apply_move(state, move))

    if not hash_in_history(history, ai_state_hash(next_state)) then
      add(kept, move)
    end
  end

  if #kept == 0 then
    return legal_moves
  end

  return kept
end

local function center_bonus(x, y, width, height)
  local center_x = (width + 1) / 2
  local center_y = (height + 1) / 2
  local distance = abs(x - center_x) + abs(y - center_y)

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
    return win_score
  end

  if state.winner == opponent then
    return -win_score
  end

  if state.winner == "tie" then
    return 0
  end

  local my_count = board_count_cells(state, perspective)
  local their_count = board_count_cells(state, opponent)
  local my_moves = rules_count_moves(state, perspective)
  local their_moves = rules_count_moves(state, opponent)

  return ((my_count - their_count) * 8)
    + (my_moves * 5)
    - (their_moves * 6)
end

function ai_score_move(state, side, move)
  local opponent = other_side(side)
  local simulated = rules_resolve_state(rules_apply_move(state, move))
  local converted = 0

  if simulated.last_move then
    converted = simulated.last_move.converted or 0
  end

  if simulated.winner == side then
    return win_score + converted
  end

  if simulated.winner == opponent then
    return -win_score
  end

  local my_count = board_count_cells(simulated, side)
  local their_count = board_count_cells(simulated, opponent)
  local my_moves = rules_count_moves(simulated, side)
  local their_moves = rules_count_moves(simulated, opponent)

  return (converted * 100)
    + ((my_count - their_count) * 8)
    + (my_moves * 5)
    - (their_moves * 6)
    + center_bonus(move.to.x, move.to.y, state.width, state.height)
end

local function random_index(maximum)
  return flr(rnd(maximum)) + 1
end

local function choose_best_move(state, side, legal_moves)
  local best_move = nil
  local best_score = nil

  for move in all(legal_moves) do
    ai_tick()
    local score = ai_score_move(state, side, move)

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
  local legal_moves = rules_get_legal_moves(state, current_side)

  if #legal_moves == 0 then
    return evaluate_state(state, perspective)
  end

  local maxing = current_side == perspective
  local best = maxing and -infinity or infinity

  for move in all(legal_moves) do
    ai_tick()
    local score = minimax_score(rules_resolve_state(rules_apply_move(state, move)), perspective, depth - 1, alpha, beta)

    if maxing then
      best = max(best, score)
      alpha = max(alpha, best)
    else
      best = min(best, score)
      beta = min(beta, best)
    end

    if alpha >= beta then
      break
    end
  end

  return best
end

-- 2-ply search. each root move only has to beat the best so far,
-- so replies that already refute it are cut off (alpha = best - 1
-- keeps exact scores for ties; scores are whole numbers).
local function choose_lookahead_move(state, side, legal_moves)
  local best_move = nil
  local best_score = nil

  for move in all(legal_moves) do
    local next_state = rules_resolve_state(rules_apply_move(state, move))
    local score = minimax_score(next_state, side, 1, best_score and best_score - 1 or -infinity, infinity)

    if compare_moves(move, score, best_move, best_score) then
      best_move = move
      best_score = score
    end
  end

  return best_move
end

function ai_choose_move(state, side, difficulty, history)
  local legal_moves = rules_get_legal_moves(state, side)
  local bot_difficulty = difficulty or "hard"

  if #legal_moves == 0 then
    return nil
  end

  legal_moves = filter_non_repeating(state, legal_moves, history)

  if bot_difficulty == "easy" then
    local grow_moves = {}

    for move in all(legal_moves) do
      if move.kind == "grow" then
        add(grow_moves, move)
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

  return choose_lookahead_move(state, side, legal_moves)
end
