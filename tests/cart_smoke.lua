-- Cart smoke test: boots pico8/main.lua against stubbed PICO-8 graphics and
-- input, then plays games from the title screen until someone wins. Catches
-- runtime errors in the cart-only code that the unit tests never touch.
--
-- Run from the repo root:  luajit tests/cart_smoke.lua

package.path = "tests/?.lua;tools/?.lua;" .. package.path
local pico8_env = require("pico8_env")
local stub = require("pico8_stub")

local function play_one(seed, menu_presses)
  local game = stub.boot({
    seed = seed,
    globals = { ai_tick = function() end },
    peek = { "scene", "state", "cur", "targets", "anim" },
  })
  local env = game.env
  local rng = pico8_env.make_rng(seed + 100)

  for _, b in ipairs(menu_presses) do game.frame({ b }) end
  game.frame({ stub.O })
  assert(game.peek().scene == "play", "start should enter play scene")

  for _ = 1, 60000 do
    local p = game.peek()
    if p.anim then
      game.frame()
    elseif p.state.winner then
      game.frame({ stub.O })
      assert(game.peek().scene == "title", "button after game over should return to title")
      return p.state.winner
    elseif p.state.current_player == "player" then
      -- Pick a random legal move, walk the cursor to it, press O twice.
      local moves = env.rules_get_legal_moves(p.state, "player")
      local m = moves[rng(#moves)]
      local function walk(tx, ty)
        -- the cart replaces its cursor table after each landing, so re-read it
        while true do
          local cur = game.peek().cur
          if cur.x == tx and cur.y == ty then break end
          local b = cur.x < tx and stub.RIGHT or cur.x > tx and stub.LEFT
            or cur.y < ty and stub.DOWN or stub.UP
          game.frame({ b })
        end
      end
      walk(m.from.x, m.from.y)
      game.frame({ stub.O })
      assert(#game.peek().targets > 0, "selecting own piece should show targets")
      walk(m.to.x, m.to.y)
      game.frame({ stub.O })
    else
      game.frame()
    end
  end

  error("game did not finish")
end

local results = {}
-- title: left/right (0/1) cycles bot difficulty, starting at medium.
results[#results + 1] = play_one(1, { stub.LEFT })  -- easy
results[#results + 1] = play_one(2, {})             -- medium
results[#results + 1] = play_one(3, { stub.RIGHT }) -- hard
print("Cart smoke: 3 games played from title to game over (" .. table.concat(results, ", ") .. ").")
