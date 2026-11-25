-- Cart smoke test: boots pico8/main.lua against stubbed PICO-8 graphics and
-- input, then plays games from the title screen until someone wins. Catches
-- runtime errors in the cart-only code that the mirror match never touches.
--
-- Run from the repo root:  luajit tests/cart_smoke.lua

package.path = "tools/?.lua;" .. package.path
local pico8_env = require("pico8_env")

local function noop() end

local function boot(seed)
  local env = pico8_env.new(".", pico8_env.make_rng(seed))
  local pressed = {}
  local cpu = 0

  for _, name in ipairs({ "cls", "rectfill", "rect", "circfill", "circ", "line", "print", "sfx", "ovalfill", "pset" }) do
    rawset(env, name, noop)
  end
  rawset(env, "btnp", function(b) return pressed[b] == true end)
  rawset(env, "sin", function(a) return -math.sin(a * 2 * math.pi) end)
  rawset(env, "cos", function(a) return math.cos(a * 2 * math.pi) end)
  rawset(env, "stat", function() cpu = cpu + 0.01; return cpu end)
  local frames = 0
  rawset(env, "time", function() return frames / 60 end)
  rawset(env, "__tick", function() frames = frames + 1 end)
  rawset(env, "cocreate", coroutine.create)
  rawset(env, "coresume", coroutine.resume)
  rawset(env, "costatus", coroutine.status)
  rawset(env, "yield", coroutine.yield)
  rawset(env, "stop", function(msg) error("cart stop(): " .. tostring(msg)) end)
  -- Let the cart read its own state back for the test driver.
  rawset(env, "__peek", nil)

  local src = assert(io.open("pico8/main.lua")):read("*a")
  src = src .. "\nfunction __peek() return scene, state, cur, targets, anim end\n"
  local chunk = assert(loadstring(src, "@pico8/main.lua"))
  setfenv(chunk, env)
  chunk()

  local function frame(buttons)
    pressed = {}
    for _, b in ipairs(buttons or {}) do pressed[b] = true end
    cpu = 0
    env.__tick()
    env._update60()
    env._draw()
  end

  return env, frame
end

local function play_one(seed, menu_presses)
  local env, frame = boot(seed)
  local rng = pico8_env.make_rng(seed + 100)

  for _, b in ipairs(menu_presses) do frame({ b }) end
  frame({ 4 })
  assert(select(1, env.__peek()) == "play", "start should enter play scene")

  for _ = 1, 60000 do
    local scene, state, cur, targets, anim = env.__peek()
    if anim then
      frame()
    elseif state.winner then
      frame({ 4 })
      assert(env.__peek() == "title", "button after game over should return to title")
      return state.winner
    elseif state.current_player == "player" then
      -- Pick a random legal move, walk the cursor to it, press O twice.
      local moves = env.rules_get_legal_moves(state, "player")
      local m = moves[rng(#moves)]
      local function walk(tx, ty)
        -- the cart replaces its cursor table after each landing, so re-read it
        while true do
          cur = select(3, env.__peek())
          if cur.x == tx and cur.y == ty then break end
          local b = cur.x < tx and 1 or cur.x > tx and 0 or cur.y < ty and 3 or 2
          frame({ b })
        end
      end
      walk(m.from.x, m.from.y)
      frame({ 4 })
      targets = select(4, env.__peek())
      assert(#targets > 0, "selecting own piece should show targets")
      walk(m.to.x, m.to.y)
      frame({ 4 })
    else
      frame()
    end
  end

  error("game did not finish")
end

local results = {}
-- title: left/right (0/1) cycles bot difficulty, starting at medium.
results[#results + 1] = play_one(1, { 0 })          -- easy
results[#results + 1] = play_one(2, {})             -- medium
results[#results + 1] = play_one(3, { 1 })          -- hard
print("Cart smoke: 3 games played from title to game over (" .. table.concat(results, ", ") .. ").")
