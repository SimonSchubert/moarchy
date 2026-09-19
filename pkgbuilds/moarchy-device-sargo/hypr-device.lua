-- Google Pixel 3a (sargo, Qualcomm SDM670) hardware profile, for Hyprland.
--
-- Installed as /usr/share/moarchy/device/hypr/device.lua and required as
-- `hypr.device` by config/hypr/monitors.lua. A fixed module name on purpose
-- (docs/devices.md D6): the config layer does not know which phone it is on,
-- and exactly one package can provide this.
--
-- This file is SHORT, and that is the point of D2/D3. Everything that used to
-- sit beside the scale in the sway profile -- gaps, borders, cursor hiding,
-- the vertical split, the power-key rebinding -- was phone-shaped rather than
-- sargo-shaped, and now lives in config/hypr/ where one copy serves every
-- device. What is left is the one value nothing can discover.
--
-- Panel is 1080x2220 at 5.6", which is 441 ppi. The scale is a judgement about
-- thumbs, not a fact about hardware, which is why D3 makes it a key and not a
-- probe -- nothing in sysfs knows that 441 ppi wants 3.
--
-- 3 rather than 2, and the arithmetic is the point:
--
--   1080x2220 / 3  =  360x740 logical
--
-- 360 logical pixels wide is what every layout constant in the shell was
-- tuned against: the bar height, the drawer grid, the keyboard's exclusive
-- zone, the home strip. The extra 20 rows of height are a taller screen,
-- which the QML already handles -- it reads screen.height with a 720 fallback
-- rather than assuming.

hl.monitor({
  output   = "",          -- the only one; naming DSI-1 here would be a probe
  mode     = "preferred",
  position = "auto",
  scale    = 3,
})
