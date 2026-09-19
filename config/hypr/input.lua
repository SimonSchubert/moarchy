-- Input. Almost nothing: upstream's default/hypr/input.lua reads
-- /etc/vconsole.conf for the keyboard layout and is right about all of it,
-- including the non-Latin-layout guard.
--
-- What differs on a phone is that there is usually no keyboard at all, and
-- that the screen is the only pointing device.

hl.config({
  misc = {
    -- The panel's power state is owned by bin/moarchy-screen, which is the
    -- single gate for it (docs/refactor.md D1): a key or a pointer event must
    -- not light a screen that the power button just blanked. Upstream turns
    -- both of these on, which is right for a laptop.
    key_press_enables_dpms = false,
    mouse_move_enables_dpms = false,
  },

  cursor = {
    -- Touch is the primary input and there is no mouse to show.
    inactive_timeout = 3,
    hide_on_touch = true,
  },
})
