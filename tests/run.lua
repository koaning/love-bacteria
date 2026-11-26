-- Repo-wide test entry point: `luajit tests/run.lua` from the repo root.
-- (CI calls this path; `make test` runs the same.)
--
--   1. PICO-8 brain unit tests   tests/test_brain.lua
--   2. PICO-8 cart smoke test    tests/cart_smoke.lua
--   3. PICO-8 token meter        tools/p8tokens.lua

local steps = {
  { "brain unit tests", "luajit tests/test_brain.lua" },
  { "cart smoke test", "luajit tests/cart_smoke.lua" },
  { "token meter", "luajit tools/p8tokens.lua" },
}

local failed = {}
for _, step in ipairs(steps) do
  io.write("== ", step[1], "\n")
  io.flush()
  local r = os.execute(step[2])
  if not (r == 0 or r == true) then
    failed[#failed + 1] = step[1]
  end
end

if #failed > 0 then
  io.write("\nFAILED: ", table.concat(failed, ", "), "\n")
  os.exit(1)
end
io.write("\nAll suites passed.\n")
