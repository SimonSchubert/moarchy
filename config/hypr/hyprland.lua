-- moarchy -- top-level Hyprland config.
--
-- Installed as /usr/share/moarchy/config/hypr/hyprland.lua and passed to
-- Hyprland with -c by /etc/profile.d/zz-moarchy.sh. NOT ~/.config/hypr/, which
-- is where upstream puts its own: docs/structure.md P1 forbids this package
-- putting files in $HOME, and `Hyprland -c <file>` means it does not have to.
--
-- Upstream 4.x configures Hyprland in LUA, not hyprlang, so this is a program
-- rather than a list of settings. The layering is upstream's own, with two
-- directories inserted into package.path so that `require("hypr.bindings")`
-- finds OURS -- and so a user file in ~/.config/hypr/ still wins over both.

local home    = os.getenv("HOME")
local omarchy = os.getenv("OMARCHY_PATH") or "/usr/share/omarchy"
local moarchy = os.getenv("MOARCHY_PATH") or "/usr/share/moarchy"

-- Upstream's bootstrap: clears package.loaded for the reloadable prefixes
-- (default.hypr, hypr, omarchy.current.theme) so `hyprctl reload` re-reads
-- them, and sets the base package.path.
dofile(omarchy .. "/default/hypr/bootstrap.lua")

-- Insert moarchy's two layers between the user's and upstream's. The HOME
-- entries are re-stated in front deliberately: a duplicate package.path entry
-- never matches twice, and this way the whole search order is one readable
-- list rather than a gsub into somebody else's string.
--
--   ~/.local/state   generated -- the theme's hyprland.lua, the toggles
--   ~/.config        the user's own overrides, which win over everything
--   device/          this phone's hardware profile (docs/devices.md D6)
--   config/          moarchy's phone layer, below
--   $OMARCHY_PATH    upstream's defaults
package.path = home .. "/.local/state/?.lua;"
            .. home .. "/.config/?.lua;"
            .. moarchy .. "/device/?.lua;"
            .. moarchy .. "/config/?.lua;"
            .. package.path

-- Everything upstream ships: helpers, autostart, all five binding files, envs,
-- looknfeel, input, window rules, and the active theme's colours.
require("default.hypr.omarchy")

-- PATH, and this is load-bearing rather than tidy.
--
-- upstream's default/hypr/envs.lua ends with hl.env("PATH", ...) putting
-- $OMARCHY_PATH/bin FIRST -- it rebuilds the variable rather than appending,
-- and its own comment says why: `hyprctl setenv` does not reach the keybind
-- dispatcher's environment, so the compositor has to own PATH.
--
-- The login shell already put /usr/lib/moarchy/bin first (zz-moarchy.sh), but
-- that ordering does not survive the line above: every binding would resolve
-- omarchy-menu, omarchy-system-lock and the rest to UPSTREAM's copy rather
-- than to the ones this project shadows them with. Nothing would error; the
-- phone would just quietly run the desktop's scripts.
local bin = "/usr/lib/moarchy/bin"
local kept = {}
for entry in (os.getenv("PATH") or "/usr/local/bin:/usr/bin"):gmatch("[^:]+") do
  if entry ~= bin then table.insert(kept, entry) end
end
table.insert(kept, 1, bin)
hl.env("PATH", table.concat(kept, ":"))

-- moarchy's phone layer. The module names are upstream's own, so a user who
-- drops ~/.config/hypr/bindings.lua shadows ours exactly as a .conf in
-- ~/.config/sway/config.d/ used to -- same affordance, no extra mechanism.
require("hypr.monitors")
require("hypr.input")
require("hypr.bindings")
require("hypr.looknfeel")
require("hypr.autostart")

-- Upstream's dynamic config flags, last, as upstream orders them.
require("default.hypr.toggles")
