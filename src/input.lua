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
