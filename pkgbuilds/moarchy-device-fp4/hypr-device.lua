-- Fairphone 4 (fp4, Qualcomm SM7225) hardware profile, for Hyprland.
--
-- Installed as /usr/share/moarchy/device/hypr/device.lua and required as
-- `hypr.device` by config/hypr/monitors.lua. A fixed module name on purpose
-- (docs/devices.md D6): the config layer does not know which phone it is on,
-- and exactly one package can provide this.
--
-- This file is SHORT, and that is the point of D2/D3. Gaps, borders, cursor
-- hiding, the vertical split and the power-key rebinding are phone-shaped
-- rather than fp4-shaped, and live in config/hypr/ where one copy serves
-- every device. What is left is the one value nothing can discover.
--
-- Panel is 1080x2340 at 6.3", which is 409 ppi. The scale is a judgement
-- about thumbs, not a fact about hardware, which is why D3 makes it a key and
-- not a probe -- nothing in sysfs knows that 409 ppi wants 3.
--
-- 3, the same as sargo, and the arithmetic is why:
--
--   1080x2340 / 3  =  360x780 logical
--
-- 360 logical pixels wide is what every layout constant in the shell was
-- tuned against: the bar height, the appDrawer grid, the keyboard's exclusive
-- zone, the home strip. Landing on the SAME logical width as the Pixel 3a is
-- the thing that makes this port cheap -- the shell needs no fp4 branch
-- anywhere, because from QML's side this is the same screen 40 rows taller.
--
-- 780 rather than sargo's 740 is 40 extra logical rows of height, which the
-- QML already handles: it reads screen.height with a 720 fallback rather than
-- assuming a number.

hl.monitor({
  output   = "",          -- the only one; naming DSI-1 here would be a probe
  mode     = "preferred",
  position = "auto",
  scale    = 3,
})
