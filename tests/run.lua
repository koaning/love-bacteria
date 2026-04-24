local suites = {
  "tests.test_rules",
  "tests.test_game",
  "tests.test_level",
  "tests.test_ai",
  "tests.test_input",
}

local function sorted_keys(tbl)
  local keys = {}
  for key in pairs(tbl) do
    keys[#keys + 1] = key
  end
  table.sort(keys)
  return keys
end

local total = 0
local failed = 0

for _, suite_name in ipairs(suites) do
  local suite = require(suite_name)

  for _, test_name in ipairs(sorted_keys(suite)) do
    local test_fn = suite[test_name]
    total = total + 1

    local ok, err = pcall(test_fn)
    if ok then
      io.write("PASS ", suite_name, ".", test_name, "\n")
    else
      failed = failed + 1
      io.write("FAIL ", suite_name, ".", test_name, "\n")
      io.write("  ", tostring(err), "\n")
    end
  end
end

local passed = total - failed
io.write(string.format("Ran %d tests: %d passed, %d failed\n", total, passed, failed))

if failed > 0 then
  os.exit(1)
end
