-- Approximate PICO-8 token meter for the cart.
--
-- Usage (repo root):  luajit tools/p8tokens.lua [pico8/<game>.p8]
--
-- Follows the rules from the PICO-8 manual: every name, keyword, literal,
-- operator and opening bracket is one token; comments, `,` `.` `:` `;` `::`
-- closing brackets, `end`, `local` are free, and a unary minus in front of a
-- number literal is folded into it. PICO-8's own counter is the authority;
-- this one is usually within a few percent and is good for spotting trends.

local LIMIT = 8192
package.path = "tools/?.lua;" .. package.path
local cart = arg[1] or require("cart")()
local dir = cart:match("^(.*)/") or "."

local function read(path)
  local f = assert(io.open(path, "r"), "cannot open " .. path)
  local s = f:read("*a")
  f:close()
  return s
end

local FREE = {
  [","] = true, ["."] = true, [":"] = true, [";"] = true, ["::"] = true,
  [")"] = true, ["]"] = true, ["}"] = true, ["end"] = true, ["local"] = true,
}

local OPS = {
  "...", "..=", "<<>", ">>>", ">><", "^^=",
  "==", "~=", "!=", "<=", ">=", "..", "::", "+=", "-=", "*=", "/=", "%=",
  "<<", ">>", "\\=", "|=", "&=", "^^",
}

local function count(src)
  local n, i, len = 0, 1, #src
  local prev_value = false -- was the previous token something a binary op could follow?

  while i <= len do
    local c = src:sub(i, i)

    if c:match("%s") then
      i = i + 1
    elseif src:sub(i, i + 3) == "--[[" or src:sub(i, i + 3) == "--[=" then
      local eq = src:match("^%-%-%[(=*)%[", i)
      local close = src:find("]" .. eq .. "]", i, true)
      i = (close or len) + #eq + 2
    elseif src:sub(i, i + 1) == "--" or src:sub(i, i + 1) == "//" then
      i = (src:find("\n", i, true) or len) + 1
    elseif c == '"' or c == "'" then
      local j = i + 1
      while j <= len and src:sub(j, j) ~= c do
        if src:sub(j, j) == "\\" then j = j + 1 end
        j = j + 1
      end
      n, i, prev_value = n + 1, j + 1, true
    elseif src:match("^%[=*%[", i) then
      local eq = src:match("^%[(=*)%[", i)
      local close = src:find("]" .. eq .. "]", i, true)
      n, i, prev_value = n + 1, (close or len) + #eq + 2, true
    elseif c:match("[%a_]") then
      local word = src:match("^[%w_]+", i)
      if not FREE[word] then n = n + 1 end
      i = i + #word
      prev_value = not ({ ["and"] = 1, ["or"] = 1, ["not"] = 1, ["return"] = 1,
        ["then"] = 1, ["do"] = 1, ["else"] = 1, ["in"] = 1, ["local"] = 1 })[word]
    elseif c:match("%d") or (c == "." and src:sub(i + 1, i + 1):match("%d")) then
      local num = src:match("^0[xX][%x%.]+", i) or src:match("^0[bB][01%.]+", i)
        or src:match("^%d*%.?%d+[eE][%+%-]?%d+", i) or src:match("^%d*%.?%d*", i)
      n, i, prev_value = n + 1, i + #num, true
    else
      local op = c
      for _, candidate in ipairs(OPS) do
        if src:sub(i, i + #candidate - 1) == candidate then
          op = candidate
          break
        end
      end
      i = i + #op
      local unary_minus_on_literal = op == "-" and not prev_value
        and src:sub(i):match("^%s*[%d%.]")
      if not FREE[op] and not unary_minus_on_literal then
        n = n + 1
      end
      prev_value = op == ")" or op == "]" or op == "}"
    end
  end

  return n
end

local rows, total = {}, 0
for line in read(cart):match("__lua__\n(.-)\n__%a+__") :gmatch("[^\n]+") do
  local inc = line:match("^#include%s+(%S+)")
  if inc then
    local t = count(read(dir .. "/" .. inc))
    rows[#rows + 1] = { inc, t }
    total = total + t
  else
    total = total + count(line)
  end
end

for _, row in ipairs(rows) do
  io.write(string.format("  %-10s %5d\n", row[1], row[2]))
end

local width = 32
local filled = math.floor(total / LIMIT * width + 0.5)
io.write(string.format("  %-10s %5d / %d  [%s%s] %d%%\n", "cart", total, LIMIT,
  string.rep("#", filled), string.rep(".", width - filled), math.floor(total / LIMIT * 100)))

if total > LIMIT then
  io.write("Over the PICO-8 token limit!\n")
  os.exit(1)
end
