local Board = {}

function Board.new_state(width, height)
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
    selected_cell = nil,
    winner = nil,
    pass_count = 0,
    status_text = nil,
    last_move = nil,
  }
end

function Board.in_bounds(state, x, y)
  return x >= 1 and x <= state.width and y >= 1 and y <= state.height
end

function Board.get_cell(state, x, y)
  if not Board.in_bounds(state, x, y) then
    return nil
  end

  return state.cells[y][x]
end

function Board.set_cell(state, x, y, value)
  if Board.in_bounds(state, x, y) then
    state.cells[y][x] = value
  end
end

function Board.count_cells(state, side)
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

function Board.clone_cells(state)
  local cells = {}

  for y = 1, state.height do
    cells[y] = {}
    for x = 1, state.width do
      cells[y][x] = state.cells[y][x]
    end
  end

  return cells
end

function Board.clone_state(state)
  local copy = {
    width = state.width,
    height = state.height,
    cells = Board.clone_cells(state),
    current_player = state.current_player,
    selected_cell = nil,
    winner = state.winner,
    pass_count = state.pass_count or 0,
    status_text = state.status_text,
    last_move = nil,
  }

  if state.selected_cell then
    copy.selected_cell = {
      x = state.selected_cell.x,
      y = state.selected_cell.y,
    }
  end

  if state.last_move then
    copy.last_move = {
      kind = state.last_move.kind,
      converted = state.last_move.converted or 0,
      from = {
        x = state.last_move.from.x,
        y = state.last_move.from.y,
      },
      to = {
        x = state.last_move.to.x,
        y = state.last_move.to.y,
      },
    }
  end

  return copy
end

function Board.same_cell(a, b)
  return a and b and a.x == b.x and a.y == b.y
end

return Board
