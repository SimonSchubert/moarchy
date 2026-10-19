-- moarchy -- window rules, as additions on top of upstream's own
-- (default/hypr/windows.lua, already loaded via default.hypr.omarchy).

-- One app per workspace. On a 360px-wide screen a second window tiled beside
-- the first is 180px wide, which nothing here can use (see hypr/looknfeel.lua).
-- Sway could not express "give every window its own workspace" declaratively,
-- so this used to be a daemon (bin/moarchy-one-app-per-workspace) that watched
-- the IPC event stream and moved windows after the fact. Hyprland has the rule
-- built in: every newly-mapped TILED window is sent to the next empty, unnamed
-- workspace, so each app lands alone and "next workspace" reads as "next app".
--
-- Scoped to float = false on purpose. A modal or dialog is floated from its
-- xdg role before window rules evaluate, so this rule does not match it and it
-- stays on its parent's workspace rather than being flung to an empty one.
-- Measured on an FP4 (Hyprland 0.56.2, 2026-09-30): three tiled apps land on
-- three distinct workspaces, and the float matcher is exact (a float = true
-- rule leaves a tiled window untouched, so float = false leaves floats alone).
o.window({ float = false }, { workspace = "emptynm" })
