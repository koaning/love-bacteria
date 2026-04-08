local board = require("src.board")
local Game = require("src.game")
local rules = require("src.rules")

local Tests = {}

local function assert_equal(actual, expected, message)
  if actual ~= expected then
    error((message or "Values are not equal") .. ": expected " .. tostring(expected) .. ", got " .. tostring(actual), 2)
  end
end

local function assert_truthy(value, message)
  if not value then
    error(message or "Expected truthy value", 2)
  end
end

local function fill_board(state, side)
  for y = 1, state.height do
    for x = 1, state.width do
      board.set_cell(state, x, y, side)
    end
  end
end

local function blocked_player_state()
  local state = board.new_state(7, 7)
  fill_board(state, "enemy")
  board.set_cell(state, 1, 1, "player")
  board.set_cell(state, 7, 7, "empty")
  board.set_cell(state, 7, 6, "empty")
  board.set_cell(state, 6, 7, "empty")
  state.current_player = "player"
  return state
end

function Tests.update_auto_passes_blocked_player_without_input()
  local game = Game.new()
  game.ai_delay = 999
  game.state = blocked_player_state()
  game.screen = "playing"

  game:update(0)

  assert_equal(game.state.current_player, "enemy", "Update should auto-pass to enemy")
  assert_equal(#rules.get_legal_moves(game.state, "player"), 0, "Player should still be blocked")
end

function Tests.enemy_keeps_turn_when_player_remains_blocked()
  local game = Game.new()
  game.ai_delay = 0
  game.state = blocked_player_state()
  game.screen = "playing"

  game:update(0)

  assert_truthy(game.state.last_move, "Enemy should make a move after player pass")
  assert_equal(game.state.current_player, "enemy", "Turn should remain with enemy if player is still blocked")
  assert_equal(#rules.get_legal_moves(game.state, "player"), 0, "Player should still have no moves")
end

function Tests.start_game_uses_selected_board_size()
  local game = Game.new()

  game:start_game(5)
  assert_equal(game.screen, "playing", "Start game should enter playing screen")
  assert_equal(game.state.width, 5, "Board width should match configured size")
  assert_equal(game.state.height, 5, "Board height should match configured size")

  game:start_game(9)
  assert_equal(game.state.width, 9, "Board width should update to new configured size")
  assert_equal(game.state.height, 9, "Board height should update to new configured size")
end

function Tests.start_game_uses_selected_bot_difficulty()
  local game = Game.new()

  game:start_game(7, "easy")
  assert_equal(game.bot_difficulty, "easy", "Bot difficulty should be set when starting game")

  game:start_game(7, "hard")
  assert_equal(game.bot_difficulty, "hard", "Bot difficulty should switch between easy and hard")
end

function Tests.new_starts_in_main_menu_with_default_resolution()
  local game = Game.new()

  assert_equal(game.screen, "main_menu", "Game should start on main menu")
  assert_equal(game.selected_resolution_id, "res_840_760", "Default resolution should be 840x760")
  assert_equal(game.selected_bot_difficulty, "hard", "Default selected bot difficulty should be hard")
end

function Tests.apply_resolution_updates_selected_option()
  local game = Game.new()

  assert_equal(game:apply_resolution("res_700_700"), true, "Known resolution should apply")
  assert_equal(game.selected_resolution_id, "res_700_700", "Selected resolution should update")

  assert_equal(game:apply_resolution("res_missing"), false, "Unknown resolution should fail")
  assert_equal(game.selected_resolution_id, "res_700_700", "Selected resolution should not change on failure")
end

function Tests.main_menu_keyboard_shortcuts()
  local game = Game.new()

  game:keypressed("p")
  assert_equal(game.screen, "play_menu", "P key should open play menu")

  game.screen = "main_menu"
  game:keypressed("s")
  assert_equal(game.screen, "settings_menu", "S key should open settings menu")
end

function Tests.play_menu_keyboard_shortcuts()
  local game = Game.new()
  game.screen = "play_menu"

  game:keypressed("5")
  game:keypressed("e")
  game:keypressed("return")

  assert_equal(game.screen, "playing", "Enter should start game from play menu")
  assert_equal(game.state.width, 5, "Board size hotkey should be applied")
  assert_equal(game.bot_difficulty, "easy", "Difficulty hotkey should be applied")
end

function Tests.settings_menu_keyboard_shortcuts()
  local game = Game.new()
  game.screen = "settings_menu"

  game:keypressed("1")
  assert_equal(game.selected_resolution_id, "res_700_700", "1 should pick smallest resolution")
  game:keypressed("3")
  assert_equal(game.selected_resolution_id, "res_960_800", "3 should pick largest resolution")
end

function Tests.playing_keyboard_cursor_can_select_and_move()
  local game = Game.new()
  game:start_game(7, "hard")

  assert_equal(game.cursor_cell.x, 1, "Cursor should start on first player piece")
  assert_equal(game.cursor_cell.y, 1, "Cursor should start on first player piece")

  game:keypressed("return")
  assert_equal(game.state.selected_cell.x, 1, "Enter should select piece at cursor")
  assert_equal(game.state.selected_cell.y, 1, "Enter should select piece at cursor")

  game:keypressed("right")
  assert_equal(game.cursor_cell.x, 2, "Arrow key should move cursor")
  assert_equal(game.cursor_cell.y, 1, "Arrow key should move cursor")

  game:keypressed("space")
  assert_equal(board.get_cell(game.state, 2, 1), "player", "Space should execute legal move from selected piece")
  assert_equal(game.state.current_player, "enemy", "After player move it should become enemy turn")
end

return Tests
