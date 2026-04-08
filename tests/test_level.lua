local board = require("src.board")
local level = require("src.level")

local Tests = {}

local function assert_equal(actual, expected, message)
  if actual ~= expected then
    error((message or "Values are not equal") .. ": expected " .. tostring(expected) .. ", got " .. tostring(actual), 2)
  end
end

function Tests.load_defaults_to_7x7()
  local state = level.load()

  assert_equal(state.width, 7, "Default board width should be 7")
  assert_equal(state.height, 7, "Default board height should be 7")
end

function Tests.load_places_starting_pieces_in_corners()
  local state = level.load(5)

  assert_equal(board.get_cell(state, 1, 1), "player", "Top-left corner should be player")
  assert_equal(board.get_cell(state, 5, 5), "player", "Bottom-right corner should be player")
  assert_equal(board.get_cell(state, 1, 5), "enemy", "Bottom-left corner should be enemy")
  assert_equal(board.get_cell(state, 5, 1), "enemy", "Top-right corner should be enemy")
end

function Tests.load_supports_9x9()
  local state = level.load(9)

  assert_equal(state.width, 9, "Board width should be 9 when requested")
  assert_equal(state.height, 9, "Board height should be 9 when requested")
  assert_equal(board.get_cell(state, 9, 9), "player", "Bottom-right corner should be player on 9x9")
end

return Tests
