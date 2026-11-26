-- game.lua is written by `make pico8-preview` from GAME and TITLE in game.mk
local ok, game = pcall(require, "game")
if not ok then game = { game = "pico8", title = "PICO-8" } end

function love.conf(t)
  t.identity = game.game .. "-p8-preview"
  t.version = "11.5"
  t.window.title = game.title .. " (PICO-8 preview)"
  t.window.width = 512
  t.window.height = 512
  t.window.resizable = true
  t.modules.physics = false
  t.modules.video = false
end
