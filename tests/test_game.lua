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

local function table_has_value(values, target)
  for _, value in ipairs(values) do
    if value == target then
      return true
    end
  end

  return false
end

local function make_audio_spy(initial_muted)
  local calls = {}
  local audio = {
    muted = initial_muted == true,
    context = nil,
    context_calls = {},
    target_music = nil,
    target_music_calls = {},
    sfx_volume = 0.72,
    music_volume = 0.42,
  }

  function audio:play(name)
    calls[#calls + 1] = name
  end

  function audio:set_context(next_context)
    self.context = next_context
    self.context_calls[#self.context_calls + 1] = next_context
  end

  function audio:set_target_music(track_name)
    self.target_music = track_name
    self.target_music_calls[#self.target_music_calls + 1] = track_name or "__none__"
  end

  function audio:update()
  end

  function audio:toggle_muted()
    self.muted = not self.muted
    return self.muted
  end

  function audio:is_muted()
    return self.muted
  end

  function audio:get_status_text()
    if self.muted then
      return "Audio: Muted"
    end

    return "Audio: On"
  end

  function audio:get_sfx_volume()
    return self.sfx_volume
  end

  function audio:get_music_volume()
    return self.music_volume
  end

  function audio:adjust_sfx_volume(delta)
    local next_volume = self.sfx_volume + (delta or 0)
    if next_volume < 0 then
      next_volume = 0
    elseif next_volume > 1 then
      next_volume = 1
    end
    self.sfx_volume = next_volume
    return self.sfx_volume
  end

  function audio:adjust_music_volume(delta)
    local next_volume = self.music_volume + (delta or 0)
    if next_volume < 0 then
      next_volume = 0
    elseif next_volume > 1 then
      next_volume = 1
    end
    self.music_volume = next_volume
    return self.music_volume
  end

  return audio, calls
end

local function find_control_rect(controls, control_id)
  for _, control in ipairs(controls or {}) do
    if control.id == control_id then
      return control
    end
  end

  return nil
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

function Tests.start_game_intro_keeps_shared_music_running_until_game_cue()
  local game = Game.new()
  local audio_spy = make_audio_spy(false)
  local initial_context_calls = 0

  game.audio = audio_spy
  game:set_screen("play_menu")
  initial_context_calls = #game.audio.context_calls

  game:start_game(7, "hard")

  assert_equal(#game.audio.target_music_calls, 0, "Shared music should keep running during intro")
  assert_equal(#game.audio.context_calls, initial_context_calls, "Game music should not start immediately when intro begins")

  game:update(0.45)
  assert_equal(#game.audio.context_calls, initial_context_calls, "Game music should wait until opening scene reaches cue point")

  game:update(0.20)
  assert_equal(game.audio.context_calls[#game.audio.context_calls], "game", "Game music should start during opening scene")

  game:update(1.0)
  assert_truthy(game:get_opening_scene_view() and game:get_opening_scene_view().active == false, "Opening scene should end after enough time")
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

function Tests.play_menu_shift_m_toggles_mute_instead_of_medium()
  local game = Game.new()
  local audio_spy = nil
  local previous_love = love

  game:set_screen("play_menu")
  audio_spy = make_audio_spy(false)
  game.audio = audio_spy

  local ok, err = pcall(function()
    love = {
      keyboard = {
        isDown = function(key)
          return key == "lshift"
        end,
      },
    }

    game:keypressed("m")

    assert_equal(game.selected_bot_difficulty, "hard", "Shift+M should not change medium difficulty shortcut")
    assert_equal(game.audio.muted, true, "Shift+M should toggle mute in play menu")
  end)

  love = previous_love

  if not ok then
    error(err, 2)
  end
end

function Tests.main_menu_m_toggles_mute()
  local game = Game.new()
  local audio_spy = nil

  audio_spy = make_audio_spy(false)
  game.audio = audio_spy

  game:keypressed("m")
  assert_equal(game.audio.muted, true, "M should toggle mute on main menu")
end

function Tests.main_menu_settings_row_clicks_adjust_volume_and_mute()
  local game = Game.new()
  local audio_spy, calls = make_audio_spy(false)
  local ui = nil
  local sfx_up = nil
  local music_down = nil
  local mute = nil

  game.audio = audio_spy
  game.settings_visible = true
  ui = game:get_menu_ui("main_menu")
  sfx_up = find_control_rect(ui.settings_controls, "sfx_up")
  music_down = find_control_rect(ui.settings_controls, "music_down")
  mute = find_control_rect(ui.settings_controls, "mute")

  game:handle_main_menu_click(sfx_up.x + 2, sfx_up.y + 2)
  assert_truthy(game.audio.sfx_volume > 0.72, "Clicking SFX+ should increase sfx volume")

  game:handle_main_menu_click(music_down.x + 2, music_down.y + 2)
  assert_truthy(game.audio.music_volume < 0.42, "Clicking Music- should decrease music volume")

  game:handle_main_menu_click(mute.x + 2, mute.y + 2)
  assert_equal(game.audio.muted, true, "Clicking mute control should toggle mute")
  assert_truthy(table_has_value(calls, "navigate"), "Volume controls should play navigation feedback sound")
end

function Tests.main_menu_tab_toggles_settings_visibility()
  local game = Game.new()

  assert_equal(game.settings_visible, false, "Settings should be hidden by default")
  game:keypressed("tab")
  assert_equal(game.settings_visible, true, "Tab should show settings in main menu")
  game:keypressed("tab")
  assert_equal(game.settings_visible, false, "Tab should hide settings in main menu")
end

function Tests.hidden_settings_row_does_not_handle_clicks()
  local game = Game.new()
  local audio_spy = nil
  local ui = nil
  local sfx_up = nil

  audio_spy = make_audio_spy(false)
  game.audio = audio_spy
  game.settings_visible = false
  ui = game:get_menu_ui("main_menu")
  sfx_up = find_control_rect(ui.settings_controls, "sfx_up")

  game:handle_main_menu_click(sfx_up.x + 2, sfx_up.y + 2)
  assert_equal(game.audio.sfx_volume, 0.72, "Settings click should be ignored while settings are hidden")
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

function Tests.gamepad_dpad_moves_cursor_and_a_button_acts()
  local game = Game.new()
  game:start_game(7, "hard")

  assert_equal(game.cursor_cell.x, 1, "Cursor should start on first player piece")
  assert_equal(game.cursor_cell.y, 1, "Cursor should start on first player piece")

  game:gamepadpressed(nil, "a")
  assert_equal(game.state.selected_cell.x, 1, "A button should select piece at cursor")
  assert_equal(game.state.selected_cell.y, 1, "A button should select piece at cursor")

  game:gamepadpressed(nil, "dpright")
  assert_equal(game.cursor_cell.x, 2, "D-pad right should move cursor")

  game:gamepadpressed(nil, "a")
  assert_equal(board.get_cell(game.state, 2, 1), "player", "A button should commit move from selected piece")
  assert_equal(game.state.current_player, "enemy", "After move it should become enemy turn")
end

function Tests.gamepad_main_menu_a_button_opens_play_menu()
  local game = Game.new()

  game:gamepadpressed(nil, "a")
  assert_equal(game.screen, "play_menu", "A button on main menu should activate focused Play button")
end

function Tests.gamepad_b_button_returns_to_main_menu_from_playing()
  local game = Game.new()
  game:start_game(7, "hard")
  assert_equal(game.screen, "playing")

  game:gamepadpressed(nil, "b")
  assert_equal(game.screen, "main_menu", "B button should leave playing screen")
  assert_equal(game.state, nil, "Leaving playing should clear state")
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

function Tests.playing_cursor_navigation_plays_cursor_sound()
  local game = Game.new()
  local audio_spy, calls = make_audio_spy(false)
  game:start_game(7, "hard")
  game.audio = audio_spy

  game:keypressed("right")

  assert_truthy(table_has_value(calls, "cursor_move"), "Moving the board cursor should play cursor move sound")
end

function Tests.playing_piece_select_plays_select_sound()
  local game = Game.new()
  local audio_spy, calls = make_audio_spy(false)
  game:start_game(7, "hard")
  game.audio = audio_spy

  game:keypressed("return")

  assert_truthy(table_has_value(calls, "select"), "Selecting a piece should play select sound")
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

function Tests.commit_move_plays_convert_sound_when_enemy_is_converted()
  local game = Game.new()
  local audio_spy, calls = make_audio_spy(false)

  game.audio = audio_spy
  game.state = board.new_state(5, 5)
  game.state.current_player = "player"
  board.set_cell(game.state, 1, 1, "player")
  board.set_cell(game.state, 3, 1, "enemy")

  game:commit_move({
    kind = "grow",
    from = { x = 1, y = 1 },
    to = { x = 2, y = 1 },
  })

  assert_equal(board.get_cell(game.state, 3, 1), "player", "Move should convert adjacent enemy piece")
  assert_truthy(table_has_value(calls, "player_move"), "Commit move should play player move sound")
  assert_truthy(table_has_value(calls, "convert"), "Commit move should play convert sound when pieces flip")
end

function Tests.commit_move_starts_board_move_animation()
  local game = Game.new()
  local audio_spy = make_audio_spy(false)

  game.audio = audio_spy
  game.state = board.new_state(5, 5)
  game.state.current_player = "player"
  board.set_cell(game.state, 1, 1, "player")

  game:commit_move({
    kind = "grow",
    from = { x = 1, y = 1 },
    to = { x = 2, y = 1 },
  })

  assert_truthy(game.move_animation ~= nil, "Commit move should create a move animation")
  assert_equal(game.move_animation.kind, "grow", "Move animation should preserve move kind")
  assert_equal(game.move_animation.from.x, 1, "Move animation should track origin cell")
  assert_equal(game.move_animation.to.x, 2, "Move animation should track destination cell")
end

function Tests.commit_move_many_converts_plays_big_capture_sound()
  local game = Game.new()
  local audio_spy, calls = make_audio_spy(false)

  game.audio = audio_spy
  game.state = board.new_state(5, 5)
  game.state.current_player = "player"
  board.set_cell(game.state, 1, 1, "player")
  board.set_cell(game.state, 3, 1, "enemy")
  board.set_cell(game.state, 1, 2, "enemy")
  board.set_cell(game.state, 2, 2, "enemy")
  board.set_cell(game.state, 3, 2, "enemy")

  game:commit_move({
    kind = "grow",
    from = { x = 1, y = 1 },
    to = { x = 2, y = 1 },
  })

  assert_equal(game.state.last_move.converted, 4, "Setup move should convert four enemy cells")
  assert_truthy(table_has_value(calls, "big_capture"), "Large conversions should play big capture sound")
  assert_truthy(game.screen_shake and game.screen_shake.amplitude > 0, "Large conversions should trigger screen shake")
  assert_truthy(game.screen_shake.duration > 0, "Large conversions should set shake duration")
end

function Tests.screen_shake_expires_after_duration()
  local game = Game.new()
  local audio_spy = make_audio_spy(false)

  game.audio = audio_spy
  game:trigger_screen_shake(4, 0.1)
  game:update_screen_shake(0.2)

  assert_equal(game.screen_shake.amplitude, 0, "Shake amplitude should clear after duration elapses")
  assert_equal(game.screen_shake.duration, 0, "Shake duration should clear after duration elapses")
  assert_equal(game.screen_shake.x, 0, "Shake x offset should reset when shake ends")
  assert_equal(game.screen_shake.y, 0, "Shake y offset should reset when shake ends")
end

function Tests.resolve_forced_pass_plays_pass_sound()
  local game = Game.new()
  local audio_spy, calls = make_audio_spy(false)

  game.audio = audio_spy
  game.ai_delay = 999
  game.state = blocked_player_state()
  game:set_screen("playing")

  game:update(0)

  assert_truthy(table_has_value(calls, "pass"), "Auto-pass should trigger pass sound")
end

function Tests.setting_new_winner_plays_victory_sound()
  local game = Game.new()
  local audio_spy, calls = make_audio_spy(false)
  local previous_state = board.new_state(5, 5)
  local next_state = nil

  game.audio = audio_spy

  board.set_cell(previous_state, 1, 1, "player")
  board.set_cell(previous_state, 5, 5, "enemy")
  previous_state.current_player = "player"
  next_state = board.clone_state(previous_state)
  next_state.winner = "player"

  game:set_state(previous_state, false)
  game:set_state(next_state, previous_state)

  assert_truthy(table_has_value(calls, "win"), "Winner transition should play victory sound")
end

function Tests.start_game_adds_piece_spawn_animations()
  local game = Game.new()
  game:start_game(7, "hard")

  assert_equal(count_pairs(game.piece_animations), 4, "Starting layout should animate four starting pieces")
  game:update_piece_animations(1.0)
  assert_equal(next(game.piece_animations), nil, "Piece animations should expire after enough time")
end

return Tests
