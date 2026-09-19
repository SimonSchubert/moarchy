// The compositor's layout, as a list of workspaces holding windows
// (docs/gestures.md P3).
//
//     import "Tree.js" as Tree
//
//     Shared.Probe {
//       command: ["hyprctl", "clients", "-j"]
//       onAnswered: root.board = Tree.workspaces(text, focusedWorkspaceId)
//     }
//
// ---------------------------------------------------------------------------
// Why this is a flat grouper and not a tree walk
// ---------------------------------------------------------------------------
// It was a recursive parser for sway's `get_tree`, because sway's layout IS a
// tree: split containers hold windows, a window is a node with no children,
// and finding the container that holds a workspace's windows meant walking
// down and back up. Hyprland has no container tree at all -- `hyprctl clients`
// is a FLAT array and each entry names its own workspace -- so the walk, the
// parent search and the "is this node a window" test all go, and what is left
// is a group-by.
//
// ---------------------------------------------------------------------------
// Why it forks at all
// ---------------------------------------------------------------------------
// `Quickshell.Hyprland` does publish a window list, unlike `Quickshell.I3`
// before it, and this could read the live model. It forks anyway, for the
// reason P9 gives: shut, this plugin runs nothing, and a model the plugin
// holds is a subscription it would carry while the sheet is down. One fork per
// refresh, only while the sheet is up, is the same bargain the sway version
// struck -- and the same one rfkill, brightnessctl and mmcli are read on.
//
// ---------------------------------------------------------------------------
// What it does not own
// ---------------------------------------------------------------------------
// **Running the command.** A `Shared.Probe` is the caller's, and when to
// refresh is the surface's (P9).
//
// **What to draw.** This hands back app ids and titles. Which icon those mean
// is `moarchy.common/Apps.js`, resolved through the toplevel handle the tile
// is matched to (P5).
.pragma library

// The window's identity, and the whole reason this screen reads the
// compositor rather than the foreign-toplevel list: an ADDRESS addresses
// exactly one window. `hl.dsp.window.move({ window = "address:0x..." })` moves
// that window; the app-id-and-title criteria the back gesture once fell back
// on addressed every window that spelled the same thing (P4, P13), which on a
// phone where two terminals are ordinary is a drag that moves the wrong one.
//
// It is a STRING here where sway's con_id was an int. Callers test it with
// `!== ""`, never `> 0`.
function windowOf(client) {
  return {
    conId: String(client.address || ""),
    // XWayland clients report the same field; Hyprland folds `class` and the
    // X11 class together, so there is no second spelling to check.
    appId: String(client["class"] || ""),
    title: String(client.title || ""),
    // focusHistoryID 0 is the window the compositor would return to.
    focused: Number(client.focusHistoryID) === 0,
    floating: !!client.floating,
    // Hyprland's answer to sway's tabbed/stacked containers. A grouped window
    // is drawn as one tab of several, which is what the card's badge means.
    grouped: !!(client.grouped && client.grouped.length)
  }
}

function anyFocused(windows) {
  for (var i = 0; i < (windows || []).length; i++)
    if (windows[i].focused) return true
  return false
}

function anyGrouped(windows) {
  for (var i = 0; i < (windows || []).length; i++)
    if (windows[i].grouped) return true
  return false
}

// The workspaces the compositor is holding, in number order, each with its
// windows.
//
// Numbered ones only. A special workspace (the scratchpad) has a NEGATIVE id
// and is not a screen you can swipe to, so a card for it would be a card that
// goes nowhere -- the same `> 0` test the gesture plugin's
// firstFreeWorkspace() makes, for the same reason (F1).
//
// `focusedId` is passed in rather than read here: the caller already holds
// Hyprland.focusedWorkspace and this file forks nothing of its own.
function workspaces(json, focusedId) {
  var clients = null
  try {
    clients = JSON.parse(String(json || ""))
  } catch (e) {
    // A reply that did not parse is not an empty phone. The caller keeps the
    // board it had rather than drawing "no workspaces" over a screen that
    // plainly has some -- hyprctl answers nothing for a moment across a
    // compositor reload, and a card list that empties and refills is worse
    // than one that waits.
    return null
  }
  if (!Array.isArray(clients)) return null

  var byNumber = ({})
  for (var i = 0; i < clients.length; i++) {
    var c = clients[i]
    if (!c || !c.mapped) continue
    var ws = c.workspace || {}
    var num = Number(ws.id)
    if (!(num > 0)) continue
    if (!byNumber[num])
      byNumber[num] = { number: num, name: String(ws.name || num),
                        focused: false, layout: "", windows: [] }
    byNumber[num].windows.push(windowOf(c))
  }

  var out = []
  for (var key in byNumber) {
    var w = byNumber[key]
    // Floating last, matching the order the sway version produced so the
    // cards' tiles do not reshuffle across the compositor change.
    w.windows.sort(function(a, b) { return (a.floating ? 1 : 0) - (b.floating ? 1 : 0) })
    // Focused if this is the focused workspace, *or* if a window on it is.
    // Both halves are needed and neither is enough: an empty workspace has no
    // focused window, and a workspace holding the focused window is not
    // always the one the compositor calls active during a switch.
    w.focused = (Number(focusedId) === w.number) || anyFocused(w.windows)
    w.layout = anyGrouped(w.windows) ? "tabbed" : ""
    out.push(w)
  }
  out.sort(function(a, b) { return a.number - b.number })
  return out
}

// The lowest positive number no workspace in this board is using.
//
// Answered off the board rather than off the live compositor, so the number
// matches the cards on screen: a drop onto the new-workspace card lands where
// the card sits. The gesture plugin owns the same rule against the compositor
// (F1) and bin/moarchy-one-app-per-workspace owns it in Python; this is a
// third reader of one rule and not a fourth copy of it -- it is handed the
// list rather than going and asking.
function freeNumber(board) {
  var taken = ({})
  for (var i = 0; i < (board || []).length; i++) taken[board[i].number] = true
  var free = 1
  while (taken[free]) free++
  return free
}
