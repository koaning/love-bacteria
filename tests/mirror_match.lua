-- Mirror match: the LÖVE brain and the PICO-8 brain play the same games,
-- fed the same "random" numbers, and must agree on every single move.
--
-- Run from the repo root:  luajit tests/mirror_match.lua [--verbose]
--
-- On the first disagreement it prints the board, both moves, and exits 1.
-- That's the signal that love/src/ai.lua and pico8/ai.lua have drifted.

package.path = "love/?.lua;tools/?.lua;" .. package.path

local pico8_env = require("pico8_env")

-- love/src/ai.lua reads love.math.random at call time; we swap the function
-- per match so it shares a seed with the PICO-8 side.
_G.love = { math = {} }

local love_ai = require("src.ai")
local love_board = require("src.board")
local love_level = require("src.level")
local love_rules = require("src.rules")

local VERBOSE = arg and arg[1] == "--verbose"
local HISTORY_LIMIT = 8
local FIXED_POINT_MAX = 32767

-- { player_difficulty, enemy_difficulty, seed, max_plies }
-- Both editions only play 7x7. Hard is slow in pure Lua, so hard games get a
-- ply cap; the opening plies are where most branching happens anyway.
local MATCHES = {
  { "easy", "easy", 1, 200 },
  { "easy", "medium", 2, 200 },
  { "medium", "easy", 3, 200 },
  { "medium", "medium", 4, 200 },
  { "medium", "medium", 5, 200 },
  { "hard", "easy", 6, 16 },
  { "medium", "hard", 7, 16 },
  { "hard", "hard", 8, 10 },
}

local function move_str(m)
  if not m then
    return "pass"
  end
  return string.format("%s (%d,%d)->(%d,%d)", m.kind, m.from.x, m.from.y, m.to.x, m.to.y)
end

local function same_move(a, b)
  if not a or not b then
    return a == b
  end
  return a.kind == b.kind
    and a.from.x == b.from.x and a.from.y == b.from.y
    and a.to.x == b.to.x and a.to.y == b.to.y
end

local function board_str(state)
  local rows = {}
  for y = 1, state.height do
    local row = {}
    for x = 1, state.width do
      local c = state.cells[y][x]
      row[#row + 1] = c == "player" and "P" or c == "enemy" and "E" or "."
    end
    rows[#rows + 1] = "    " .. table.concat(row, " ")
  end
  return table.concat(rows, "\n")
end

local function states_match(a, b)
  if a.width ~= b.width or a.height ~= b.height then
    return false, "board size"
  end
  for y = 1, a.height do
    for x = 1, a.width do
      if a.cells[y][x] ~= b.cells[y][x] then
        return false, string.format("cell (%d,%d): %s vs %s", x, y, a.cells[y][x], b.cells[y][x])
      end
    end
  end
  for _, key in ipairs({ "current_player", "winner", "pass_count" }) do
    if a[key] ~= b[key] then
      return false, key .. ": " .. tostring(a[key]) .. " vs " .. tostring(b[key])
    end
  end
  return true
end

local function push_history(history, hash)
  history[#history + 1] = hash
  while #history > HISTORY_LIMIT do
    table.remove(history, 1)
  end
end

local function fail(label, ply, state, detail)
  io.write("\nDRIFT in ", label, " at ply ", ply, "\n")
  io.write(board_str(state), "\n")
  io.write("  ", detail, "\n")
  io.write("\nlove/src/ai.lua and pico8/ai.lua no longer think alike.\n")
  io.write("Port the change across (see MIRROR.md) and re-run `make mirror`.\n")
  os.exit(1)
end

local function play(match)
  local p_diff, e_diff, seed, max_plies = unpack(match)
  local label = string.format("%s vs %s (seed %d)", p_diff, e_diff, seed)

  love.math.random = pico8_env.make_rng(seed)
  local pico = pico8_env.new(".", pico8_env.make_rng(seed))

  local l_state = love_rules.resolve_state(love_level.load())
  local p_state = pico.rules_resolve_state(pico.level_load())
  local l_hist, p_hist = {}, {}
  local ply = 0
  local max_abs_score = 0

  local ok, why = states_match(l_state, p_state)
  if not ok then
    fail(label, ply, l_state, "opening position differs: " .. why)
  end

  while not l_state.winner and ply < max_plies do
    ply = ply + 1
    local side = l_state.current_player
    local diff = side == "player" and p_diff or e_diff

    -- PICO-8 has 16.16 fixed-point numbers: any score past 32767 would wrap
    -- on the cart even though it's fine here.
    for _, m in ipairs(pico.rules_get_legal_moves(p_state, side)) do
      local s = math.abs(pico.ai_score_move(p_state, side, m))
      if s > max_abs_score then
        max_abs_score = s
      end
      if s > FIXED_POINT_MAX then
        fail(label, ply, l_state, "pico8 score " .. s .. " overflows 16.16 fixed point for " .. move_str(m))
      end
    end

    local l_move = love_ai.choose_move(l_state, side, diff, l_hist)
    local p_move = pico.ai_choose_move(p_state, side, diff, p_hist)

    if not same_move(l_move, p_move) then
      fail(label, ply, l_state, string.format("%s (%s) -> love: %s | pico8: %s", side, diff, move_str(l_move), move_str(p_move)))
    end

    if l_move then
      l_state = love_rules.resolve_state(love_rules.apply_move(l_state, l_move))
      p_state = pico.rules_resolve_state(pico.rules_apply_move(p_state, p_move))
      push_history(l_hist, love_ai.state_hash(l_state))
      push_history(p_hist, pico.ai_state_hash(p_state))
    else
      l_state = love_rules.resolve_state(l_state)
      p_state = pico.rules_resolve_state(p_state)
    end

    ok, why = states_match(l_state, p_state)
    if not ok then
      fail(label, ply, l_state, "rules drift after " .. move_str(l_move) .. ": " .. why)
    end

    if VERBOSE then
      io.write(string.format("  %s ply %3d  %-6s %s\n", label, ply, side, move_str(l_move)))
    end
  end

  local result = l_state.winner or ("unfinished after " .. ply .. " plies")
  io.write(string.format("MATCH %-26s %3d plies agreed  winner: %-8s  peak |score| %d\n",
    label, ply, result, max_abs_score))
end

io.write("Mirror match: love/src/ai.lua vs pico8/ai.lua\n")
local started = os.clock()
for _, match in ipairs(MATCHES) do
  play(match)
end
io.write(string.format("All %d mirror matches agree (%.1fs).\n", #MATCHES, os.clock() - started))
