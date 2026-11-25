local board = require("src.board")

local Rules = {}

local ADJACENT_OFFSETS = {
  { x = -1, y = -1 },
  { x = 0, y = -1 },
  { x = 1, y = -1 },
  { x = -1, y = 0 },
  { x = 1, y = 0 },
  { x = -1, y = 1 },
  { x = 0, y = 1 },
  { x = 1, y = 1 },
}

local JUMP_OFFSETS = {
  { x = 0, y = -2 },
  { x = 2, y = 0 },
  { x = 0, y = 2 },
  { x = -2, y = 0 },
}

local function other_side(side)
  if side == "player" then
    return "enemy"
  end

  return "player"
end

local function side_label(side)
  if side == "player" then
    return "Player"
  end

  return "Enemy"
end

local function add_move(moves, kind, fx, fy, tx, ty)
  moves[#moves + 1] = {
    kind = kind,
    from = { x = fx, y = fy },
    to = { x = tx, y = ty },
  }
end

function Rules.get_piece_moves(state, side, x, y)
  local moves = {}

  if board.get_cell(state, x, y) ~= side then
    return moves
  end

  for _, offset in ipairs(ADJACENT_OFFSETS) do
    local nx = x + offset.x
    local ny = y + offset.y

    if board.get_cell(state, nx, ny) == "empty" then
      add_move(moves, "grow", x, y, nx, ny)
    end
  end

  for _, offset in ipairs(JUMP_OFFSETS) do
    local nx = x + offset.x
    local ny = y + offset.y

    if board.get_cell(state, nx, ny) == "empty" then
      add_move(moves, "jump", x, y, nx, ny)
    end
  end

  return moves
end

function Rules.get_legal_moves(state, side)
  local moves = {}

  for y = 1, state.height do
    for x = 1, state.width do
      if board.get_cell(state, x, y) == side then
        local piece_moves = Rules.get_piece_moves(state, side, x, y)
        for _, move in ipairs(piece_moves) do
          moves[#moves + 1] = move
        end
      end
    end
  end

  return moves
end

function Rules.find_move(state, side, from_cell, to_cell)
  local piece_moves = Rules.get_piece_moves(state, side, from_cell.x, from_cell.y)

  for _, move in ipairs(piece_moves) do
    if move.to.x == to_cell.x and move.to.y == to_cell.y then
      return move
    end
  end

  return nil
end

function Rules.is_move_legal(state, side, move)
  local legal = Rules.find_move(state, side, move.from, move.to)

  if not legal then
    return false
  end

  return legal.kind == move.kind
end

function Rules.apply_move(state, move)
  local side = state.current_player

  if not Rules.is_move_legal(state, side, move) then
    return board.clone_state(state)
  end

  local next_state = board.clone_state(state)
  local enemy = other_side(side)
  local converted = 0

  next_state.selected_cell = nil
  next_state.winner = nil

  if move.kind == "jump" then
    board.set_cell(next_state, move.from.x, move.from.y, "empty")
  end

  board.set_cell(next_state, move.to.x, move.to.y, side)

  for _, offset in ipairs(ADJACENT_OFFSETS) do
    local nx = move.to.x + offset.x
    local ny = move.to.y + offset.y

    if board.get_cell(next_state, nx, ny) == enemy then
      board.set_cell(next_state, nx, ny, side)
      converted = converted + 1
    end
  end

  next_state.last_move = {
    kind = move.kind,
    converted = converted,
    from = { x = move.from.x, y = move.from.y },
    to = { x = move.to.x, y = move.to.y },
  }
  next_state.current_player = enemy
  next_state.pass_count = 0
  next_state.status_text = nil

  return next_state
end

function Rules.get_winner(state)
  local player_count = board.count_cells(state, "player")
  local enemy_count = board.count_cells(state, "enemy")

  if player_count == 0 and enemy_count == 0 then
    return "tie"
  end

  if player_count == 0 then
    return "enemy"
  end

  if enemy_count == 0 then
    return "player"
  end

  local player_moves = Rules.get_legal_moves(state, "player")
  local enemy_moves = Rules.get_legal_moves(state, "enemy")

  if #player_moves == 0 and #enemy_moves == 0 then
    if player_count > enemy_count then
      return "player"
    end

    if enemy_count > player_count then
      return "enemy"
    end

    return "tie"
  end

  return nil
end

local function winner_message(state, winner)
  local player_count = board.count_cells(state, "player")
  local enemy_count = board.count_cells(state, "enemy")

  if winner == "tie" then
    return "No legal moves remain. The board ends in a tie."
  end

  if winner == "player" then
    if enemy_count == 0 then
      return "Enemy bacteria were eliminated."
    end

    return "Player controls more of the board."
  end

  if player_count == 0 then
    return "Player bacteria were eliminated."
  end

  return "Enemy controls more of the board."
end

function Rules.resolve_state(state)
  local next_state = board.clone_state(state)
  local winner = Rules.get_winner(next_state)

  next_state.selected_cell = nil

  if winner then
    next_state.winner = winner
    next_state.status_text = winner_message(next_state, winner)
    return next_state
  end

  local active_side = next_state.current_player
  local active_moves = Rules.get_legal_moves(next_state, active_side)

  if #active_moves > 0 then
    next_state.pass_count = 0
    next_state.status_text = side_label(active_side) .. " turn."
    return next_state
  end

  next_state.pass_count = (next_state.pass_count or 0) + 1
  next_state.current_player = other_side(active_side)
  next_state.status_text = side_label(active_side) .. " has no legal moves and passes."

  winner = Rules.get_winner(next_state)

  if winner then
    next_state.winner = winner
    next_state.status_text = winner_message(next_state, winner)
    return next_state
  end

  return next_state
end

return Rules
