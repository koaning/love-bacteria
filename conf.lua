function love.conf(t)
  t.identity = "love-bacteria"
  t.version = "11.5"
  t.console = false

  t.window.title = "Bacteria Prototype"
  t.window.width = 700
  t.window.height = 700
  t.window.resizable = false
  t.window.vsync = 1
  t.window.msaa = 4
end
