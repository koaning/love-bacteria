-- rules.lua
-- legal moves, conversion, automatic passing, and win detection.

function other_side(side)
  if side == "player" then
    return "enemy"
  end

  return "player"
end

-- the first 8 offsets grow, the last 4 jump.
local move_offsets = {
  { x = -1, y = -1 },
  { x = 0, y = -1 },
  { x = 1, y = -1 },
  { x = -1, y = 0 },
  { x = 1, y = 0 },
  { x = -1, y = 1 },
  { x = 0, y = 1 },
  { x = 1, y = 1 },
  { x = 0, y = -2 },
  { x = 2, y = 0 },
  { x = 0, y = 2 },
  { x = -2, y = 0 },
}

function rules_get_piece_moves(state, side, x, y)
  local moves = {}

  if board_get_cell(state, x, y) == side then
    for i = 1, 12 do
      local o = move_offsets[i]
      local nx = x + o.x
      local ny = y + o.y

      if board_get_cell(state, nx, ny) == "empty" then
        add(moves, {
          kind = i > 8 and "jump" or "grow",
          from = { x = x, y = y },
          to = { x = nx, y = ny },
        })
      end
    end
  end

  return moves
end

-- growing into a cell gives the same board whichever piece
-- grows, so only the first grow per target cell is listed.
function rules_get_legal_moves(state, side)
  local moves = {}
  local seen = {}

  for y = 1, state.height do
    for x = 1, state.width do
      for move in all(rules_get_piece_moves(state, side, x, y)) do
        -- jumps key on themselves, so they are never dropped
        local k = move.kind == "grow" and move.to.y * 8 + move.to.x or move

        if not seen[k] then
          seen[k] = 1
          add(moves, move)
        end
      end
    end
  end

  return moves
end

-- mobility (every grow and jump) for both sides in one pass,
-- cached on the state; board_set_cell() clears the cache.
function rules_count_moves(state, side)
  local n = state.mob

  if not n then
    n = { player = 0, enemy = 0 }

    for y = 1, state.height do
      for x = 1, state.width do
        local c = state.cells[y][x]

        if c ~= "empty" then
          for o in all(move_offsets) do
            local row = state.cells[y + o.y]

            if row and row[x + o.x] == "empty" then
              n[c] = n[c] + 1
            end
          end
        end
      end
    end

    state.mob = n
  end

  return n[side]
end

function rules_find_move(state, side, from_cell, to_cell)
  for move in all(rules_get_piece_moves(state, side, from_cell.x, from_cell.y)) do
    if move.to.x == to_cell.x and move.to.y == to_cell.y then
      return move
    end
  end

  return nil
end

function rules_is_move_legal(state, side, move)
  local legal = rules_find_move(state, side, move.from, move.to)

  if not legal then
    return false
  end

  return legal.kind == move.kind
end

function rules_apply_move(state, move)
  local side = state.current_player

  if not rules_is_move_legal(state, side, move) then
    return board_clone_state(state)
  end

  local next_state = board_clone_state(state)
  local enemy = other_side(side)
  local converted = 0

  next_state.winner = nil

  if move.kind == "jump" then
    board_set_cell(next_state, move.from.x, move.from.y, "empty")
  end

  board_set_cell(next_state, move.to.x, move.to.y, side)

  for i = 1, 8 do
    local nx = move.to.x + move_offsets[i].x
    local ny = move.to.y + move_offsets[i].y

    if board_get_cell(next_state, nx, ny) == enemy then
      board_set_cell(next_state, nx, ny, side)
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

  return next_state
end

function rules_get_winner(state)
  local player_count = board_count_cells(state, "player")
  local enemy_count = board_count_cells(state, "enemy")

  if player_count == 0 and enemy_count == 0 then
    return "tie"
  end

  if player_count == 0 then
    return "enemy"
  end

  if enemy_count == 0 then
    return "player"
  end

  if rules_count_moves(state, "player") + rules_count_moves(state, "enemy") == 0 then
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

-- updates state in place (callers pass a fresh state) and returns it.
function rules_resolve_state(state)
  local next_state = state
  local winner = rules_get_winner(next_state)

  if winner then
    next_state.winner = winner
    return next_state
  end

  local active_side = next_state.current_player

  if rules_count_moves(next_state, active_side) > 0 then
    next_state.pass_count = 0
    return next_state
  end

  next_state.pass_count = (next_state.pass_count or 0) + 1
  next_state.current_player = other_side(active_side)

  winner = rules_get_winner(next_state)

  if winner then
    next_state.winner = winner
  end

  return next_state
end
