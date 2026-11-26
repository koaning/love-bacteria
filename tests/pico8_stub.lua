-- Boots pico8/main.lua under LuaJIT on a stubbed PICO-8 API, so a smoke test
-- can play the cart through its buttons. Drawing and sound are no-ops; input,
-- cartdata, time() and stat() are faked.
--
--   package.path = "tests/?.lua;tools/?.lua;" .. package.path
--   local stub = require("pico8_stub")
--   local game = stub.boot({
--     seed = 7,                       -- rnd() goes through pico8_env.make_rng(seed)
--     save = {},                      -- cartdata numbers (game.data, shared)
--     peek = { "scene", "score", "moves = #hist" },  -- cart locals to read back
--   })
--   game.frame({ stub.O })            -- one frame with O pressed
--   game.frame({}, { stub.X })        -- one frame with X held (btn, not btnp)
--   game.frame({}, {}, { stub.ENTER })  -- devkit keyboard: stat(28, 40)
--   game.peek().scene
--
-- `peek` entries are either a name ("scene") or "key = expression"
-- ("moves = #hist"); they are evaluated inside main.lua's scope, so they can
-- read its locals. opts.globals adds or replaces API functions; opts.files
-- is passed on to pico8_env (the logic files loaded before main.lua).

local pico8_env = require("pico8_env")

local stub = {
  LEFT = 0, RIGHT = 1, UP = 2, DOWN = 3, O = 4, X = 5, PAUSE = 6,
  ENTER = 40, -- SDL scancode, for stat(28, n)
}

local NOOPS = {
  "cls", "rectfill", "rect", "circfill", "circ", "line", "print", "sfx", "music",
  "ovalfill", "oval", "pset", "fillp", "clip", "pal", "palt", "spr", "sspr", "map",
  "camera", "color", "cursor", "cartdata", "menuitem", "poke", "poke2", "poke4",
  "memcpy", "memset", "printh", "srand", "flip", "sset", "mset",
}

local function peek_source(names)
  local fields = {}
  for _, n in ipairs(names or {}) do
    fields[#fields + 1] = n:find("=", 1, true) and n or (n .. " = " .. n)
  end
  return "\nfunction __peek() return { " .. table.concat(fields, ", ") .. " } end\n"
end

function stub.boot(opts)
  opts = opts or {}
  local env = pico8_env.new(".", pico8_env.make_rng(opts.seed or 1),
    { files = opts.files, globals = opts.globals })
  local pressed, holding, keys = {}, {}, {}
  local data = opts.save or {}
  local frames, cpu = 0, 0
  local function noop() end

  local api = {
    dget = function(i) return data[i] or 0 end,
    dset = function(i, v) data[i] = v end,
    btnp = function(b) return pressed[b] == true end,
    btn = function(b)
      if b == nil then
        local mask = 0
        for i = 0, 6 do
          if pressed[i] or holding[i] then mask = mask + 2 ^ i end
        end
        return mask
      end
      return pressed[b] == true or holding[b] == true
    end,
    -- stat(0)/stat(1) creep up with every call, so code that yields when a
    -- frame's CPU runs out still yields; stat(28, k) is the devkit keyboard
    stat = function(n, k)
      if n == 0 or n == 1 then cpu = cpu + 0.01; return cpu end
      if n == 28 then return keys[k] == true end
      if n == 7 then return 60 end
      return 0
    end,
    time = function() return frames / 60 end,
    t = function() return frames / 60 end,
    pget = function() return 0 end,
    sget = function() return 0 end,
    mget = function() return 0 end,
    peek = function() return 0 end,
    del = function(t, v)
      for i = 1, #t do
        if t[i] == v then return table.remove(t, i) end
      end
    end,
    count = function(t) return #t end,
    foreach = function(t, f) for _, v in ipairs(t) do f(v) end end,
    mid = function(a, b, c)
      if a > b then a, b = b, a end
      return math.max(a, math.min(b, c))
    end,
    sgn = function(x) return x < 0 and -1 or 1 end,
    sin = function(a) return -math.sin(a * 2 * math.pi) end,
    cos = function(a) return math.cos(a * 2 * math.pi) end,
    atan2 = function(dx, dy) return (math.atan2(-dy, dx) / (2 * math.pi)) % 1 end,
    chr = string.char,
    ord = function(s, i) return string.byte(s, i or 1) end,
    cocreate = coroutine.create,
    coresume = coroutine.resume,
    costatus = coroutine.status,
    yield = coroutine.yield,
    stop = function(msg) error("cart stop(): " .. tostring(msg)) end,
  }
  for _, name in ipairs(NOOPS) do rawset(env, name, noop) end
  for k, v in pairs(api) do rawset(env, k, v) end
  for k, v in pairs(opts.globals or {}) do rawset(env, k, v) end

  local f = assert(io.open("pico8/main.lua"))
  local src = f:read("*a") .. peek_source(opts.peek)
  f:close()
  local chunk = assert(loadstring(src, "@pico8/main.lua"))
  setfenv(chunk, env)
  chunk()
  if rawget(env, "_init") then env._init() end

  local update = rawget(env, "_update60") or rawget(env, "_update")
  assert(update, "pico8/main.lua defines neither _update60 nor _update")

  local game = { env = env, data = data }

  -- one frame: `buttons` pressed this frame (btnp and btn), `hold` held
  -- (btn only), `scancodes` down on the devkit keyboard
  function game.frame(buttons, hold, scancodes)
    pressed, holding, keys = {}, {}, {}
    for _, b in ipairs(buttons or {}) do pressed[b] = true end
    for _, b in ipairs(hold or {}) do holding[b] = true end
    for _, k in ipairs(scancodes or {}) do keys[k] = true end
    frames, cpu = frames + 1, 0
    update()
    if rawget(env, "_draw") then env._draw() end
  end

  -- n empty frames
  function game.wait(n)
    for _ = 1, n or 1 do game.frame() end
  end

  function game.peek()
    return env.__peek()
  end

  function game.frames()
    return frames
  end

  return game
end

return stub
