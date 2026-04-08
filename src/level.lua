local board = require("src.board")

local Level = {}

function Level.load(size)
  local board_size = size or 7
  local state = board.new_state(board_size, board_size)

  board.set_cell(state, 1, 1, "player")
  board.set_cell(state, board_size, board_size, "player")
  board.set_cell(state, 1, board_size, "enemy")
  board.set_cell(state, board_size, 1, "enemy")

  return state
end

return Level
