function love.conf(t)
  t.identity = "love-bacteria"
  t.version = "11.5"
  t.console = false

  t.window.title = "Bacteria Prototype"
  t.window.width = 960
  t.window.height = 720
  t.window.resizable = false
  t.window.vsync = 1
  t.window.msaa = 4
end
