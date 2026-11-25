local Input = {}

function Input.is_primary_click(button)
  return button == 1
end

function Input.is_restart_key(key)
  return key == "r"
end

function Input.is_quit_key(key)
  return key == "escape"
end

function Input.is_fullscreen_key(key)
  return key == "f11" or key == "f"
end

function Input.is_mute_key(key)
  return key == "m"
end

function Input.is_toggle_settings_key(key)
  return key == "tab"
end

function Input.gamepad_direction(button)
  if button == "dpup" then
    return 0, -1
  end

  if button == "dpdown" then
    return 0, 1
  end

  if button == "dpleft" then
    return -1, 0
  end

  if button == "dpright" then
    return 1, 0
  end

  return nil
end

function Input.is_gamepad_confirm(button)
  return button == "a"
end

function Input.is_gamepad_back(button)
  return button == "b" or button == "start"
end

function Input.is_gamepad_mute(button)
  return button == "x"
end

function Input.is_gamepad_restart(button)
  return button == "y"
end

function Input.is_gamepad_settings(button)
  return button == "leftshoulder" or button == "rightshoulder" or button == "back"
end

function Input.screen_to_cell(layout, x, y)
  local local_x = x - layout.origin_x
  local local_y = y - layout.origin_y

  if local_x < 0 or local_y < 0 then
    return nil
  end

  if local_x >= layout.board_width or local_y >= layout.board_height then
    return nil
  end

  local cell_x = math.floor(local_x / layout.cell_size) + 1
  local cell_y = math.floor(local_y / layout.cell_size) + 1

  if cell_x < 1 or cell_x > layout.columns or cell_y < 1 or cell_y > layout.rows then
    return nil
  end

  return { x = cell_x, y = cell_y }
end

return Input
