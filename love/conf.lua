function love.conf(t)
  local is_web = love and love.system and love.system.getOS and love.system.getOS() == "Web"

  local windowed = false
  if type(arg) == "table" then
    for _, a in ipairs(arg) do
      if a == "--windowed" or a == "-w" then
        windowed = true
        break
      end
    end
  end

  t.identity = "sporeline"
  t.version = "11.5"
  t.console = false

  t.window.title = "Sporeline"
  t.window.width = 700
  t.window.height = 700
  t.window.fullscreen = (not is_web) and (not windowed)
  t.window.fullscreentype = "desktop"
  t.window.resizable = is_web or windowed
  t.window.vsync = 1
  t.window.msaa = 4
end
