-- Unit tests for the PICO-8 board, rules, and AI inside the PICO-8 sandbox.
-- Run from the repo root:  luajit tests/test_brain.lua

package.path = "tools/?.lua;" .. package.path
local pico8_env = require("pico8_env")

local function assert_eq(actual, expected, msg)
  if actual ~= expected then
    error((msg or "assertion failed") .. ": expected " .. tostring(expected) .. ", got " .. tostring(actual), 2)
  end
end

local function assert_true(val, msg)
  if not val then
    error(msg or "expected truthy value", 2)
  end
end

local function move_matches(a, b)
  return a and b and a.kind == b.kind
    and a.from.x == b.from.x and a.from.y == b.from.y
    and a.to.x == b.to.x and a.to.y == b.to.y
end

local function move_exists(moves, cand)
  for _, m in ipairs(moves) do
    if move_matches(m, cand) then return true end
  end
  return false
end

local function fill_board(env, st, side)
  for y = 1, st.height do
    for x = 1, st.width do
      env.board_set_cell(st, x, y, side)
    end
  end
end

local tests = {}

function tests.level_load_is_7x7_with_corner_spores(env)
  local st = env.level_load()
  assert_eq(st.width, 7)
  assert_eq(st.height, 7)
  assert_eq(env.board_get_cell(st, 1, 1), "player")
  assert_eq(env.board_get_cell(st, 7, 7), "player")
  assert_eq(env.board_get_cell(st, 1, 7), "enemy")
  assert_eq(env.board_get_cell(st, 7, 1), "enemy")
  assert_eq(env.board_count_cells(st, "player"), 2)
  assert_eq(env.board_count_cells(st, "enemy"), 2)
end

function tests.piece_moves_cover_8_grows_and_4_orthogonal_jumps(env)
  local st = env.board_new_state(7, 7)
  env.board_set_cell(st, 4, 4, "player")
  local moves = env.rules_get_piece_moves(st, "player", 4, 4)
  local grows, jumps = 0, 0
  for _, m in ipairs(moves) do
    local dx, dy = math.abs(m.to.x - 4), math.abs(m.to.y - 4)
    if m.kind == "grow" then
      assert_true(math.max(dx, dy) == 1, "grow must be adjacent")
      grows = grows + 1
    else
      assert_true((dx == 2 and dy == 0) or (dx == 0 and dy == 2), "jump must be 2 cells orthogonally")
      jumps = jumps + 1
    end
  end
  assert_eq(grows, 8)
  assert_eq(jumps, 4)
end

function tests.apply_move_converts_adjacent_enemies(env)
  local st = env.board_new_state(7, 7)
  env.board_set_cell(st, 2, 2, "player")
  env.board_set_cell(st, 4, 2, "enemy")
  env.board_set_cell(st, 4, 3, "enemy")
  local next_st = env.rules_apply_move(st, { kind = "grow", from = { x = 2, y = 2 }, to = { x = 3, y = 2 } })
  assert_eq(env.board_get_cell(next_st, 2, 2), "player")
  assert_eq(env.board_get_cell(next_st, 3, 2), "player")
  assert_eq(env.board_get_cell(next_st, 4, 2), "player")
  assert_eq(env.board_get_cell(next_st, 4, 3), "player")
  assert_eq(next_st.last_move.converted, 2)
  assert_eq(next_st.current_player, "enemy")
end

function tests.resolve_state_passes_when_active_side_is_stuck(env)
  local st = env.board_new_state(7, 7)
  fill_board(env, st, "enemy")
  env.board_set_cell(st, 1, 1, "player")
  env.board_set_cell(st, 7, 7, "empty")
  env.board_set_cell(st, 7, 6, "empty")
  env.board_set_cell(st, 6, 7, "empty")
  st.current_player = "player"

  local resolved = env.rules_resolve_state(st)
  assert_eq(resolved.current_player, "enemy")
  assert_eq(resolved.winner, nil)
  assert_eq(#env.rules_get_legal_moves(resolved, "player"), 0)
end

function tests.resolve_state_declares_winner_when_both_sides_are_stuck(env)
  local st = env.board_new_state(3, 3)
  fill_board(env, st, "enemy")
  env.board_set_cell(st, 1, 1, "player")
  st.current_player = "player"

  local resolved = env.rules_resolve_state(st)
  assert_eq(resolved.winner, "enemy")
end

function tests.easy_bot_prefers_grow_moves(env)
  local st = env.level_load()
  st.current_player = "enemy"
  local legal = env.rules_get_legal_moves(st, "enemy")
  local m = env.ai_choose_move(st, "enemy", "easy")
  assert_true(m, "easy bot should return a move")
  assert_true(move_exists(legal, m), "easy bot move must be legal")
  assert_eq(m.kind, "grow")
end

function tests.medium_and_hard_bots_return_legal_moves(env)
  local st = env.level_load()
  st.current_player = "enemy"
  local legal = env.rules_get_legal_moves(st, "enemy")
  assert_true(move_exists(legal, env.ai_choose_move(st, "enemy", "medium")))
  assert_true(move_exists(legal, env.ai_choose_move(st, "enemy", "hard")))
end

function tests.hard_bot_looks_beyond_one_ply(env)
  local st = env.board_new_state(7, 7)
  env.board_set_cell(st, 1, 1, "player")
  env.board_set_cell(st, 7, 1, "enemy")
  env.board_set_cell(st, 2, 2, "player")
  env.board_set_cell(st, 6, 2, "enemy")
  env.board_set_cell(st, 1, 7, "enemy")
  env.board_set_cell(st, 7, 7, "player")
  st.current_player = "enemy"

  local legal = env.rules_get_legal_moves(st, "enemy")
  local best_1ply, best_s = nil, nil
  for _, m in ipairs(legal) do
    local s = env.ai_score_move(st, "enemy", m)
    if not best_s or s > best_s then best_1ply, best_s = m, s end
  end
  local hard = env.ai_choose_move(st, "enemy", "hard")
  assert_true(hard, "hard bot should return a move")
  assert_eq(move_matches(best_1ply, hard), false, "hard bot should look past 1 ply")
end

function tests.hard_bot_avoids_history_and_falls_back_when_forced(env)
  local st = env.level_load()
  st.current_player = "enemy"
  local first = env.ai_choose_move(st, "enemy", "hard")
  local res = env.rules_resolve_state(env.rules_apply_move(st, first))
  local second = env.ai_choose_move(st, "enemy", "hard", { env.ai_state_hash(res) })
  assert_eq(move_matches(first, second), false, "hard bot should avoid repeating history")

  local all_hashes = {}
  for _, m in ipairs(env.rules_get_legal_moves(st, "enemy")) do
    all_hashes[#all_hashes + 1] = env.ai_state_hash(env.rules_resolve_state(env.rules_apply_move(st, m)))
  end
  assert_true(env.ai_choose_move(st, "enemy", "hard", all_hashes), "must fall back if all moves repeat")
end

function tests.choose_move_returns_nil_without_legal_moves(env)
  local st = env.board_new_state(3, 3)
  fill_board(env, st, "enemy")
  st.current_player = "enemy"
  assert_eq(env.ai_choose_move(st, "enemy", "easy"), nil)
  assert_eq(env.ai_choose_move(st, "enemy", "medium"), nil)
  assert_eq(env.ai_choose_move(st, "enemy", "hard"), nil)
end

function tests.scores_stay_within_pico8_fixed_point_range(env)
  local st = env.level_load()
  for _, m in ipairs(env.rules_get_legal_moves(st, "player")) do
    local s = env.ai_score_move(st, "player", m)
    assert_true(math.abs(s) <= 32767, "score out of 16.16 range: " .. tostring(s))
  end
end

local names = {}
for k in pairs(tests) do names[#names + 1] = k end
table.sort(names)

local passed = 0
for _, name in ipairs(names) do
  local env = pico8_env.new(".", pico8_env.make_rng(1))
  tests[name](env)
  print("PASS " .. name)
  passed = passed + 1
end
print("Brain unit tests: " .. passed .. " passed, 0 failed.")
