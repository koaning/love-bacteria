-- Finds the game's cart: the CART environment variable (the Makefile sets
-- it from GAME in game.mk), else the only pico8/*.p8.
--
--   local cart = require("cart")()          -- "pico8/<game>.p8"

return function(root)
  root = root or "."
  local env = os.getenv("CART")
  if env and env ~= "" then
    return root == "." and env or root .. "/" .. env
  end
  local found = {}
  local ls = io.popen('ls "' .. root .. '/pico8/" 2>/dev/null')
  for name in ls:lines() do
    if name:match("%.p8$") then found[#found + 1] = root .. "/pico8/" .. name end
  end
  ls:close()
  if #found ~= 1 then
    error("expected one pico8/*.p8 cart, found " .. #found .. " (set CART=pico8/<game>.p8)", 2)
  end
  return found[1]
end
