local Audio = {}
Audio.__index = Audio

local SAMPLE_RATE = 44100
local DEFAULT_SFX_VOLUME = 0.56
local DEFAULT_MUSIC_VOLUME = 0.50
local MUSIC_FADE_SPEED = 1.40
local SFX_LEVELS = {
  menu_open = 0.70,
  navigate = 0.62,
  confirm = 0.66,
  game_start = 0.72,
  player_move = 0.74,
  enemy_move = 0.70,
  cursor_move = 0.50,
  select = 0.64,
  invalid = 0.45,
  convert = 0.62,
  big_capture = 0.56,
  pass = 0.60,
  win = 0.64,
  lose = 0.60,
  tie = 0.58,
}

local function clamp(value, minimum, maximum)
  if value < minimum then
    return minimum
  end

  if value > maximum then
    return maximum
  end

  return value
end

local function approach(current, target, max_step)
  if current < target then
    return math.min(target, current + max_step)
  end

  if current > target then
    return math.max(target, current - max_step)
  end

  return current
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

local function safe_set_looping(source, looping)
  if source and source.setLooping then
    source:setLooping(looping)
  end
end

local function safe_set_volume(source, volume)
  if source and source.setVolume then
    source:setVolume(volume)
  end
end

local function safe_is_playing(source)
  if source and source.isPlaying then
    return source:isPlaying()
  end

  return false
end

local function safe_play(source)
  if source and source.play then
    source:play()
  end
end

local function safe_pause(source)
  if source and source.pause then
    source:pause()
  end
end

local function safe_stop(source)
  if source and source.stop then
    source:stop()
  end
end

local function load_source_if_exists(path, source_type)
  if not love or not love.filesystem or not love.filesystem.getInfo then
    return nil
  end

  if not love.filesystem.getInfo(path) then
    return nil
  end

  local ok, source = pcall(love.audio.newSource, path, source_type)

  if not ok then
    return nil
  end

  return source
end

local function load_first_source(paths, source_type)
  for _, path in ipairs(paths) do
    local source = load_source_if_exists(path, source_type)

    if source then
      return source
    end
  end

  return nil
end

local function create_tone_source(frequency, duration, gain)
  local sample_count = math.max(1, math.floor(duration * SAMPLE_RATE))
  local progress_denominator = math.max(1, sample_count - 1)
  local sound_data = love.sound.newSoundData(sample_count, SAMPLE_RATE, 16, 1)

  for index = 0, sample_count - 1 do
    local t = index / SAMPLE_RATE
    local progress = index / progress_denominator
    local base = math.sin((2 * math.pi * frequency) * t)
    local harmonic = math.sin((2 * math.pi * frequency * 1.5) * t) * 0.20
    local shaped = (base + harmonic) * 0.45 * envelope(progress) * gain

    sound_data:setSample(index, clamp(shaped, -1, 1))
  end

  return love.audio.newSource(sound_data, "static")
end

local function create_dual_tone_source(low_frequency, high_frequency, duration, gain)
  local sample_count = math.max(1, math.floor(duration * SAMPLE_RATE))
  local progress_denominator = math.max(1, sample_count - 1)
  local sound_data = love.sound.newSoundData(sample_count, SAMPLE_RATE, 16, 1)

  for index = 0, sample_count - 1 do
    local t = index / SAMPLE_RATE
    local progress = index / progress_denominator
    local low = math.sin((2 * math.pi * low_frequency) * t) * 0.74
    local high = math.sin((2 * math.pi * high_frequency) * t) * 0.20
    local shaped = (low + high) * envelope(progress) * gain * 0.78

    sound_data:setSample(index, clamp(shaped, -1, 1))
  end

  return love.audio.newSource(sound_data, "static")
end

local function create_music_loop_source(frequency_a, frequency_b, duration, gain)
  local sample_count = math.max(1, math.floor(duration * SAMPLE_RATE))
  local sound_data = love.sound.newSoundData(sample_count, SAMPLE_RATE, 16, 1)

  for index = 0, sample_count - 1 do
    local t = index / SAMPLE_RATE
    local drift = (math.sin((2 * math.pi * 0.061) * t) + 1) * 0.5
    local pulse = 0.78 + (((math.sin((2 * math.pi * 0.147) * t) + 1) * 0.5) * 0.16)
    local a = math.sin((2 * math.pi * (frequency_a + (drift * 2.0))) * t) * 0.58
    local b = math.sin((2 * math.pi * frequency_b) * t) * 0.42
    local shimmer = math.sin((2 * math.pi * (frequency_b * 1.5)) * t) * 0.10
    local sample = (a + b + shimmer) * 0.25 * pulse * gain

    sound_data:setSample(index, clamp(sample, -1, 1))
  end

  local source = love.audio.newSource(sound_data, "static")
  safe_set_looping(source, true)
  return source
end

local function semitone_ratio(semitones)
  return 2 ^ (semitones / 12)
end

local function smoothstep(value)
  local t = clamp(value, 0, 1)
  return t * t * (3 - (2 * t))
end

local function chord_voice_gain(index)
  if index == 1 then
    return 0.27
  end

  if index == 2 then
    return 0.20
  end

  if index == 3 then
    return 0.15
  end

  return 0.10
end

local function chord_sample(root_frequency, chord, t, drift)
  local root_shift = chord.root_shift or 0
  local intervals = chord.intervals or { 0, 4, 7, 11 }
  local chord_root = root_frequency * semitone_ratio(root_shift)
  local sample = math.sin((2 * math.pi * (chord_root * 0.5)) * t) * 0.13

  for index, interval in ipairs(intervals) do
    local note_frequency = (chord_root * semitone_ratio(interval)) + drift
    sample = sample + (math.sin((2 * math.pi * note_frequency) * t) * chord_voice_gain(index))
  end

  return sample
end

local function create_progression_music_loop_source(root_frequency, progression, bar_duration, gain)
  local chords = progression or {
    { root_shift = 0, intervals = { 0, 4, 7, 11 } },
  }
  local chord_count = math.max(1, #chords)
  local seconds_per_bar = bar_duration or 2.0
  local duration = seconds_per_bar * chord_count
  local sample_count = math.max(1, math.floor(duration * SAMPLE_RATE))
  local sound_data = love.sound.newSoundData(sample_count, SAMPLE_RATE, 16, 1)

  for index = 0, sample_count - 1 do
    local t = index / SAMPLE_RATE
    local bar_position = t / seconds_per_bar
    local bar_index = math.floor(bar_position)
    local bar_phase = bar_position - bar_index
    local current_index = (bar_index % chord_count) + 1
    local next_index = (current_index % chord_count) + 1
    local transition = smoothstep((bar_phase - 0.72) / 0.28)
    local drift = math.sin((2 * math.pi * 0.058) * t) * 1.6
    local pulse = 0.82 + (((math.sin((2 * math.pi * 0.52) * t) + 1) * 0.5) * 0.12)
    local shimmer = 0.92 + (((math.sin((2 * math.pi * 1.12) * t) + 1) * 0.5) * 0.08)
    local from_chord = chord_sample(root_frequency, chords[current_index], t, drift)
    local to_chord = chord_sample(root_frequency, chords[next_index], t, drift)
    local mixed = (from_chord * (1 - transition)) + (to_chord * transition)
    local sample = mixed * 0.19 * pulse * shimmer * gain

    sound_data:setSample(index, clamp(sample, -1, 1))
  end

  local source = love.audio.newSource(sound_data, "static")
  safe_set_looping(source, true)
  return source
end

function Audio.new()
  local self = setmetatable({}, Audio)
  self.enabled = false
  self.muted = false
  self.context = nil
  self.sfx_volume = DEFAULT_SFX_VOLUME
  self.music_volume = DEFAULT_MUSIC_VOLUME
  self.music_fade_speed = MUSIC_FADE_SPEED
  self.sfx = {}
  self.music_tracks = {}
  self.music_levels = {}
  self.target_music = nil

  if not has_audio_runtime() then
    return self
  end

  local ok = pcall(function()
    self.sfx.menu_open = load_first_source({
      "assets/audio/sfx/menu_open.ogg",
      "assets/audio/sfx/menu_open.wav",
    }, "static") or create_tone_source(370, 0.08, 0.30)

    self.sfx.navigate = load_first_source({
      "assets/audio/sfx/navigate.ogg",
      "assets/audio/sfx/navigate.wav",
    }, "static") or create_tone_source(460, 0.05, 0.24)

    self.sfx.confirm = load_first_source({
      "assets/audio/sfx/confirm.ogg",
      "assets/audio/sfx/confirm.wav",
    }, "static") or create_tone_source(620, 0.09, 0.30)

    self.sfx.game_start = load_first_source({
      "assets/audio/sfx/game_start.ogg",
      "assets/audio/sfx/game_start.wav",
    }, "static") or create_tone_source(295, 0.12, 0.34)

    self.sfx.player_move = load_first_source({
      "assets/audio/sfx/player_move.ogg",
      "assets/audio/sfx/player_move.wav",
    }, "static") or create_tone_source(520, 0.08, 0.30)

    self.sfx.enemy_move = load_first_source({
      "assets/audio/sfx/enemy_move.ogg",
      "assets/audio/sfx/enemy_move.wav",
    }, "static") or create_tone_source(235, 0.10, 0.28)

    self.sfx.cursor_move = load_first_source({
      "assets/audio/sfx/cursor_move.ogg",
      "assets/audio/sfx/cursor_move.wav",
    }, "static") or create_tone_source(440, 0.04, 0.18)

    self.sfx.select = load_first_source({
      "assets/audio/sfx/select.ogg",
      "assets/audio/sfx/select.wav",
    }, "static") or create_tone_source(690, 0.05, 0.22)

    self.sfx.invalid = load_first_source({
      "assets/audio/sfx/invalid.ogg",
      "assets/audio/sfx/invalid.wav",
    }, "static") or create_tone_source(190, 0.07, 0.20)

    self.sfx.convert = load_first_source({
      "assets/audio/sfx/convert.ogg",
      "assets/audio/sfx/convert.wav",
    }, "static") or create_dual_tone_source(410, 580, 0.11, 0.30)

    self.sfx.big_capture = load_first_source({
      "assets/audio/sfx/big_capture.ogg",
      "assets/audio/sfx/big_capture.wav",
    }, "static") or create_dual_tone_source(430, 860, 0.15, 0.36)

    self.sfx.pass = load_first_source({
      "assets/audio/sfx/pass.ogg",
      "assets/audio/sfx/pass.wav",
    }, "static") or create_tone_source(255, 0.09, 0.24)

    self.sfx.win = load_first_source({
      "assets/audio/sfx/win.ogg",
      "assets/audio/sfx/win.wav",
    }, "static") or create_dual_tone_source(510, 760, 0.16, 0.34)

    self.sfx.lose = load_first_source({
      "assets/audio/sfx/lose.ogg",
      "assets/audio/sfx/lose.wav",
    }, "static") or create_dual_tone_source(290, 180, 0.16, 0.32)

    self.sfx.tie = load_first_source({
      "assets/audio/sfx/tie.ogg",
      "assets/audio/sfx/tie.wav",
    }, "static") or create_dual_tone_source(330, 330, 0.14, 0.28)

    self.music_tracks.menu = load_first_source({
      "assets/audio/music/menu.ogg",
      "assets/audio/music/menu.wav",
    }, "stream") or create_music_loop_source(214, 320, 8.0, 0.95)

    self.music_tracks.game = load_first_source({
      "assets/audio/music/game.ogg",
      "assets/audio/music/game.wav",
    }, "stream") or create_progression_music_loop_source(196, {
      { root_shift = 0, intervals = { 0, 4, 7, 11 } },
      { root_shift = 5, intervals = { 0, 4, 7, 11 } },
      { root_shift = 7, intervals = { 0, 4, 7, 11 } },
      { root_shift = 0, intervals = { 0, 4, 7, 14 } },
    }, 4.0, 0.95)
  end)

  if not ok then
    self.sfx = {}
    self.music_tracks = {}
    self.music_levels = {}
    return self
  end

  for track_name, source in pairs(self.music_tracks) do
    safe_set_looping(source, true)
    safe_set_volume(source, 0)
    self.music_levels[track_name] = 0
  end

  self.enabled = true
  return self
end

function Audio:play(effect_name)
  if not self.enabled or self.muted then
    return
  end

  local source = self.sfx[effect_name]

  if not source then
    return
  end

  local level = SFX_LEVELS[effect_name] or 1
  safe_set_volume(source, self.sfx_volume * level)
  safe_stop(source)
  safe_play(source)
end

function Audio:is_muted()
  return self.muted
end

function Audio:toggle_muted()
  self.muted = not self.muted
  return self.muted
end

function Audio:get_sfx_volume()
  return self.sfx_volume or DEFAULT_SFX_VOLUME
end

function Audio:get_music_volume()
  return self.music_volume or DEFAULT_MUSIC_VOLUME
end

function Audio:adjust_sfx_volume(delta)
  local shift = delta or 0
  self.sfx_volume = clamp((self.sfx_volume or DEFAULT_SFX_VOLUME) + shift, 0, 1)
  return self.sfx_volume
end

function Audio:adjust_music_volume(delta)
  local shift = delta or 0
  self.music_volume = clamp((self.music_volume or DEFAULT_MUSIC_VOLUME) + shift, 0, 1)
  return self.music_volume
end

function Audio:get_status_text()
  if self.muted then
    return "Audio: Muted"
  end

  return "Audio: On"
end

function Audio:set_target_music(track_name)
  if self.target_music == track_name then
    return
  end

  self.target_music = track_name

  if not track_name then
    return
  end

  local source = self.music_tracks[track_name]

  if source and not safe_is_playing(source) then
    safe_play(source)
  end
end

function Audio:set_context(next_context)
  if self.context == next_context and self.target_music then
    return
  end

  self.context = next_context

  if next_context == "menu" then
    self:set_target_music("menu")
    self:play("menu_open")
    return
  end

  if next_context == "game" then
    self:set_target_music("game")
    self:play("game_start")
    return
  end

  self:set_target_music(nil)
end

function Audio:update(dt)
  if not self.enabled then
    return
  end

  local delta = dt or 0
  local fade_step = math.max(0, delta * self.music_fade_speed)

  for track_name, source in pairs(self.music_tracks) do
    local target_volume = 0
    if not self.muted and self.target_music == track_name then
      target_volume = self.music_volume
    end

    local current_volume = self.music_levels[track_name] or 0
    local next_volume = target_volume

    if fade_step > 0 then
      next_volume = approach(current_volume, target_volume, fade_step)
    end

    self.music_levels[track_name] = next_volume
    safe_set_volume(source, next_volume)

    if next_volume > 0.001 then
      if not safe_is_playing(source) then
        safe_play(source)
      end
    elseif self.target_music ~= track_name and safe_is_playing(source) then
      safe_pause(source)
    end
  end
end

return Audio
