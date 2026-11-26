-- board.lua
-- written in the lua subset that both pico-8 and luajit accept
-- (no +=, no !=, no ?, no math./table./string.) so the test
-- suite can run it on a desktop.

function board_new_state(width, height)
  local cells = {}

  for y = 1, height do
    cells[y] = {}
    for x = 1, width do
      cells[y][x] = "empty"
    end
  end

  return {
    width = width,
    height = height,
    cells = cells,
    current_player = "player",
    winner = nil,
    pass_count = 0,
    last_move = nil,
  }
end

function board_in_bounds(state, x, y)
  return x >= 1 and x <= state.width and y >= 1 and y <= state.height
end

function board_get_cell(state, x, y)
  if not board_in_bounds(state, x, y) then
    return nil
  end

  return state.cells[y][x]
end

function board_set_cell(state, x, y, value)
  if board_in_bounds(state, x, y) then
    state.cells[y][x] = value
  end
end

function board_count_cells(state, side)
  local total = 0

  for y = 1, state.height do
    for x = 1, state.width do
      if state.cells[y][x] == side then
        total = total + 1
      end
    end
  end

  return total
end

function board_clone_state(state)
  local cells = {}

  for y = 1, state.height do
    cells[y] = {}
    for x = 1, state.width do
      cells[y][x] = state.cells[y][x]
    end
  end

  local copy = {
    width = state.width,
    height = state.height,
    cells = cells,
    current_player = state.current_player,
    winner = state.winner,
    pass_count = state.pass_count or 0,
    last_move = nil,
  }

  local lm = state.last_move
  if lm then
    copy.last_move = {
      kind = lm.kind,
      converted = lm.converted or 0,
      from = { x = lm.from.x, y = lm.from.y },
      to = { x = lm.to.x, y = lm.to.y },
    }
  end

  return copy
end

function board_same_cell(a, b)
  return a and b and a.x == b.x and a.y == b.y
end

-- mossballs is always played on a 7x7 dish (both editions).
level_board_size = 7

function level_load()
  local n = level_board_size
  local state = board_new_state(n, n)

  board_set_cell(state, 1, 1, "player")
  board_set_cell(state, n, n, "player")
  board_set_cell(state, 1, n, "enemy")
  board_set_cell(state, n, 1, "enemy")

  return state
end
