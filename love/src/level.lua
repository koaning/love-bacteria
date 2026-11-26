local board = require("src.board")

local Level = {}

-- Mossballs is always played on a 7x7 dish (both the LÖVE and PICO-8 editions).
Level.BOARD_SIZE = 7

function Level.load()
  local board_size = Level.BOARD_SIZE
  local state = board.new_state(board_size, board_size)

  board.set_cell(state, 1, 1, "player")
  board.set_cell(state, board_size, board_size, "player")
  board.set_cell(state, 1, board_size, "enemy")
  board.set_cell(state, board_size, 1, "enemy")

  return state
end

return Level
