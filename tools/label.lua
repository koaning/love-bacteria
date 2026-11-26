-- Writes a label (128 lines of 128 hex colours, as made by the preview
-- player's `--label`) into the cart's __label__ section, which PICO-8 needs
-- for `export` and shows on the cartridge.
--
-- Usage (repo root):  luajit tools/label.lua dist/label.txt [pico8/<game>.p8]

local label_path = assert(arg[1], "usage: luajit tools/label.lua <label.txt> [cart.p8]")
package.path = "tools/?.lua;" .. package.path
local cart = arg[2] or require("cart")()

local function read(path)
  local f = assert(io.open(path, "rb"), "cannot open " .. path)
  local s = f:read("*a")
  f:close()
  return s
end

local rows = {}
for l in read(label_path):gmatch("[^\n]+") do
  assert(#l == 128 and l:match("^[0-9a-v]+$"), "label rows must be 128 colour digits")
  rows[#rows + 1] = l
end
assert(#rows == 128, "label must have 128 rows, got " .. #rows)
local label = "__label__\n" .. table.concat(rows, "\n") .. "\n"

local src = read(cart)
-- drop an old label, then put the new one right after the code and the
-- sprites, where PICO-8 keeps it
src = src:gsub("__label__\n[^_]*", "")
local code = assert(src:find("__lua__\n", 1, true), "cart has no __lua__ section")
code = src:find("__gfx__\n", code, true) or code
local at = src:find("\n__%w+__\n", code)
local out = at and src:sub(1, at) .. label .. src:sub(at + 1) or src .. label

local f = assert(io.open(cart, "wb"))
f:write(out)
f:close()
print("wrote the label into " .. cart)
