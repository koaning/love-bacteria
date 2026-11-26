-- Scripted run for `love mossballs-p8.love --shots <dir> [--label <file>] [--all]`
-- (`make screenshots`). It presses the buttons for a player and saves:
--
--   pico8-cart.png    the title screen as a cartridge: the cart label with
--                     the cart's title and byline, like PICO-8 shows carts
--   pico8-title.png   the title screen
--   pico8.png         a game in progress with merged colonies and a move hovered
--   with --label:     the title screen as __label__ text (tools/label.lua)
--
-- The cart's locals (state, cur, anim, ...) are read through the upvalues of
-- its callbacks, so the cart needs no test hooks.

local shots = {}
shots.__index = shots

-- finds a local of the cart by name among the upvalues of its callbacks
local function peek(env, name)
  local seen, queue = {}, { env._update60 or env._update, env._draw }
  while #queue > 0 do
    local f = table.remove(queue, 1)
    if not seen[f] then
      seen[f] = true
      local i = 1
      while true do
        local n, v = debug.getupvalue(f, i)
        if not n then break end
        if n == name then return v end
        if type(v) == "function" then queue[#queue + 1] = v end
        i = i + 1
      end
    end
  end
end

function shots.new(dir, all, capture, label, cartridge)
  return setmetatable({ dir = dir, all = all, capture = capture, label = label, cartridge = cartridge,
    save = {}, buttons = {} }, shots)
end

function shots:start(env)
  local LEFT, RIGHT, UP, DOWN, O = 0, 1, 2, 3, 4
  local self_ = self

  local function frame(buttons, n)
    for _ = 1, n or 1 do
      self_.buttons = {}
      for _, b in ipairs(buttons or {}) do self_.buttons[b] = true end
      coroutine.yield()
    end
  end

  local function shot(name)
    self_.capture(self_.dir .. "/" .. name, 4)
  end

  local function wait_player()
    for _ = 1, 2400 do
      local st = peek(env, "state")
      if not peek(env, "anim") and st and (st.winner or st.current_player == "player") then
        return st
      end
      frame()
    end
    error("timed out waiting for player turn")
  end

  local function walk(tx, ty)
    for _ = 1, 64 do
      local cur = peek(env, "cur")
      if cur.x == tx and cur.y == ty then return end
      local b = cur.x < tx and RIGHT or cur.x > tx and LEFT or cur.y < ty and DOWN or UP
      frame({ b })
      frame()
    end
    error("could not walk cursor to " .. tx .. "," .. ty)
  end

  local function best_move(st, want_capture)
    local best, best_score = nil, nil
    for _, m in ipairs(env.rules_get_legal_moves(st, "player")) do
      local score = env.ai_score_move(st, "player", m)
      if want_capture and m.kind == "grow" then
        score = score + 50
      end
      if not best_score or score > best_score then
        best, best_score = m, score
      end
    end
    return best
  end

  self.co = coroutine.create(function()
    env.srand(3)
    frame(nil, 35)
    shot("pico8-title.png")
    self_.cartridge(self_.dir .. "/pico8-cart.png")
    if self_.label then self_.label() end

    -- start a game (medium bot, light theme)
    frame({ O })
    frame()

    -- play 12 turns so both colonies grow into large merged blobs
    for _ = 1, 12 do
      local st = wait_player()
      if st.winner then break end
      local m = best_move(st, false)
      if not m then break end
      walk(m.from.x, m.from.y)
      frame({ O })
      frame()
      walk(m.to.x, m.to.y)
      frame({ O })
      frame()
    end

    -- select a piece and hover a promising grow target for the screenshot
    local st = wait_player()
    if not st.winner then
      local m = best_move(st, true)
      if m then
        walk(m.from.x, m.from.y)
        frame({ O })
        frame()
        walk(m.to.x, m.to.y)
      end
    end
    frame(nil, 4)
    shot("pico8.png")
  end)
end

-- called once per cart frame: false when the script is done
function shots:tick()
  if not self.co or coroutine.status(self.co) == "dead" then return false end
  local ok, err = coroutine.resume(self.co)
  if not ok then error(err) end
  return coroutine.status(self.co) ~= "dead"
end

return shots
