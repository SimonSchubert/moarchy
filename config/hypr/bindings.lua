-- The phone's bindings, as DELTAS on upstream's.
--
-- Upstream's default/hypr/bindings/{media,clipboard,tiling,utilities,voxtype}
-- .lua are adopted whole: ~200 bindings of Omarchy muscle memory, the
-- omarchy-menu system, the capture bindings, workspace switching and window
-- management, all maintained upstream rather than hand-translated here. This
-- file is only what a phone changes.
--
-- Eight of the commands upstream binds are already shadowed by bin/omarchy-*
-- (brightness, capture, the four window toggles, the keybindings menu, lock),
-- so those bindings do the phone's thing without being restated.
--
-- hl.unbind BEFORE o.bind, always. Upstream's own template says to unbind an
-- existing binding before replacing it, and the sway config this replaced
-- carried the same warning for the same reason: a second binding on one key
-- does not replace the first.

-- --- The volume rocker ------------------------------------------------------
-- It is hardware, it is one of two buttons on the device, and it raises the
-- volume PANEL as well as moving the volume (docs/volume.md). Upstream's
-- omarchy-audio-output-volume knows nothing about that panel.
hl.unbind("XF86AudioRaiseVolume")
hl.unbind("XF86AudioLowerVolume")
hl.unbind("XF86AudioMute")
o.bind("XF86AudioRaiseVolume", "Volume up",   "moarchy-volume up",   { locked = true, repeating = true })
o.bind("XF86AudioLowerVolume", "Volume down", "moarchy-volume down", { locked = true, repeating = true })
o.bind("XF86AudioMute",        "Mute",        "moarchy-volume mute", { locked = true })

-- --- The power button -------------------------------------------------------
-- The other button. logind's HandlePowerKey is already set to ignore the short
-- press (/etc/systemd/logind.conf.d/10-power-key.conf) so that it reaches us;
-- upstream then binds it to the system menu, which is right on a desktop where
-- this button is behind the machine and pressed on purpose. Here a press in a
-- pocket would open a menu, and a second press inside 400ms means something
-- else entirely (docs/gestures.md Q11) -- which is why it goes through
-- moarchy-power-press rather than straight to moarchy-screen.
--
-- locked so it still works with a session lock up; repeating = false so
-- holding it does not toggle over and over on the way to the long press.
hl.unbind("XF86PowerOff")
o.bind("XF86PowerOff", "Screen on/off", "moarchy-power-press", { locked = true, repeating = false })

-- --- Our panels, not upstream's --------------------------------------------
-- The bar is moarchy.bar, so upstream's bar-widget panels do not exist here.
hl.unbind("SUPER + CTRL + B")
hl.unbind("SUPER + CTRL + W")
o.bind("SUPER + CTRL + B", "Bluetooth", "omarchy-shell shell toggle moarchy.bluetooth")
o.bind("SUPER + CTRL + W", "Network",   "omarchy-shell shell toggle moarchy.wifi")

-- --- The on-screen keyboard -------------------------------------------------
-- No upstream counterpart: a desktop has a keyboard. This is the binding for
-- when a USB one is attached and you want the on-screen one anyway.
o.bind("SUPER + I", "Toggle on-screen keyboard", "moarchy-toggle-keyboard")

-- --- Hardware this phone does not have --------------------------------------
-- Left bound, these are keys that cannot be pressed and menu rows that lie
-- about what the device can do.
hl.unbind("switch:on:Lid Switch")
hl.unbind("switch:off:Lid Switch")
hl.unbind("XF86TouchpadToggle")
hl.unbind("XF86TouchpadOn")
hl.unbind("XF86TouchpadOff")
