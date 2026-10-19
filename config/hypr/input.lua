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

    -- Suppress Hyprland 0.56's red banner "was started without start-hyprland"
    -- (fp4-defects.md D12). The session execs `Hyprland -c ...` from
    -- zz-moarchy.sh on purpose; start-hyprland is a 264 KB binary that manages an
    -- instance and does more than exec, so adopting it risks a phone that boots
    -- to no UI -- a worse defect than a banner. This option (misleadingly named;
    -- its own description is "the warning about not using start-hyprland") turns
    -- the banner off without changing how the session launches.
    disable_watchdog_warning = true,
  },

  cursor = {
    -- Touch is the primary input and there is no mouse to show.
    inactive_timeout = 3,
    hide_on_touch = true,
  },
})
