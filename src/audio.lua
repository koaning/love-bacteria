local Audio = {}
Audio.__index = Audio

local SAMPLE_RATE = 44100

local function clamp(value, minimum, maximum)
  if value < minimum then
    return minimum
  end

  if value > maximum then
    return maximum
  end

  return value
end

local function has_audio_runtime()
  return love
    and love.audio
    and love.audio.newSource
    and love.sound
    and love.sound.newSoundData
end

local function envelope(progress)
  local attack = 0.10
  local release = 0.20

  if progress < attack then
    return progress / attack
  end

  if progress > (1 - release) then
    return (1 - progress) / release
  end

  return 1
end

local function create_tone_source(frequency, duration, gain)
  local sample_count = math.max(1, math.floor(duration * SAMPLE_RATE))
  local progress_denominator = math.max(1, sample_count - 1)
  local sound_data = love.sound.newSoundData(sample_count, SAMPLE_RATE, 16, 1)

  for index = 0, sample_count - 1 do
    local t = index / SAMPLE_RATE
    local progress = index / progress_denominator
    local base = math.sin((2 * math.pi * frequency) * t)
    local harmonic = math.sin((2 * math.pi * frequency * 2) * t) * 0.35
    local shaped = (base + harmonic) * 0.55 * envelope(progress) * gain

    sound_data:setSample(index, clamp(shaped, -1, 1))
  end

  return love.audio.newSource(sound_data, "static")
end

function Audio.new()
  local self = setmetatable({}, Audio)
  self.enabled = false
  self.context = nil
  self.sfx = {}

  if not has_audio_runtime() then
    return self
  end

  local ok = pcall(function()
    self.sfx.menu_open = create_tone_source(370, 0.08, 0.30)
    self.sfx.navigate = create_tone_source(460, 0.05, 0.24)
    self.sfx.confirm = create_tone_source(620, 0.09, 0.30)
    self.sfx.game_start = create_tone_source(295, 0.12, 0.34)
    self.sfx.player_move = create_tone_source(520, 0.08, 0.30)
    self.sfx.enemy_move = create_tone_source(235, 0.10, 0.28)
  end)

  if not ok then
    self.sfx = {}
    return self
  end

  self.enabled = true
  return self
end

function Audio:play(effect_name)
  if not self.enabled then
    return
  end

  local source = self.sfx[effect_name]

  if not source then
    return
  end

  source:stop()
  source:play()
end

function Audio:set_context(next_context)
  if self.context == next_context then
    return
  end

  self.context = next_context

  if next_context == "menu" then
    self:play("menu_open")
    return
  end

  if next_context == "game" then
    self:play("game_start")
  end
end

return Audio
