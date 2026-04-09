local board = require("src.board")
local rules = require("src.rules")

local AI = {}

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

local function score_move(state, side, move)
  local opponent = other_side(side)
  local simulated = rules.resolve_state(rules.apply_move(state, move))
  local converted = 0

  if simulated.last_move then
    converted = simulated.last_move.converted or 0
  end

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

function AI.choose_move(state, side, difficulty)
  local legal_moves = rules.get_legal_moves(state, side)
  local bot_difficulty = difficulty or "hard"

  if #legal_moves == 0 then
    return nil
  end

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

  local best_move = choose_best_move(state, side, legal_moves)

  if bot_difficulty == "medium" then
    if random_index(3) == 1 then
      return legal_moves[random_index(#legal_moves)]
    end

    return best_move
  end

  return best_move
end

return AI
