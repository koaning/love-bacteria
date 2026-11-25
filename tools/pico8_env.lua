-- Loads pico8/*.lua into a sandbox that only exposes PICO-8 builtins.
--
-- This doubles as a dialect linter for the mirrored files:
--   * PICO-8-only syntax (+=, !=, ?) fails to parse under LuaJIT.
--   * Touching math./table./string./ipairs/require raises an error, because
--     those globals don't exist on PICO-8 either.

local Env = {}

local MIRRORED_FILES = { "board.lua", "rules.lua", "ai.lua" }

local function pico_all(t)
  local i = 0
  return function()
    i = i + 1
    return t and t[i]
  end
end

local function pico_add(t, v)
  t[#t + 1] = v
  return v
end

local function pico_deli(t, i)
  return table.remove(t, i or #t)
end

-- rng(n) must return an integer in 1..n. PICO-8 code does flr(rnd(n)) + 1,
-- so rnd(n) hands back rng(n) - 1 to consume the exact same sequence the LÖVE
-- side consumes through love.math.random(n).
function Env.new(root, rng)
  local env = {
    all = pico_all,
    add = pico_add,
    deli = pico_deli,
    abs = math.abs,
    flr = math.floor,
    ceil = math.ceil,
    max = math.max,
    min = math.min,
    sqrt = math.sqrt,
    sub = function(s, i, j) return string.sub(s, i, j or i) end,
    tostr = tostring,
    tonum = tonumber,
    pairs = pairs,
    type = type,
    rnd = function(n)
      if not rng then
        error("pico8 copy called rnd() but the test supplied no rng", 2)
      end
      return rng(n) - 1
    end,
    ai_tick = function() end,
  }

  setmetatable(env, {
    __index = function(_, key)
      error("pico8 copy touched undefined global '" .. tostring(key)
        .. "' (not a PICO-8 builtin and not defined by the cart)", 2)
    end,
  })

  for _, name in ipairs(MIRRORED_FILES) do
    local path = root .. "/pico8/" .. name
    local chunk, err = loadfile(path)
    if not chunk then
      error("could not load " .. path .. " under LuaJIT -- is it using "
        .. "PICO-8-only syntax (+=, !=, ?) in a mirrored file?\n" .. err)
    end
    setfenv(chunk, env)
    chunk()
  end

  return env
end

-- Deterministic LCG so both brains can be fed identical "random" numbers.
function Env.make_rng(seed)
  local s = seed
  return function(n)
    s = (s * 1103515245 + 12345) % 2147483648
    return (math.floor(s / 65536) % n) + 1
  end
end

return Env
