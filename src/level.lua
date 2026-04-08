local board = require("src.board")

local Level = {}

function Level.load()
  local state = board.new_state(7, 7)

  board.set_cell(state, 1, 1, "player")
  board.set_cell(state, 7, 7, "player")
  board.set_cell(state, 1, 7, "enemy")
  board.set_cell(state, 7, 1, "enemy")

  return state
end

return Level
