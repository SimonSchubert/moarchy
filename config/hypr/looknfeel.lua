-- Look and feel, as overrides on upstream's default/hypr/looknfeel.lua.
--
-- Upstream's values are a desktop's: gaps_in 5, gaps_out 10, rounding 0,
-- animations on, dwindle. On a 360px-wide screen the gaps alone ate a third
-- of the width, so they go to zero -- the app is what the screen is for.

hl.config({
  general = {
    -- No gaps at all. docs/windows.md W1-W3.
    gaps_in = 0,
    gaps_out = 0,

    -- The 2px border is the only thing left saying which pane has focus once
    -- a workspace holds two windows. A lone window is flush to its workspace
    -- either way, because there is nothing to sit beside.
    border_size = 2,

    -- Tiling, and the split is what makes P7 free: on a 360x740 workspace
    -- dwindle splits along the longer side, so a second window lands BELOW
    -- the first rather than beside it. Half of 740 is 370, which every app
    -- here reflows to; half of 360 is 180, which nothing can use.
    layout = "dwindle",
  },

  dwindle = {
    preserve_split = true,
    force_split = 2,    -- always split down/right, never "wherever the cursor is"
  },

  decoration = {
    rounding = 0,
    blur   = { enabled = false },
    shadow = { enabled = false },
  },

  -- The motion budget is docs/style.md §G's, and §G now states the GLES 2.0
  -- floor as a CHOICE rather than a ceiling (docs/devices.md D18). The
  -- compositor's own animations are off because every surface that moves on
  -- this phone is a QML sheet following a finger, and a second animation
  -- underneath it is a second thing to go out of step with the drag.
  animations = { enabled = false },
})
