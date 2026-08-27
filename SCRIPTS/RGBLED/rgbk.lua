-- rgbk.lua - All-in-one RGB LED keeper for the RGB LED tool (EdgeTX 2.11+)
--
-- Install this file as /SCRIPTS/RGBLED/rgbk.lua on the radio SD card.
-- The RGB LED tool (/SCRIPTS/TOOLS/RGB.lua) points the native "RGB Led"
-- Special Function (SF64) at this script. EdgeTX loads it straight from
-- /SCRIPTS/RGBLED/. The tool creates the Special Function once and this
-- script polls /SCRIPTS/TOOLS/RGB.dat, switching between the built-in LED
-- modes on its own. Selecting a mode in the tool takes effect the moment
-- the tool exits.
--
-- All mode logic is embedded here; the individual mode scripts in
-- /SCRIPTS/RGBLED/ are not needed by this keeper.
--
-- The tool previews modes through the exported apply() function, so the
-- on-screen preview matches exactly what the keeper runs on the radio.

local CFG = "/SCRIPTS/TOOLS/RGB.dat"

-- Decorative ("bling") LEDs only. Firmware maps Lua index 0 to the first
-- gimbal/bling LED. Function-switch LEDs stay under model on/off colours /
-- setCFSLedColor() and must not be painted here.
local function decorativeLength()
  if type(BLING_LED_STRIP_LENGTH) == "number" and BLING_LED_STRIP_LENGTH > 0 then
    return BLING_LED_STRIP_LENGTH
  end
  local n = LED_STRIP_LENGTH or 0
  if type(CFS_LED_STRIP_LENGTH) == "number" and CFS_LED_STRIP_LENGTH > 0 and n >= CFS_LED_STRIP_LENGTH then
    return n - CFS_LED_STRIP_LENGTH
  end
  -- Pre-constant firmware: TX16S Mk3 / GX15 / TX15 report 20 bling + 6 CFS.
  if n == 26 then return 20 end
  return n
end

local N = decorativeLength()
local HALF = math.max(1, math.floor(N / 2))

-- Bound every write to the decorative range so leftover CFS indices are never
-- touched, even if a pattern hardcodes a 10+10 gimbal layout.
local _setRGB = setRGBLedColor
local _applyRGB = applyRGBLedColors

local function setRGBLedColor(id, r, g, b)
  if type(_setRGB) ~= "function" then return false end
  if type(id) ~= "number" or id < 0 or id >= N then return false end
  return _setRGB(id, r, g, b)
end

local function applyRGBLedColors()
  if type(_applyRGB) == "function" then
    _applyRGB()
  end
end

local curSel = nil
local runFn = nil

------------------------------------------------------------------------
-- Shared helpers
------------------------------------------------------------------------

local function floor(v)
  return math.floor(v)
end

local function clamp(v, lo, hi)
  return math.max(lo, math.min(hi, v))
end

-- Hue wheel. slope: 3 = smooth rainbow, larger = tighter transitions.
-- bgR/bgG/bgB: when given, colours close to the background are skipped.
local function hue(phase, length, slope, bgR, bgG, bgB)
  slope = slope or 3
  local position = (phase % length) / length
  local r, g, b = 0, 0, 0
  if position < 1 / 3 then
    r = 255 * (1 - slope * position)
    g = 255 * (slope * position)
  elseif position < 2 / 3 then
    position = position - 1 / 3
    g = 255 * (1 - slope * position)
    b = 255 * (slope * position)
  else
    position = position - 2 / 3
    b = 255 * (1 - slope * position)
    r = 255 * (slope * position)
  end
  if bgR and math.abs(r - bgR) < 30 and math.abs(g - bgG) < 30 and math.abs(b - bgB) < 30 then
    return hue((phase + 1) % length, length, slope, bgR, bgG, bgB)
  end
  return r, g, b
end



-- STICKTEST-exact stick readout.  STICKTEST.lua hardcodes 10 LEDs per ring
-- (indices 0..9 right gimbal, 10..19 left gimbal) and literal "% 10" - it
-- does NOT use HALF/LED_STRIP_LENGTH for the ring math.  Any pattern that
-- goes through HALF instead breaks on radios where LED_STRIP_LENGTH != 20.
-- The helpers below use the exact same constants and sign conventions as
-- STICKTEST.lua so behaviour matches on the radio.

local RING_SEGS = 10  -- LEDs per ring, fixed by STICKTEST.lua
local STICK_DZ  = 0.08  -- deadzone, fixed by STICKTEST.lua

-- Return the physical {x=right, y=up} stick vector for the RIGHT gimbal.
local function rightStick()
  local rx = -(getValue("ail") or 0) / 1024  -- physical RIGHT = positive
  local ry =  (getValue("ele") or 0) / 1024  -- physical UP    = positive
  return rx, ry
end

-- Return the physical {x=right, y=up} stick vector for the LEFT gimbal.
local function leftStick()
  local lx =  (getValue("rud") or 0) / 1024  -- physical RIGHT = positive
  local ly =  (getValue("thr") or 0) / 1024  -- physical UP    = positive
  return lx, ly
end

-- Map a stick vector to the two straddling LED offsets within a ring.
-- Returns lower, upper (both 0..9), magnitude, angle  -- or nil if deadzoned.
local function stickPair(x, y)
  local len = math.sqrt(x * x + y * y)
  if len <= STICK_DZ then return nil end
  local angle = math.atan(y, x)
  angle = (math.deg(angle) + 360) % 360
  local segment = angle / 36
  local lower = math.floor(segment) % RING_SEGS
  local upper = (lower + 1) % RING_SEGS
  return lower, upper, len, angle
end


------------------------------------------------------------------------
-- Mode builders (each returns a run() closure holding its own state)
------------------------------------------------------------------------

local function solid(r, g, b)
  return function()
    for i = 0, N - 1 do setRGBLedColor(i, r, g, b) end
    applyRGBLedColors()
  end
end

-- Single lit LED scrolling over a dim background; optionally the lit LED
-- cycles through rainbow colours that avoid colours close to the background
local function scroll(fwd, bgR, bgG, bgB, colorCycle)
  local oldtime = getTime()
  local cyc = fwd and 0 or (N - 1)
  local phase = 0
  return function()
    for i = 0, N - 1 do
      if i == cyc then
        if colorCycle then
          local r, g, b = hue(phase, 255, 3, bgR, bgG, bgB)
          setRGBLedColor(i, r, g, b)
        else
          setRGBLedColor(i, 0, 50, 0)
        end
      else
        setRGBLedColor(i, bgR, bgG, bgB)
      end
    end
    if (getTime() - oldtime) > 8 then
      oldtime = getTime()
      if fwd then
        cyc = cyc + 1
        if cyc >= N then cyc = 0 end
      else
        cyc = cyc - 1
        if cyc < 0 then cyc = N - 1 end
      end
    end
    if colorCycle then phase = (phase + 1) % 255 end
    applyRGBLedColors()
  end
end

-- Whole-strip rainbow flowing along the LEDs
local function rainbowStrip(interval, slope)
  local oldtime = getTime()
  local phase = 0
  return function()
    if (getTime() - oldtime) > interval then
      oldtime = getTime()
      phase = (phase + 1) % 255
      for i = 0, N - 1 do
        local r, g, b = hue(phase + i * 64, 255, slope)
        setRGBLedColor(i, r, g, b)
      end
      applyRGBLedColors()
    end
  end
end

-- Whole strip pulses through the colour cycle together
local function loopColor()
  local cycleTime = getTime()
  local phase = 0
  return function()
    if (getTime() - cycleTime) > 2 then
      cycleTime = getTime()
      phase = phase + 1
    end
    local r, g, b = hue(phase, 255, 3)
    r = clamp(r, 0, 255)
    g = clamp(g, 0, 255)
    b = clamp(b, 0, 255)
    for i = 0, N - 1 do setRGBLedColor(i, r, g, b) end
    applyRGBLedColors()
  end
end

-- Fill-up runner with complementary background colour
local function runner()
  local colorChangeTime = getTime()
  local phase = 0
  local currentLed = 0
  return function()
    if (getTime() - colorChangeTime) > 2 then
      colorChangeTime = getTime()
      phase = phase + 1
      currentLed = (currentLed + 1) % N
    end
    local r, g, b = hue(phase, 255, 3)
    for i = 0, N - 1 do
      if i <= currentLed then
        setRGBLedColor(i, r, g, b)
      else
        local bg_r = (r + 128) % 256
        local bg_g = (g + 128) % 256
        local bg_b = (b + 128) % 256
        if bg_r > bg_g and bg_r > bg_b then
          bg_r = 0
        elseif bg_g > bg_r and bg_g > bg_b then
          bg_g = 0
        else
          bg_b = 0
        end
        setRGBLedColor(i, bg_r, bg_g, bg_b)
      end
    end
    applyRGBLedColors()
  end
end

-- Alternating red/blue halves swapping place
local function police()
  local oldtime = getTime()
  local cyc = 0
  return function()
    for i = 0, N - 1 do
      if i % 2 == cyc then
        setRGBLedColor(i, 0, 0, 50)
      else
        setRGBLedColor(i, 50, 0, 0)
      end
    end
    if (getTime() - oldtime) > 8 then
      oldtime = getTime()
      cyc = 1 - cyc
    end
    applyRGBLedColors()
  end
end

-- Gimbal ring feedback: solid base colour with two full-white LEDs marking
-- the stick direction on each ring.  The stick-reading, angle, segment and
-- two-LED straddling logic is inlined verbatim from STICKTEST.lua so the
-- on-radio behaviour is guaranteed identical.  STICKTEST hardcodes 10 LEDs
-- per ring (indices 0..9 right, 10..19 left) and literal "% 10"; this does
-- the same instead of going through HALF, which varies with LED_STRIP_LENGTH.
local function gimbal(baseR, baseG, baseB)
  return function()
    -- Fill the whole strip with the base colour first.
    for i = 0, N - 1 do
      setRGBLedColor(i, baseR, baseG, baseB)
    end

    local len, angle, segment, lower, upper

    -- ===== Right gimbal -> LEDs 0..9 (verbatim STICKTEST logic) =====
    local rx = -(getValue("ail") or 0) / 1024  -- physical RIGHT = positive
    local ry =  (getValue("ele") or 0) / 1024  -- physical UP    = positive
    len = math.sqrt(rx * rx + ry * ry)
    if len > 0.08 then
      angle = math.atan(ry, rx)
      angle = (math.deg(angle) + 360) % 360
      segment = angle / 36
      lower = math.floor(segment) % 10
      upper = (lower + 1) % 10
      setRGBLedColor(lower, 255, 255, 255)
      setRGBLedColor(upper, 255, 255, 255)
    end

    -- ===== Left gimbal -> LEDs 10..19 (verbatim STICKTEST logic) =====
    local lx =  (getValue("rud") or 0) / 1024  -- physical RIGHT = positive
    local ly =  (getValue("thr") or 0) / 1024  -- physical UP    = positive
    len = math.sqrt(lx * lx + ly * ly)
    if len > 0.08 then
      angle = math.atan(ly, lx)
      angle = (math.deg(angle) + 360) % 360
      segment = angle / 36
      lower = math.floor(segment) % 10
      upper = (lower + 1) % 10
      local led1 = 10 + lower
      local led2 = 10 + upper
      setRGBLedColor(led1, 255, 255, 255)
      setRGBLedColor(led2, 255, 255, 255)
    end

    applyRGBLedColors()
  end
end

------------------------------------------------------------------------
-- New patterns
------------------------------------------------------------------------

-- Breath: whole ring slowly fades in and out (calm idle)
local function breath()
  local oldtime = getTime()
  local ph = 0
  return function()
    if (getTime() - oldtime) > 2 then
      oldtime = getTime()
      ph = (ph + 1) % 128
    end
    local lvl = (1 - math.cos(ph / 128 * 2 * math.pi)) / 2
    local v = floor(lvl * 70)
    for i = 0, N - 1 do setRGBLedColor(i, v, v, v) end
    applyRGBLedColors()
  end
end

-- Comet: bright leading pixel with a fading tail behind it
local function comet()
  local oldtime = getTime()
  local pos = 0
  return function()
    if (getTime() - oldtime) > 2 then
      oldtime = getTime()
      pos = (pos + 1) % N
    end
    for i = 0, N - 1 do setRGBLedColor(i, 0, 0, 0) end
    local col = { 0, 220, 255 }
    for d = 0, 3 do
      local idx = (pos - d) % N
      if d == 0 then
        setRGBLedColor(idx, 255, 255, 255)
      else
        local f = 1 - d / 4
        setRGBLedColor(idx, floor(col[1] * f), floor(col[2] * f), floor(col[3] * f))
      end
    end
    applyRGBLedColors()
  end
end

-- Chase: 3 LEDs run continuously around the ring
local function chase()
  local oldtime = getTime()
  local pos = 0
  return function()
    if (getTime() - oldtime) > 2 then
      oldtime = getTime()
      pos = (pos + 1) % N
    end
    for i = 0, N - 1 do
      local d = (i - pos) % N
      if d < 3 then
        local f = 1 - d / 3
        setRGBLedColor(i, 0, floor(200 * f), 0)
      else
        setRGBLedColor(i, 0, 10, 0)
      end
    end
    applyRGBLedColors()
  end
end

-- Spinner: small bright arc rotating around the ring
local function spinner()
  local oldtime = getTime()
  local pos = 0
  return function()
    if (getTime() - oldtime) > 3 then
      oldtime = getTime()
      pos = (pos + 1) % N
    end
    for i = 0, N - 1 do
      local d = (i - pos) % N
      if d < 3 then
        local f = 1 - d / 3
        setRGBLedColor(i, floor(40 * f), floor(200 * f), floor(255 * f))
      else
        setRGBLedColor(i, 0, 0, 8)
      end
    end
    applyRGBLedColors()
  end
end

-- DualSpinner: both gimbal rings spin in opposite directions
local function dualSpinner()
  local oldtime = getTime()
  local p0 = 0
  local p1 = 0
  return function()
    if (getTime() - oldtime) > 3 then
      oldtime = getTime()
      p0 = (p0 + 1) % HALF
      p1 = (p1 + HALF - 1) % HALF
    end
    for i = 0, N - 1 do setRGBLedColor(i, 0, 0, 8) end
    for d = 0, 2 do
      local f = 1 - d / 3
      local idx0 = (p0 - d + HALF) % HALF
      local idx1 = (p1 + d) % HALF
      setRGBLedColor(idx0, floor(0), floor(200 * f), floor(255 * f))
      setRGBLedColor(idx1 + HALF, floor(255 * f), floor(60 * f), floor(220 * f))
    end
    applyRGBLedColors()
  end
end

-- PingPong: light travels around and reverses at the ends
local function pingPong()
  local oldtime = getTime()
  local pos = 0
  local dir = 1
  return function()
    if (getTime() - oldtime) > 2 then
      oldtime = getTime()
      pos = pos + dir
      if pos >= N then pos = N - 2 dir = -1 end
      if pos < 0 then pos = 1 dir = 1 end
    end
    for i = 0, N - 1 do setRGBLedColor(i, 0, 0, 0) end
    for d = 0, 2 do
      local idx = pos - dir * d
      idx = (idx % N + N) % N
      local f = 1 - d / 3
      setRGBLedColor(idx, floor(220 * f), floor(220 * f), floor(255 * f))
    end
    applyRGBLedColors()
  end
end

-- PingPong with a colour and a gaussian tail (used for Knight)
local function pingPongWithColor(r, g, b)
  local oldtime = getTime()
  local pos = 0
  local dir = 1
  return function()
    if (getTime() - oldtime) > 2 then
      oldtime = getTime()
      pos = pos + dir
      if pos >= N then pos = N - 2 dir = -1 end
      if pos < 0 then pos = 1 dir = 1 end
    end
    for i = 0, N - 1 do
      local dist = math.abs((i - pos + N) % N)
      if dist > N / 2 then dist = N - dist end
      local f = math.exp(-dist * 0.5)
      setRGBLedColor(i, floor(r * f), floor(g * f), floor(b * f))
    end
    applyRGBLedColors()
  end
end

-- Knight: KITT/Cylon, bright centre with fading tail, reversing
local function knight()
  return pingPongWithColor(200, 0, 0)
end

-- Sparkle: random LEDs briefly flash
local function sparkle()
  local buf = {}
  for i = 0, N - 1 do buf[i] = 0 end
  local oldtime = getTime()
  local tick = 0
  return function()
    if (getTime() - oldtime) > 3 then
      oldtime = getTime()
      tick = tick + 1
      if tick % 2 == 0 then
        buf[math.random(0, N - 1)] = 255
      end
    end
    for i = 0, N - 1 do
      buf[i] = floor(buf[i] * 0.85)
      local v = buf[i]
      setRGBLedColor(i, floor(v * 0.8), floor(v * 0.9), v)
    end
    applyRGBLedColors()
  end
end

-- Twinkle: each LED fades in and out independently
local function twinkle()
  local phase = {}
  local speed = {}
  for i = 0, N - 1 do
    phase[i] = math.random(0, 628)
    speed[i] = 1 + math.random(0, 4)
  end
  local oldtime = getTime()
  local t = 0
  return function()
    if (getTime() - oldtime) > 5 then
      oldtime = getTime()
      t = t + 1
    end
    for i = 0, N - 1 do
      local s = math.sin((t * speed[i] + phase[i]) / 100)
      local v = floor(math.max(0, s) * 140)
      setRGBLedColor(i, v, floor(v * 0.9), floor(v * 0.7))
    end
    applyRGBLedColors()
  end
end

-- Wave: brightness sine travels around the ring
local function wave()
  local oldtime = getTime()
  local ph = 0
  return function()
    if (getTime() - oldtime) > 2 then
      oldtime = getTime()
      ph = (ph + 1) % 256
    end
    local base = ph / 256 * 2 * math.pi
    for i = 0, N - 1 do
      local a = i / N * 2 * math.pi
      local l = (0.5 + 0.5 * math.sin(a - base))
      setRGBLedColor(i, floor(30 * l), floor(120 * l), floor(255 * l))
    end
    applyRGBLedColors()
  end
end

-- HalfSweep: one half of the ring illuminates progressively
local function halfSweep()
  local oldtime = getTime()
  local level = 0
  local fwd = true
  return function()
    if (getTime() - oldtime) > 2 then
      oldtime = getTime()
      if fwd then
        level = level + 1
        if level >= HALF then fwd = false end
      else
        level = level - 1
        if level <= 0 then fwd = true end
      end
    end
    for i = 0, N - 1 do
      if i < level then
        local p = level > 0 and (i / level) or 0
        setRGBLedColor(i, 0, floor(180 * p), floor(255 * p))
      else
        setRGBLedColor(i, 0, 0, 8)
      end
    end
    applyRGBLedColors()
  end
end

-- Orbit: a single dot orbits continuously
local function orbit()
  local oldtime = getTime()
  local pos = 0
  return function()
    if (getTime() - oldtime) > 3 then
      oldtime = getTime()
      pos = (pos + 1) % N
    end
    for i = 0, N - 1 do setRGBLedColor(i, 0, 0, 8) end
    setRGBLedColor(pos, 255, 140, 0)
    applyRGBLedColors()
  end
end

-- Reactor: dark ring, bright energy point; every few laps the whole ring pulses
local function reactor()
  local oldtime = getTime()
  local pos = 0
  local laps = 0
  local pulse = 0
  return function()
    if (getTime() - oldtime) > 2 then
      oldtime = getTime()
      pos = pos + 1
      if pos >= N then
        pos = 0
        laps = laps + 1
        if laps % 3 == 0 then pulse = 20 end
      end
    end
    if pulse > 0 then pulse = pulse - 1 end
    local dim = pulse > 0 and 60 or 10
    for i = 0, N - 1 do setRGBLedColor(i, 0, 0, dim) end
    local leader = (pos + 1) % N
    setRGBLedColor(pos, 0, 220, 255)
    setRGBLedColor(leader, 255, 255, 255)
    applyRGBLedColors()
  end
end

-- Dual Helix: both rings rotate opposite directions, swapping periodically
local function dualHelix()
  local oldtime = getTime()
  local p0 = 0
  local p1 = 0
  local d0 = 1
  local d1 = -1
  local tick = 0
  return function()
    if (getTime() - oldtime) > 2 then
      oldtime = getTime()
      tick = tick + 1
      if tick % 64 == 0 then
        d0 = -d0
        d1 = -d1
      end
      p0 = (p0 + d0 + HALF) % HALF
      p1 = (p1 + d1 + HALF) % HALF
    end
    for i = 0, N - 1 do setRGBLedColor(i, 0, 0, 6) end
    for d = 0, 2 do
      local f = 1 - d / 3
      local a = (p0 - d * d0 + HALF) % HALF
      local b = (p1 - d * d1 + HALF) % HALF
      setRGBLedColor(a, 0, floor(220 * f), floor(255 * f))
      setRGBLedColor(b + HALF, floor(255 * f), floor(60 * f), floor(220 * f))
    end
    applyRGBLedColors()
  end
end

-- Mirror: both rings mirror each other
local function mirror()
  local oldtime = getTime()
  local pos = 0
  return function()
    if (getTime() - oldtime) > 2 then
      oldtime = getTime()
      pos = (pos + 1) % HALF
    end
    for i = 0, N - 1 do setRGBLedColor(i, 0, 0, 8) end
    local idx = pos
    setRGBLedColor(idx, 200, 220, 255)
    setRGBLedColor(idx + HALF, 200, 220, 255)
    applyRGBLedColors()
  end
end

-- Nuclear Reactor: dark green rings with a bright light-green orbiting dot per ring
local function nuclearReactor()
  local oldtime = getTime()
  local p0 = 0
  local p1 = 0
  return function()
    if (getTime() - oldtime) > 3 then
      oldtime = getTime()
      p0 = (p0 + 1) % HALF
      p1 = (p1 + 1) % HALF
    end
    for i = 0, N - 1 do setRGBLedColor(i, 0, 30, 0) end
    setRGBLedColor(p0, 150, 255, 150)
    setRGBLedColor(p1 + HALF, 150, 255, 150)
    applyRGBLedColors()
  end
end

-- RGB Vortex: ring as a rotating colour wheel with distinct sectors
local function vortex()
  local oldtime = getTime()
  local ph = 0
  local sectors = 3
  local step = math.floor(255 / sectors)
  return function()
    if (getTime() - oldtime) > 2 then
      oldtime = getTime()
      ph = (ph + 1) % 255
    end
    for i = 0, N - 1 do
      local r, g, b = hue(ph + i * step, 255, 1)
      setRGBLedColor(i, r, g, b)
    end
    applyRGBLedColors()
  end
end

-- Candy Rain: flickering orange/red/yellow
local function candyRain()
  local cols = {}
  for i = 0, N - 1 do cols[i] = { 0, 0, 0 } end
  local function refresh()
    for i = 0, N - 1 do
      local r = 140 + math.random(0, 115)
      local g = math.random(20, 140)
      local b = math.random(0, 40)
      local s = 0.4 + math.random() * 0.6
      cols[i] = { floor(r * s), floor(g * s), floor(b * s) }
    end
  end
  refresh()
  local oldtime = getTime()
  local tick = 0
  return function()
    if (getTime() - oldtime) > 2 then
      oldtime = getTime()
      tick = tick + 1
      if tick % 2 == 0 then refresh() end
    end
    for i = 0, N - 1 do
      local c = cols[i]
      setRGBLedColor(i, c[1], c[2], c[3])
    end
    applyRGBLedColors()
  end
end

-- Fire Ring: hot reds with orange/yellow flicker
local function fire()
  local cols = {}
  for i = 0, N - 1 do cols[i] = { 0, 0, 0 } end
  local function refresh()
    for i = 0, N - 1 do
      local r = math.random(160, 255)
      local g = math.random(0, math.floor(r * 0.45))
      local s = 0.5 + math.random() * 0.5
      cols[i] = { floor(r * s), floor(g * s), 0 }
    end
  end
  refresh()
  local oldtime = getTime()
  local tick = 0
  return function()
    if (getTime() - oldtime) > 2 then
      oldtime = getTime()
      tick = tick + 1
      if tick % 2 == 0 then refresh() end
    end
    for i = 0, N - 1 do
      local c = cols[i]
      setRGBLedColor(i, c[1], c[2], c[3])
    end
    applyRGBLedColors()
  end
end

-- Plasma: multiple brightness waves moving through changing colours
local function plasma()
  local oldtime = getTime()
  local t = 0
  local gh = 0
  return function()
    if (getTime() - oldtime) > 1 then
      oldtime = getTime()
      t = t + 1
      gh = (gh + 1) % 255
    end
    for i = 0, N - 1 do
      local a = i / N * 2 * math.pi
      local v = math.sin(a + t * 0.08) + math.sin(a * 2.1 - t * 0.11) + math.sin(a * 0.4 + t * 0.03)
      local l = (v + 3) / 6
      local r, g, b = hue(gh + i * 3, 255, 3)
      setRGBLedColor(i, floor(r * l), floor(g * l), floor(b * l))
    end
    applyRGBLedColors()
  end
end

-- Scanner: KITT/Cylone style, keeps looping when it hits the end
local function scanner()
  local oldtime = getTime()
  local pos = 0
  return function()
    if (getTime() - oldtime) > 2 then
      oldtime = getTime()
      pos = (pos + 1) % N
    end
    for i = 0, N - 1 do setRGBLedColor(i, 10, 0, 0) end
    for d = 0, 4 do
      local idx = (pos - d) % N
      local f = 1 - d / 5
      setRGBLedColor(idx, floor(255 * f), 0, 0)
    end
    applyRGBLedColors()
  end
end


------------------------------------------------------------------------
-- Stick-driven patterns
------------------------------------------------------------------------

-- Stick Compass: each ring shows the two LEDs surrounding the stick direction.
-- Uses the STICKTEST-exact stick readout and ring math (10 LEDs/ring, % 10).
local function stickCompass()
  return function()
    for i = 0, N - 1 do setRGBLedColor(i, 0, 0, 12) end

    local lr, ur = stickPair(rightStick())
    if lr then
      setRGBLedColor(lr, 0, 220, 255)
      setRGBLedColor(ur, 0, 220, 255)
    end

    local ll, ul = stickPair(leftStick())
    if ll then
      setRGBLedColor(10 + ll, 0, 220, 255)
      setRGBLedColor(10 + ul, 0, 220, 255)
    end

    applyRGBLedColors()
  end
end

-- Stick Magnitude: whole-ring brightness follows the magnitude of each
-- gimbal's stick vector.  Uses the STICKTEST-exact stick readout and the
-- fixed 10-LED ring split (right 0..9, left 10..19) instead of HALF.
local function stickVectorMode()
  return function()
    local rx, ry = rightStick()
    local lx, ly = leftStick()
    local lenR = math.sqrt(rx * rx + ry * ry)
    local lenL = math.sqrt(lx * lx + ly * ly)
    if lenR < STICK_DZ then lenR = 0 end
    if lenL < STICK_DZ then lenL = 0 end
    lenR = clamp(lenR, 0, 1)
    lenL = clamp(lenL, 0, 1)
    local bR = floor(lenR * 255)
    local bL = floor(lenL * 255)
    for i = 0, N - 1 do
      if i < RING_SEGS then
        setRGBLedColor(i, floor(bR * 0.2), bR, 0)
      else
        setRGBLedColor(i, bL, floor(bL * 0.8), 0)
      end
    end
    applyRGBLedColors()
  end
end

-- Stick Trail: each stick leaves a slowly decaying trail on its own ring.
-- Uses the STICKTEST-exact stick readout and ring math (10 LEDs/ring, % 10).
local function stickTrail()
  local buf = {}
  for i = 0, N - 1 do buf[i] = 0 end
  return function()
    local lr, ur = stickPair(rightStick())
    if lr then
      buf[lr] = 255
      buf[ur] = 255
    end
    local ll, ul = stickPair(leftStick())
    if ll then
      buf[10 + ll] = 255
      buf[10 + ul] = 255
    end
    for i = 0, N - 1 do
      buf[i] = floor(buf[i] * 0.9)
      local c = buf[i]
      setRGBLedColor(i, 0, floor(c * 0.8), c)
    end
    applyRGBLedColors()
  end
end

-- Stick Velocity: each ring shows an arc whose length is that stick's speed.
-- Uses the STICKTEST-exact stick readout and ring math (10 LEDs/ring, % 10).
local function stickVelocity()
  local prevRx, prevRy = 0, 0
  local prevLx, prevLy = 0, 0
  local function drawArc(base, x, y, px, py)
    local lr, ur, len = stickPair(x, y)
    if not lr then return end
    local plen = math.sqrt(px * px + py * py)
    local speed = math.abs(len * 1024 - plen * 1024) / 10
    local n = clamp(math.floor(speed), 1, RING_SEGS)
    local l = clamp(speed / 50, 0.1, 1)
    local col = { floor(255 * l), floor(200 * l), floor(100 * l) }
    setRGBLedColor(base + lr, col[1], col[2], col[3])
    setRGBLedColor(base + ur, col[1], col[2], col[3])
    for d = 2, n - 1 do
      local pos = (ur + d - 1) % RING_SEGS
      setRGBLedColor(base + pos, col[1], col[2], col[3])
    end
  end
  return function()
    local rx, ry = rightStick()
    local lx, ly = leftStick()
    for i = 0, N - 1 do setRGBLedColor(i, 0, 0, 8) end
    drawArc(0, rx, ry, prevRx, prevRy)
    drawArc(10, lx, ly, prevLx, prevLy)
    prevRx, prevRy = rx, ry
    prevLx, prevLy = lx, ly
    applyRGBLedColors()
  end
end

-- Centre Detent: each ring shows a subtle white centre when centred, else
-- its own direction.  Uses the STICKTEST-exact stick readout and ring math.
local function centreDetent()
  return function()
    for i = 0, N - 1 do setRGBLedColor(i, 0, 0, 12) end

    local lr, ur = stickPair(rightStick())
    if lr then
      setRGBLedColor(lr, 0, 220, 255)
      setRGBLedColor(ur, 0, 220, 255)
    else
      setRGBLedColor(0, 220, 220, 220)
    end

    local ll, ul = stickPair(leftStick())
    if ll then
      setRGBLedColor(10 + ll, 0, 220, 255)
      setRGBLedColor(10 + ul, 0, 220, 255)
    else
      setRGBLedColor(10, 220, 220, 220)
    end

    applyRGBLedColors()
  end
end

-- Quadrant Mode: each ring lights the quadrant its own stick points to.
-- Uses the STICKTEST-exact stick readout and the fixed 10-LED ring split.
local function quadrant()
  local function drawQuadrant(base, x, y)
    local lr, ur, _, angle = stickPair(x, y)
    if not lr then return end
    local q = math.floor((angle + 45) % 360 / 90)
    local ledOffsets
    if q == 0 then      ledOffsets = {0, 1, 9}
    elseif q == 1 then  ledOffsets = {2, 3}
    elseif q == 2 then  ledOffsets = {4, 5}
    else                ledOffsets = {7, 8}
    end
    for _, off in ipairs(ledOffsets) do
      setRGBLedColor(base + off, 255, 220, 0)
    end
  end
  return function()
    for i = 0, N - 1 do setRGBLedColor(i, 0, 0, 10) end
    drawQuadrant(0, rightStick())
    drawQuadrant(10, leftStick())
    applyRGBLedColors()
  end
end

------------------------------------------------------------------------
-- Combined-gimbal patterns
------------------------------------------------------------------------

-- Combined stick feedback: each ring mirrors the other's stick direction.
-- Left ring (10..19) shows the RIGHT stick, right ring (0..9) shows the LEFT
-- stick.  Uses the STICKTEST-exact stick readout and ring math.
local function opposing()
  return function()
    for i = 0, N - 1 do setRGBLedColor(i, 0, 0, 12) end

    local lr, ur = stickPair(rightStick())
    if lr then
      setRGBLedColor(10 + lr, 0, 220, 255)
      setRGBLedColor(10 + ur, 0, 220, 255)
    end

    local ll, ul = stickPair(leftStick())
    if ll then
      setRGBLedColor(ll, 255, 60, 220)
      setRGBLedColor(ul, 255, 60, 220)
    end

    applyRGBLedColors()
  end
end

-- Crosshair: each ring shows a directional colour based on its own stick.
-- Uses the STICKTEST-exact stick readout and the fixed 10-LED ring split.
local function crosshair()
  local function ringColour(x, y)
    local len = math.sqrt(x * x + y * y)
    if len < STICK_DZ then return nil end
    local total = math.abs(x) + math.abs(y)
    if total < 0.001 then total = 0.001 end
    local r = (255 * math.max(0, -y) + 255 * math.max(0, x)) / total
    local g = (255 * math.max(0, -y) + 255 * math.max(0, -x)) / total
    local b = (255 * math.max(0, y)) / total
    local maxc = math.max(r, g, b)
    if maxc < 0.001 then maxc = 0.001 end
    return { floor(r / maxc * 200), floor(g / maxc * 200), floor(b / maxc * 200) }
  end
  return function()
    local cR = ringColour(rightStick())
    local cL = ringColour(leftStick())
    for i = 0, N - 1 do
      local c
      if i < RING_SEGS then c = cR else c = cL end
      if c then
        setRGBLedColor(i, c[1], c[2], c[3])
      else
        setRGBLedColor(i, 4, 4, 8)
      end
    end
    applyRGBLedColors()
  end
end

------------------------------------------------------------------------
-- Throttle-driven patterns
------------------------------------------------------------------------

-- Afterburner: throttle-driven plasma/afterburner effect across both rings.
-- Reads only getValue("thr") (no ail/ele/rud).  Throttle controls colour,
-- brightness, animation speed and turbulence.  Both rings animate with a
-- phase offset so they stay visually independent.  Lightweight enough for
-- EdgeTX: a handful of sin/exp calls per LED per frame, no tables.
local function afterburner()
  local oldtime = getTime()
  local phase = 0
  -- Colour stops: { t, r, g, b } from cold (dark blue) to white-hot.
  local stops = {
    { 0.00,   5,   0,  40 },  -- very dark blue  (engine off)
    { 0.125, 10,   0,  90 },  -- deep blue      (cold glow)
    { 0.25, 20,  40, 180 },  -- electric blue  (low power)
    { 0.375, 60, 120, 220 },  -- cyan/blue-violet (spooling)
    { 0.50, 180,  40, 180 },  -- violet/magenta (plasma)
    { 0.625,255,  40,  80 },  -- hot pink/red   (ignition)
    { 0.75, 255, 100,  20 },  -- red/orange     (afterburner)
    { 0.875,255, 170,  30 },  -- orange/yellow  (high thrust)
    { 1.00, 255, 240, 160 },  -- yellow-white   (max / white-hot)
  }
  local function colourAt(t)
    t = clamp(t, 0, 1)
    for i = 1, #stops - 1 do
      local a, b = stops[i], stops[i + 1]
      if t <= b[1] then
        local f = (t - a[1]) / (b[1] - a[1])
        return a[2] + (b[2] - a[2]) * f,
               a[3] + (b[3] - a[3]) * f,
               a[4] + (b[4] - a[4]) * f
      end
    end
    local s = stops[#stops]
    return s[2], s[3], s[4]
  end
  return function()
    local now = getTime()
    -- Normalised throttle 0..1 (centre = 0.5)
    local t = ((getValue("thr") or 0) + 1024) / 2048
    t = clamp(t, 0, 1)

    -- Nonlinear brightness: 10% idle -> 100% max
    local brightness = 0.10 + (t * t * 0.90)

    -- Animation speed rises with throttle (t^2 curve)
    local speed = 0.15 + (t * t * 2.5)
    if (now - oldtime) > 1 then
      oldtime = now
      phase = phase + speed
    end

    -- Turbulence: subtle deterministic irregularity that grows with throttle
    local turb = t * t

    -- Base colour for this throttle setting
    local br, bg, bb = colourAt(t)

    for i = 0, N - 1 do
      local base = (i < RING_SEGS) and 0 or 10
      local off = i - base
      -- Independent ring phases (right ring offset by ~half a ring)
      local ringPhase = phase + (base * 0.5)
      -- Travelling Gaussian-like hotspot: position = phase, width narrows
      -- with throttle for tighter hot cores at high power.
      local pos = ringPhase + off
      local d = (pos % RING_SEGS + RING_SEGS) % RING_SEGS
      -- distance from moving centre 0..5
      local dc = math.abs(d - RING_SEGS / 2)
      if dc > RING_SEGS / 2 then dc = RING_SEGS - dc end
      -- Plasma intensity: moving hotspot + secondary wave for turbulence
      local hotspot = math.exp(-dc * dc * (0.6 + t * 1.4))
      local wave = 0.5 + 0.5 * math.sin((off + phase * 1.7) * 0.9)
      local localI = 0.35 + 0.65 * (hotspot * (0.7 + 0.3 * wave))
      -- Add turbulent shimmer at high throttle
      if turb > 0.01 then
        local shimmer = 0.5 + 0.5 * math.sin(off * 3.3 + phase * 4.1)
        localI = localI + (shimmer - 0.5) * turb * 0.3
      end
      localI = clamp(localI, 0, 1)

      -- Hot-region colour shift: hottest LEDs push toward white/yellow
      local hot = hotspot * hotspot  -- sharpen the hot core
      local r = br + (255 - br) * hot * (0.4 + t * 0.6)
      local g = bg + (255 - bg) * hot * (0.5 + t * 0.5)
      local b = bb + (255 - bb) * hot * (0.2 + t * 0.4)
      -- At very high throttle the hottest cores go white-hot
      if t > 0.9 and hot > 0.6 then
        local w = (t - 0.9) / 0.1 * (hot - 0.6) / 0.4
        w = clamp(w, 0, 1)
        r = r + (255 - r) * w
        g = g + (255 - g) * w
        b = b + (255 - b) * w
      end

      local lvl = brightness * localI
      setRGBLedColor(i,
        clamp(floor(r * lvl), 0, 255),
        clamp(floor(g * lvl), 0, 255),
        clamp(floor(b * lvl), 0, 255))
    end
    applyRGBLedColors()
  end
end

------------------------------------------------------------------------
-- Mode registry (keys match the tool's RGB.dat selections)
------------------------------------------------------------------------

local builders = {
  off    = function() return solid(0, 0, 0) end,
  red    = function() return solid(50, 0, 0) end,
  green  = function() return solid(0, 50, 0) end,
  blue   = function() return solid(0, 0, 50) end,
  yellow = function() return solid(255, 255, 0) end,
  white  = function() return solid(255, 255, 255) end,
  orange = function() return solid(255, 100, 0) end,
  purple = function() return solid(255, 0, 255) end,
  sapp   = function() return solid(0, 255, 255) end,
  scr    = function() return scroll(true, 0, 0, 50, false) end,
  scl    = function() return scroll(false, 0, 0, 50, false) end,
  Pfwrd  = function() return scroll(true, 72, 0, 72, true) end,
  Pback  = function() return scroll(false, 72, 0, 72, true) end,
  Bfwrd  = function() return scroll(true, 0, 0, 72, true) end,
  Bback  = function() return scroll(false, 0, 0, 72, true) end,
  rainbw = function() return rainbowStrip(2, 3) end,
  flow   = function() return rainbowStrip(1, 32) end,
  rgbLop = function() return loopColor() end,
  runner = function() return runner() end,
  police = function() return police() end,
  gimbal = function() return gimbal(50, 0, 0) end,
  gblred = function() return gimbal(255, 0, 0) end,
  gblgre = function() return gimbal(0, 255, 0) end,
  gblblu = function() return gimbal(0, 0, 255) end,
  gblyel = function() return gimbal(255, 255, 0) end,
  gblcyn = function() return gimbal(0, 255, 255) end,
  gblmag = function() return gimbal(255, 0, 255) end,
  gblorg = function() return gimbal(255, 165, 0) end,
  gblpur = function() return gimbal(128, 0, 128) end,
  gbllim = function() return gimbal(191, 255, 0) end,
  gblpnk = function() return gimbal(255, 20, 147) end,
  gbltrq = function() return gimbal(64, 224, 208) end,
  breath = function() return breath() end,
  comet  = function() return comet() end,
  chase  = function() return chase() end,
  spinner = function() return spinner() end,
  dspinner = function() return dualSpinner() end,
  pingpong = function() return pingPong() end,
  knight = function() return knight() end,
  sparkle = function() return sparkle() end,
  twinkle = function() return twinkle() end,
  wave   = function() return wave() end,
  sweep  = function() return halfSweep() end,
  orbit  = function() return orbit() end,
  reactor = function() return fire() end,
  helix  = function() return dualHelix() end,
  mirror = function() return mirror() end,
  nuclear = function() return nuclearReactor() end,
  vortex = function() return vortex() end,
  fire   = function() return candyRain() end,
  plasma = function() return plasma() end,
  scanner = function() return scanner() end,
  compass = function() return stickCompass() end,
  vector = function() return stickVectorMode() end,
  trail  = function() return stickTrail() end,
  velocity = function() return stickVelocity() end,
  detent = function() return centreDetent() end,
  quadrant = function() return quadrant() end,
  transfer = function() return opposing() end,
  opposing = function() return opposing() end,
  crosshair = function() return crosshair() end,
  afterburner = function() return afterburner() end,
}

local function buildMode(sel)
  if type(sel) == "string" and string.sub(sel, 1, 7) == "custom:" then
    local r, g, b = string.match(sel, "^custom:(%d+),(%d+),(%d+)$")
    if r then
      return solid(tonumber(r), tonumber(g), tonumber(b))
    end
    return solid(0, 0, 0)
  end
  local b = builders[sel]
  if not b then return solid(0, 0, 0) end
  return b()
end

------------------------------------------------------------------------
-- Config polling + script interface
------------------------------------------------------------------------

local function readSelection()
  local f = io.open(CFG, "r")
  if not f then return nil end
  local c = io.read(f, 256)
  io.close(f)
  if not c or #c == 0 then return nil end
  local chunk = load(c, CFG, "t")
  if not chunk then return nil end
  local ok, res = pcall(chunk)
  if ok and type(res) == "string" then return res end
  return nil
end

-- Apply a specific selection and run one frame. Used by the tool to preview.
local function apply(sel)
  if sel ~= curSel then
    curSel = sel
    runFn = buildMode(sel)
  end
  if runFn then runFn() end
end

local function tick()
  apply(readSelection())
end

local function init()
  tick()
end

local function run()
  tick()
end

local function background()
  tick()
end

return { run = run, background = background, init = init, apply = apply }
