local input = require("src.input")

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

local function assert_falsy(value, message)
  if value then
    error(message or "Expected falsy value", 2)
  end
end

function Tests.test_gamepad_direction_dpad_up()
  local dx, dy = input.gamepad_direction("dpup")
  assert_equal(dx, 0)
  assert_equal(dy, -1)
end

function Tests.test_gamepad_direction_dpad_down()
  local dx, dy = input.gamepad_direction("dpdown")
  assert_equal(dx, 0)
  assert_equal(dy, 1)
end

function Tests.test_gamepad_direction_dpad_left()
  local dx, dy = input.gamepad_direction("dpleft")
  assert_equal(dx, -1)
  assert_equal(dy, 0)
end

function Tests.test_gamepad_direction_dpad_right()
  local dx, dy = input.gamepad_direction("dpright")
  assert_equal(dx, 1)
  assert_equal(dy, 0)
end

function Tests.test_gamepad_direction_non_dpad_returns_nil()
  assert_equal(input.gamepad_direction("a"), nil)
  assert_equal(input.gamepad_direction("b"), nil)
  assert_equal(input.gamepad_direction("leftshoulder"), nil)
  assert_equal(input.gamepad_direction(""), nil)
end

function Tests.test_is_gamepad_confirm()
  assert_truthy(input.is_gamepad_confirm("a"))
  assert_falsy(input.is_gamepad_confirm("b"))
  assert_falsy(input.is_gamepad_confirm("x"))
  assert_falsy(input.is_gamepad_confirm("dpup"))
end

function Tests.test_is_gamepad_back()
  assert_truthy(input.is_gamepad_back("b"))
  assert_truthy(input.is_gamepad_back("start"))
  assert_falsy(input.is_gamepad_back("a"))
  assert_falsy(input.is_gamepad_back("back"))
end

function Tests.test_is_gamepad_mute()
  assert_truthy(input.is_gamepad_mute("x"))
  assert_falsy(input.is_gamepad_mute("a"))
  assert_falsy(input.is_gamepad_mute("y"))
end

function Tests.test_is_gamepad_restart()
  assert_truthy(input.is_gamepad_restart("y"))
  assert_falsy(input.is_gamepad_restart("x"))
  assert_falsy(input.is_gamepad_restart("a"))
end

function Tests.test_is_gamepad_settings()
  assert_truthy(input.is_gamepad_settings("leftshoulder"))
  assert_truthy(input.is_gamepad_settings("rightshoulder"))
  assert_truthy(input.is_gamepad_settings("back"))
  assert_falsy(input.is_gamepad_settings("start"))
  assert_falsy(input.is_gamepad_settings("a"))
end

function Tests.test_existing_key_helpers_still_work()
  assert_truthy(input.is_restart_key("r"))
  assert_truthy(input.is_quit_key("escape"))
  assert_truthy(input.is_fullscreen_key("f"))
  assert_truthy(input.is_fullscreen_key("f11"))
  assert_truthy(input.is_mute_key("m"))
  assert_truthy(input.is_toggle_settings_key("tab"))
end

return Tests
