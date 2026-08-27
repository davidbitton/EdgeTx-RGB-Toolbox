-- toolName = TNS|RGB Toolbox|TNE

local LED_DIR = "/SCRIPTS/RGBLED"
local CFG_FILE = "/SCRIPTS/TOOLS/RGB.dat"
-- Native "RGB Led" special function: loads <name>.lua from /SCRIPTS/RGBLED/
-- Prefer the firmware constant so a future enum shift does not break setup.
local RGB_LED_FUNC = (type(FUNC_RGB_LED) == "number") and FUNC_RGB_LED or 25
-- Fixed Special Function slot for the keeper script (SF64 = index 63)
local SF_SLOT = 63
local KEEPER_NAME = "rgbk"
local KEEPER_FILE = "/SCRIPTS/RGBLED/rgbk.lua"
local CUSTOM_PREFIX = "custom:"

local exitRequested = false
local noLvgl = false
local noLeds = type(setRGBLedColor) ~= "function" or type(applyRGBLedColors) ~= "function"
local selected = nil
local subtitle = ""
local buttons = {}
local onSwitch = nil
local keeper = nil
local keeperWarned = false
local custR = 255
local custG = 128
local custB = 0

local function saveSelection(name)
  local f = io.open(CFG_FILE, "w")
  if not f then return end
  if name then
    io.write(f, "return \"", name, "\"\n")
  else
    io.write(f, "return nil\n")
  end
  io.close(f)
end

local function loadSelection()
  local f = io.open(CFG_FILE, "r")
  if not f then return nil end
  local content = io.read(f, 1024)
  io.close(f)
  if not content or #content == 0 then return nil end
  local chunk, err = load(content, CFG_FILE, "t")
  if not chunk then return nil end
  local ok, res = pcall(chunk)
  if ok and type(res) == "string" then return res end
  return nil
end

local function rgbValue(col, isBg)
  if lcd and lcd.RGB then
    local r, g, b = 0, 0, 0
    if type(col) == "table" then
      r = math.max(0, math.min(255, math.floor(col.r)))
      g = math.max(0, math.min(255, math.floor(col.g)))
      b = math.max(0, math.min(255, math.floor(col.b)))
    end
    if isBg then
      return lcd.RGB(math.floor(r * 0.3), math.floor(g * 0.3), math.floor(b * 0.3))
    end
    return lcd.RGB(r, g, b)
  end
  return COLOR_THEME_PRIMARY2
end

local modes = {
  off    = { label = "Off", color = nil },
  red    = { label = "Red", color = { r = 255, g = 0, b = 0 } },
  green  = { label = "Green", color = { r = 0, g = 255, b = 0 } },
  blue   = { label = "Blue", color = { r = 0, g = 128, b = 255 } },
  yellow = { label = "Yellow", color = { r = 255, g = 255, b = 0 } },
  white  = { label = "White", color = { r = 255, g = 255, b = 255 } },
  orange = { label = "Orange", color = { r = 255, g = 128, b = 0 } },
  purple = { label = "Purple", color = { r = 160, g = 32, b = 255 } },
  sapp   = { label = "Sapphire", color = { r = 0, g = 255, b = 255 } },
  scr    = { label = "Green Fwd", color = { r = 0, g = 255, b = 0 } },
  scl    = { label = "Green Back", color = { r = 0, g = 255, b = 0 } },
  Pfwrd  = { label = "Purple Fwd", color = { r = 160, g = 32, b = 255 } },
  Pback  = { label = "Purple Back", color = { r = 160, g = 32, b = 255 } },
  Bfwrd  = { label = "Blue Fwd", color = { r = 0, g = 128, b = 255 } },
  Bback  = { label = "Blue Back", color = { r = 0, g = 128, b = 255 } },
  rainbw = { label = "Rainbow", color = { r = 128, g = 128, b = 128 } },
  flow   = { label = "Flow", color = { r = 128, g = 128, b = 128 } },
  rgbLop = { label = "Loop", color = { r = 128, g = 128, b = 128 } },
  runner = { label = "Runner", color = { r = 128, g = 128, b = 128 } },
  police = { label = "Police", color = { r = 200, g = 0, b = 50 } },
  gimbal = { label = "Gimbal White", color = { r = 255, g = 255, b = 255 } },
  gblred = { label = "Gimbal Red", color = { r = 255, g = 0, b = 0 } },
  gblgre = { label = "Gimbal Green", color = { r = 0, g = 255, b = 0 } },
  gblblu = { label = "Gimbal Blue", color = { r = 0, g = 128, b = 255 } },
  gblyel = { label = "Gimbal Yellow", color = { r = 255, g = 255, b = 0 } },
  gblcyn = { label = "Gimbal Cyan", color = { r = 0, g = 255, b = 255 } },
  gblmag = { label = "Gimbal Magenta", color = { r = 255, g = 0, b = 255 } },
  gblorg = { label = "Gimbal Orange", color = { r = 255, g = 128, b = 0 } },
  gblpur = { label = "Gimbal Purple", color = { r = 160, g = 32, b = 255 } },
  gbllim = { label = "Gimbal Lime", color = { r = 191, g = 255, b = 0 } },
  gblpnk = { label = "Gimbal Pink", color = { r = 255, g = 20, b = 147 } },
  gbltrq = { label = "Gimbal Turq.", color = { r = 64, g = 224, b = 208 } },
  breath = { label = "Breath", color = { r = 128, g = 128, b = 128 } },
  comet  = { label = "Comet", color = { r = 0, g = 220, b = 255 } },
  chase  = { label = "Chase", color = { r = 0, g = 200, b = 0 } },
  spinner = { label = "Spinner", color = { r = 0, g = 200, b = 255 } },
  dspinner = { label = "Dual Spin", color = { r = 128, g = 60, b = 220 } },
  pingpong = { label = "Ping Pong", color = { r = 220, g = 220, b = 255 } },
  knight = { label = "Knight", color = { r = 200, g = 0, b = 0 } },
  sparkle = { label = "Sparkle", color = { r = 200, g = 220, b = 255 } },
  twinkle = { label = "Twinkle", color = { r = 140, g = 130, b = 90 } },
  wave  = { label = "Wave", color = { r = 30, g = 120, b = 255 } },
  sweep = { label = "Half Sweep", color = { r = 0, g = 180, b = 255 } },
  orbit = { label = "Orbit", color = { r = 255, g = 140, b = 0 } },
  reactor = { label = "Fire", color = { r = 255, g = 80, b = 0 } },
  vortex = { label = "Vortex", color = { r = 128, g = 128, b = 255 } },
  helix = { label = "Dual Helix", color = { r = 200, g = 60, b = 220 } },
  mirror = { label = "Mirror", color = { r = 200, g = 220, b = 255 } },
  nuclear = { label = "Nuclear", color = { r = 0, g = 255, b = 80 } },
  fire  = { label = "Candy Rain", color = { r = 255, g = 80, b = 0 } },
  plasma = { label = "Plasma", color = { r = 128, g = 128, b = 255 } },
  scanner = { label = "Scanner", color = { r = 255, g = 0, b = 0 } },
  compass = { label = "Compass", color = { r = 200, g = 220, b = 255 } },
  vector = { label = "Vector", color = { r = 0, g = 255, b = 0 } },
  trail = { label = "Trail", color = { r = 0, g = 200, b = 255 } },
  velocity = { label = "Velocity", color = { r = 255, g = 200, b = 100 } },
  detent = { label = "Detent", color = { r = 220, g = 220, b = 220 } },
  quadrant = { label = "Quadrant", color = { r = 255, g = 220, b = 0 } },
  transfer = { label = "Transfer", color = { r = 0, g = 220, b = 255 } },
  opposing = { label = "Opposing", color = { r = 200, g = 40, b = 220 } },
  crosshair = { label = "Crosshair", color = { r = 0, g = 255, b = 255 } },
  afterburner = { label = "Afterburner", color = { r = 255, g = 140, b = 20 } },
}

local groups = {
  { title = "Solid", modes = { "red", "green", "blue", "yellow", "white", "orange", "purple", "sapp" }, cols = 4 },
  { title = "Scroll", modes = { "scr", "scl", "Pfwrd", "Pback", "Bfwrd", "Bback" }, cols = 3 },
  { title = "Rainbow", modes = { "rainbw", "flow", "rgbLop", "runner", "police" }, cols = 3 },
  { title = "Gimbal", modes = { "gimbal", "gblred", "gblgre", "gblblu", "gblyel", "gblcyn", "gblmag", "gblorg", "gblpur", "gbllim", "gblpnk", "gbltrq" }, cols = 3 },
  { title = "Patterns", modes = { "breath", "comet", "chase", "spinner", "dspinner", "pingpong", "knight", "sparkle", "twinkle", "wave", "sweep", "orbit", "fire" }, cols = 4 },
  { title = "Advanced", modes = { "reactor", "vortex", "mirror", "nuclear", "helix", "plasma", "scanner" }, cols = 4 },
  { title = "Gimbal FX", modes = { "compass", "vector", "trail", "velocity", "detent", "quadrant", "afterburner" }, cols = 4 },
  { title = "Dual Gimbal", modes = { "transfer", "opposing", "crosshair" }, cols = 3 },
}

local function findOnSwitch()
  if type(getSwitchIndex) == "function" then
    local idx = getSwitchIndex("ON")
    if type(idx) == "number" and idx >= 0 then return idx end
  end
  if type(switches) == "function" then
    for i, name in switches() do
      if name == "ON" then return i end
    end
  end
  return nil
end

-- Check whether the keeper Special Function is already installed and active
-- in the current model at the fixed SF64 slot.
local function keeperInstalled()
  if type(model.getCustomFunction) ~= "function" then return false end
  local cur = model.getCustomFunction(SF_SLOT)
  return cur ~= nil and cur.func == RGB_LED_FUNC and cur.name == KEEPER_NAME and cur.active == 1
end

-- Install the keeper Special Function once. After it exists (and is enabled)
-- the tool never rewrites it: the keeper picks up mode changes from RGB.dat.
local function ensureKeeper()
  if type(model.getCustomFunction) ~= "function" or type(model.setCustomFunction) ~= "function" then
    return
  end
  if keeperInstalled() then
    return
  end
  local cur = model.getCustomFunction(SF_SLOT)
  local ours = cur ~= nil and cur.func == RGB_LED_FUNC and cur.name == KEEPER_NAME
  if cur ~= nil and type(cur.func) == "number" and cur.func ~= 0 and not ours then
    lvgl.message({ title = "SF64 in use",
      message = "Special Function SF64 is already assigned to a different function. Free it to let the RGB LED tool use it." })
    return
  end
  if onSwitch == nil then onSwitch = findOnSwitch() end
  if onSwitch == nil then
    lvgl.message({ title = "No ON switch", message = "Could not find the always-ON switch index." })
    return
  end
  model.setCustomFunction(SF_SLOT, {
    switch = onSwitch,
    func = RGB_LED_FUNC,
    name = KEEPER_NAME,
    active = 1,
  })
end

-- Load the keeper module once; it exports apply() which runs one animation
-- frame for the requested mode, giving an exact preview.
local function loadKeeper()
  if keeper then return keeper end
  local chunk, err = loadScript(KEEPER_FILE)
  if not chunk then return nil end
  local ok, iface = pcall(chunk)
  if ok and type(iface) == "table" and type(iface.apply) == "function" then
    keeper = iface
  end
  return keeper
end

local function preview(name)
  local k = loadKeeper()
  if not k then
    if not keeperWarned then
      keeperWarned = true
      lvgl.message({ title = "rgbk.lua missing",
        message = "Copy rgbk.lua to /SCRIPTS/RGBLED/ so modes can run after exit." })
    end
    return
  end
  pcall(k.apply, name)
end

local function customKey()
  return CUSTOM_PREFIX .. custR .. "," .. custG .. "," .. custB
end

local function setChecked(name, on)
  local btn = buttons[name]
  if btn and btn.set then
    btn:set({ checked = on })
  end
end

local function selectMode(name)
  selected = name
  saveSelection(name)
  if not noLeds then
    preview(name)
    ensureKeeper()
  end
  for key, _ in pairs(buttons) do
    setChecked(key, key == name)
  end
end

local function runMode(name)
  if not modes[name] then return end
  selectMode(name)
end

local function applyCustom()
  selectMode(customKey())
end

local function buildUi()
  lvgl.clear()
  buttons = {}
  local pg = lvgl.page({ title = "RGB", subtitle = subtitle,
    back = function() exitRequested = true end, backButton = true })
  local EH = lvgl.UI_ELEMENT_HEIGHT or 50
  local W = (LCD_W or 480) - 16
  local MARGIN = 8
  local GAP = 6
  local LABEL_H = 28
  local y = MARGIN

  if noLeds then
    pg:label({ x = MARGIN, y = y, w = W - 2 * MARGIN,
      text = "This radio has no RGB LED strip (setRGBLedColor missing).",
      color = COLOR_THEME_WARNING })
    y = y + LABEL_H + GAP
  end

  local offBtn = pg:button({ x = MARGIN, y = y, w = W - 2 * MARGIN, h = EH,
    text = "Off",
    color = function() return COLOR_THEME_PRIMARY3 end,
    textColor = function() return COLOR_THEME_SECONDARY1 end,
    checked = selected == "off",
    press = function() runMode("off") end })
  buttons.off = offBtn
  y = y + EH + GAP

  -- Setup Background Script button: installs the keeper as SF64 on the
  -- current model.  Disabled once it is already installed.
  local setupBtn = pg:button({ x = MARGIN, y = y, w = W - 2 * MARGIN, h = EH,
    text = "Setup Background Script on Model",
    color = function() return rgbValue({ r = 30, g = 120, b = 255 }, true) end,
    textColor = function() return rgbValue({ r = 30, g = 120, b = 255 }, false) end,
    active = function() return not noLeds and not keeperInstalled() end,
    press = function()
      if noLeds then return end
      ensureKeeper()
      if keeperInstalled() then
        lvgl.message({ title = "Background Script Installed",
          message = "Restart your radio or switch models to load it. Add the script to each model - Background script is added as Special Function 64." })
      end
    end })
  buttons.setup = setupBtn
  y = y + EH + 2
  pg:label({ x = MARGIN, y = y, w = W - 2 * MARGIN, text = "Restart your Radio or Switch Models to Load it. Add script to each model - Background script will be added as Special Function 64", font = SMLSIZE, color = COLOR_THEME_DISABLED })
  y = y + LABEL_H + GAP

  for _, grp in ipairs(groups) do
    y = y + LABEL_H
    pg:label({ x = MARGIN, y = y + 8, text = grp.title, font = MIDSIZE })
    y = y + LABEL_H + math.floor((LABEL_H + 8) * 1.5)
    local n = #grp.modes
    local rows = math.ceil(n / grp.cols)
    local colW = (W - 2 * MARGIN - (grp.cols - 1) * GAP) / grp.cols
    for row = 0, rows - 1 do
      for c = 0, grp.cols - 1 do
        local idx = row * grp.cols + c + 1
        if idx <= n then
          local key = grp.modes[idx]
          local m = modes[key]
          local btn = pg:button({ x = MARGIN + c * (colW + GAP), y = y, w = colW, h = EH,
            text = m.label,
            color = function() return rgbValue(m.color, true) end,
            textColor = function() return rgbValue(m.color, false) end,
            checked = selected == key,
            press = function() runMode(key) end })
          buttons[key] = btn
        end
      end
      y = y + EH + GAP
    end
    y = y + GAP
  end

  -- Custom colour section at the very bottom
  y = y + LABEL_H
  pg:label({ x = MARGIN, y = y + 8, text = "Custom Colour", font = MIDSIZE })
  y = y + LABEL_H + 8
  local sliderW = (W - 2 * MARGIN) * 0.5 - GAP

  local function sliderRow(label, getter, setter)
    pg:label({ x = MARGIN, y = y, w = sliderW, text = label, font = SMLSIZE })
    pg:slider({ x = MARGIN + sliderW + GAP, y = y, w = sliderW, h = EH, min = 0, max = 255,
      get = function() return getter() end,
      set = setter })
    y = y + EH + GAP
  end

  sliderRow("R", function() return custR end,
    function(v) custR = math.floor(v) applyCustom() end)
  sliderRow("G", function() return custG end,
    function(v) custG = math.floor(v) applyCustom() end)
  sliderRow("B", function() return custB end,
    function(v) custB = math.floor(v) applyCustom() end)

  pg:label({ x = MARGIN, y = y + 4, text = "Custom: " .. tostring(custR) .. "," .. tostring(custG) .. "," .. tostring(custB), color = COLOR_THEME_DISABLED })
end

local function init()
  local ok, info = pcall(model.getInfo)
  if ok and info and type(info) == "table" then
    subtitle = info.name or ""
  end
  if type(BLING_LED_STRIP_LENGTH) == "number" and BLING_LED_STRIP_LENGTH > 0 then
    subtitle = (subtitle ~= "" and (subtitle .. " · ") or "") .. tostring(BLING_LED_STRIP_LENGTH) .. " LEDs"
  elseif type(LED_STRIP_LENGTH) == "number" and LED_STRIP_LENGTH > 0 then
    subtitle = (subtitle ~= "" and (subtitle .. " · ") or "") .. tostring(LED_STRIP_LENGTH) .. " LEDs"
  end
  if lvgl == nil then
    noLvgl = true
    return
  end
  selected = loadSelection()
  if type(selected) == "string" and string.sub(selected, 1, 7) == CUSTOM_PREFIX then
    local r, g, b = string.match(selected, "^custom:(%d+),(%d+),(%d+)$")
    if r then
      custR = tonumber(r)
      custG = tonumber(g)
      custB = tonumber(b)
    end
  end
  buildUi()
end

local function run(event, touchState)
  if noLvgl then
    if lcd then
      lcd.clear()
      lcd.drawText(0, 0, "RGB needs EdgeTX 2.11+")
    end
    return 0
  end
  if not noLeds and selected then
    preview(selected)
  end
  if exitRequested then
    return 2
  end
  return 0
end

return { init = init, run = run, useLvgl = true }
