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

local function count_pairs(tbl)
  local count = 0
  for _ in pairs(tbl) do
    count = count + 1
  end
  return count
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
  game:set_screen("playing")

  game:update(0)

  assert_equal(game.state.current_player, "enemy", "Update should auto-pass to enemy")
  assert_equal(#rules.get_legal_moves(game.state, "player"), 0, "Player should still be blocked")
end

function Tests.enemy_keeps_turn_when_player_remains_blocked()
  local game = Game.new()
  game.ai_delay = 0
  game.state = blocked_player_state()
  game:set_screen("playing")

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

  game:start_game(7, "medium")
  assert_equal(game.bot_difficulty, "medium", "Bot difficulty should support medium")

  game:start_game(7, "hard")
  assert_equal(game.bot_difficulty, "hard", "Bot difficulty should switch between easy and hard")
end

function Tests.new_starts_in_main_menu_with_default_difficulty()
  local game = Game.new()

  assert_equal(game.screen, "main_menu", "Game should start on main menu")
  assert_equal(game.selected_bot_difficulty, "hard", "Default selected bot difficulty should be hard")
end

function Tests.menu_transition_advances_over_time()
  local game = Game.new()

  assert_equal(game.menu_transition, 0, "Menu transition should reset when entering a menu")
  game:update(0.12)
  assert_truthy(game.menu_transition > 0 and game.menu_transition < 1, "Menu transition should animate in")
  game:update(1.0)
  assert_equal(game.menu_transition, 1, "Menu transition should cap at full visibility")
end

function Tests.play_transition_advances_during_gameplay()
  local game = Game.new()
  game:start_game(7, "hard")

  assert_equal(game.play_transition, 0, "Gameplay transition should reset when entering a match")
  game:update(0.10)
  assert_truthy(game.play_transition > 0 and game.play_transition < 1, "Gameplay transition should animate in")
  game:update(1.0)
  assert_equal(game.play_transition, 1, "Gameplay transition should cap at full visibility")
end

function Tests.main_menu_keyboard_shortcuts()
  local game = Game.new()

  game:keypressed("p")
  assert_equal(game.screen, "play_menu", "P key should open play menu")
end

function Tests.play_menu_keyboard_shortcuts()
  local game = Game.new()
  game:set_screen("play_menu")

  game:keypressed("5")
  game:keypressed("e")
  game:keypressed("return")

  assert_equal(game.screen, "playing", "Enter should start game from play menu")
  assert_equal(game.state.width, 5, "Board size hotkey should be applied")
  assert_equal(game.bot_difficulty, "easy", "Difficulty hotkey should be applied")
end

function Tests.play_menu_keyboard_medium_shortcut()
  local game = Game.new()
  game:set_screen("play_menu")

  game:keypressed("m")
  game:keypressed("return")

  assert_equal(game.screen, "playing", "Enter should start game from play menu")
  assert_equal(game.bot_difficulty, "medium", "M hotkey should select medium difficulty")
end

function Tests.main_menu_arrow_focus_selects_play()
  local game = Game.new()

  game:keypressed("down")
  game:keypressed("up")
  game:keypressed("return")

  assert_equal(game.screen, "play_menu", "Arrow focus plus Enter should activate focused menu button")
end

function Tests.play_menu_arrow_focus_can_activate_back()
  local game = Game.new()
  game:set_screen("play_menu")

  game:keypressed("left")
  game:keypressed("return")

  assert_equal(game.screen, "main_menu", "Arrow focus plus Enter should activate focused play menu button")
end

function Tests.play_menu_vertical_focus_activates_difficulty()
  local game = Game.new()
  game:set_screen("play_menu")
  game.selected_bot_difficulty = "easy"

  game:keypressed("up")
  game:keypressed("return")

  assert_equal(game.selected_bot_difficulty, "hard", "Up from start should focus hard difficulty")
  assert_equal(game.screen, "play_menu", "Selecting difficulty should keep play menu open")
end

function Tests.play_menu_arrow_focus_can_activate_medium_difficulty()
  local game = Game.new()
  game:set_screen("play_menu")
  game.selected_bot_difficulty = "hard"

  game:keypressed("up")
  game:keypressed("left")
  game:keypressed("return")

  assert_equal(game.selected_bot_difficulty, "medium", "Arrow focus plus Enter should activate medium difficulty")
  assert_equal(game.screen, "play_menu", "Selecting difficulty should keep play menu open")
end

function Tests.fullscreen_hotkeys_toggle_window_mode()
  local game = Game.new()
  local previous_love = love
  local fullscreen = false
  local set_calls = 0

  local ok, err = pcall(function()
    love = {
      window = {
        getFullscreen = function()
          return fullscreen
        end,
        setFullscreen = function(next_mode, mode_type)
          fullscreen = next_mode
          set_calls = set_calls + 1
          assert_equal(mode_type, "desktop", "Fullscreen should use desktop mode")
        end,
      },
    }

    game:keypressed("f11")
    assert_equal(fullscreen, true, "F11 should enable fullscreen")

    game:keypressed("f")
    assert_equal(fullscreen, false, "F should disable fullscreen when already enabled")
    assert_equal(set_calls, 2, "Each fullscreen hotkey press should call window.setFullscreen once")
  end)

  love = previous_love

  if not ok then
    error(err, 2)
  end
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

function Tests.playing_arrow_hold_repeats_cursor_movement()
  local game = Game.new()
  game:start_game(7, "hard")
  local previous_love = love

  local ok, err = pcall(function()
    love = {
      keyboard = {
        isDown = function(key)
          return key == "right"
        end,
      },
    }

    game:keypressed("right")
    assert_equal(game.cursor_cell.x, 2, "Initial right press should move cursor one step")

    game:update(0.40)
    assert_truthy(game.cursor_cell.x > 2, "Held arrow key should continue moving cursor across cells")
  end)

  love = previous_love

  if not ok then
    error(err, 2)
  end
end

function Tests.start_game_adds_piece_spawn_animations()
  local game = Game.new()
  game:start_game(7, "hard")

  assert_equal(count_pairs(game.piece_animations), 4, "Starting layout should animate four starting pieces")
  game:update_piece_animations(1.0)
  assert_equal(next(game.piece_animations), nil, "Piece animations should expire after enough time")
end

return Tests
