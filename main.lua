local Game = require("src.game")
local render = require("src.render")

local game

function love.load()
  love.math.setRandomSeed(os.time())
  love.graphics.setLineStyle("smooth")
  love.graphics.setLineJoin("round")

  render.load()
  game = Game.new()
end

function love.update(dt)
  game:update(dt)
end

function love.draw()
  game:draw()
end

function love.mousepressed(x, y, button)
  game:mousepressed(x, y, button)
end

function love.keypressed(key)
  game:keypressed(key)
end
