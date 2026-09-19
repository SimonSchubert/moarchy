-- The panel. Nothing device-specific lives here.
--
-- Scale is the one genuinely per-device value (docs/devices.md D3), so the
-- device package owns it: whichever moarchy-device-* is installed ships
-- /usr/share/moarchy/device/hypr/device.lua, which hyprland.lua put on
-- package.path. A fixed module name on purpose -- this file does not know
-- which phone it is on, and exactly one package can provide it.
local ok, err = pcall(require, "hypr.device")
if not ok then
  -- Loud, and then a usable fallback. A phone with the wrong scale is
  -- recoverable; a phone with no monitor configured shows nothing at all.
  hl.monitor({ output = "", mode = "preferred", position = "auto", scale = "auto" })
  print("moarchy: no hypr.device module (" .. tostring(err) .. "); using scale=auto")
end

-- Upstream's config/hypr/monitors.lua sets GDK_SCALE=2 for a desktop with a
-- HiDPI laptop panel. Here the compositor already scales, and a second factor
-- on top makes every GTK app twice the size it should be.
hl.env("GDK_SCALE", "1")
