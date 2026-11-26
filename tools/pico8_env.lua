-- Loads the cart's plain-logic files into a sandbox that only exposes PICO-8
-- builtins, so tests can run the exact code the cart runs.
--
--   local pico8_env = require("pico8_env")      -- with tools/ on package.path
--   local env = pico8_env.new(".", pico8_env.make_rng(1))
--   env.rules_new() ...
--
-- By default it loads every file the cart #includes except main.lua (which
-- needs the graphics and input API; tests/pico8_stub.lua boots that one).
-- opts.files overrides the list, opts.globals adds extra globals (e.g. a
-- hook main.lua normally defines that a logic file calls).
--
-- This doubles as a dialect linter for those files:
--   * PICO-8-only syntax (+=, !=, ?) fails to parse under LuaJIT.
--   * Touching math./table./string./ipairs/require raises an error, because
--     those globals don't exist on PICO-8 either.

local find_cart = require("cart")

local Env = {}

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

-- the files the cart #includes, in order, except main.lua
function Env.logic_files(root)
  local f = assert(io.open(find_cart(root), "r"))
  local src = f:read("*a")
  f:close()
  local files = {}
  for name in (src:match("__lua__\n(.-)\n__%a+__") or ""):gmatch("#include%s+(%S+)") do
    if name ~= "main.lua" then files[#files + 1] = name end
  end
  return files
end

-- rng(n) must return an integer in 1..n. PICO-8 code does flr(rnd(n)) + 1,
-- so rnd(n) hands back rng(n) - 1, which keeps test runs deterministic.
function Env.new(root, rng, opts)
  root = root or "."
  opts = opts or {}
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
    sub = function(s, i, j) return string.sub(s, i, j or -1) end,
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
  }
  for k, v in pairs(opts.globals or {}) do env[k] = v end

  setmetatable(env, {
    __index = function(_, key)
      error("pico8 copy touched undefined global '" .. tostring(key)
        .. "' (not a PICO-8 builtin and not defined by the cart)", 2)
    end,
  })

  for _, name in ipairs(opts.files or Env.logic_files(root)) do
    local path = root .. "/pico8/" .. name
    local chunk, err = loadfile(path)
    if not chunk then
      error("could not load " .. path .. " under LuaJIT -- is it using "
        .. "PICO-8-only syntax (+=, !=, ?)?\n" .. err)
    end
    setfenv(chunk, env)
    chunk()
  end

  return env
end

-- Deterministic LCG for reproducible "random" numbers in tests.
function Env.make_rng(seed)
  local s = seed
  return function(n)
    s = (s * 1103515245 + 12345) % 2147483648
    return (math.floor(s / 65536) % n) + 1
  end
end

return Env
