# RGB Toolbox

RGB LED control tool for EdgeTX 2.11+ radios.

## Features

- **Persists across model changes** - your selected mode and custom colour are stored in `/SCRIPTS/TOOLS/RGB.dat` on the SD card, so the same RGB setting applies to every model.
- **Quick and easy interface** - a simple tap-to-select tool screen with all modes grouped by category, plus live on-screen preview before you exit.
- **Advanced RGB patterns** - 60+ modes including animations, gimbal lighting and dual-gimbal FX.
- **Custom colour** - R/G/B sliders for any colour you want.

## Installation

1. Power off your radio and remove the SD card.
2. Copy the entire `SCRIPTS` folder from this repository onto your SD card to merge/copy the contents:
   - `SCRIPTS/TOOLS/RGB.lua` -> `/SCRIPTS/TOOLS/RGB.lua` (the RGB Toolbox tool)
   - `SCRIPTS/RGBLED/rgbk.lua` -> `/SCRIPTS/RGBLED/rgbk.lua` (the background keeper script)
3. Reinsert the SD card and power on the radio.

## Usage

1. Long-press the SYS key, then open **Tools** and run **RGB Toolbox**.
2. Tap **Setup Background Script on Model** to install the keeper as Special Function 64 on the current model. Repeat for every model you want the LED control on. This only needs to be done once per model.
3. Restart your radio or switch models to load the background script.
4. Pick a mode or set a custom RGB colour with the R/G/B sliders. Your selection is remembered, takes effect when the tool exits, and persists across model changes.

## RGB Modes

**Solid:** Off, Red, Green, Blue, Yellow, White, Orange, Purple, Sapphire

**Scroll:** Green Fwd, Green Back, Purple Fwd, Purple Back, Blue Fwd, Blue Back

**Rainbow:** Rainbow, Flow, Loop, Runner, Police

**Gimbal:** Gimbal White, Gimbal Red, Gimbal Green, Gimbal Blue, Gimbal Yellow, Gimbal Cyan, Gimbal Magenta, Gimbal Orange, Gimbal Purple, Gimbal Lime, Gimbal Pink, Gimbal Turquoise

**Patterns:** Breath, Comet, Chase, Spinner, Dual Spin, Ping Pong, Knight, Sparkle, Twinkle, Wave, Half Sweep, Orbit, Candy Rain

**Advanced:** Fire, Vortex, Dual Helix, Mirror, Nuclear, Plasma, Scanner

**Gimbal FX:** Compass, Vector, Trail, Velocity, Detent, Quadrant, Afterburner

**Dual Gimbal:** Transfer, Opposing, Crosshair

**Custom:** any colour via the R/G/B sliders

## Notes

- Requires EdgeTX 2.11 or newer.
- The keeper polls `/SCRIPTS/TOOLS/RGB.dat` and runs the selected mode, so no other mode scripts are needed.
