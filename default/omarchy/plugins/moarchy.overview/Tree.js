// The compositor's layout, as a list of workspaces holding windows
// (docs/gestures.md P3).
//
//     import "Tree.js" as Tree
//
//     Shared.Probe {
//       command: ["swaymsg", "-r", "-t", "get_tree"]
//       onAnswered: root.board = Tree.workspaces(text)
//     }
//
// ---------------------------------------------------------------------------
// Why this reads the tree rather than asking Quickshell
// ---------------------------------------------------------------------------
// `Quickshell.I3` publishes workspaces and dispatches commands, and that is
// all: there is no window list on it, and a workspace's `lastIpcObject` carries
// only sway's own `representation` string -- `H[foot papers]` -- which names app
// ids in layout order and nothing else. Two windows of the same app are one
// word repeated, and a con_id appears nowhere.
//
// A con_id is what this screen exists to move things by. `[con_id=N] move
// container to workspace number M` addresses exactly one window; the title
// criteria the back gesture falls back on address every window that spells the
// same thing (M5), which on a phone where two terminals are ordinary is a drag
// that moves the wrong one. So: the tree, on the sheet's own terms, while the
// sheet is up.
//
// ---------------------------------------------------------------------------
// What it does not own
// ---------------------------------------------------------------------------
// **Running the command.** A `Shared.Probe` is the caller's, and when to refresh
// is the surface's (P9): idle while shut is the whole of keepLoaded's bargain.
//
// **What to draw.** This hands back app ids and titles. Which icon those mean is
// `moarchy.common/Apps.js`, resolved through the toplevel handle the tile is
// matched to (P5).
.pragma library

// A node is a window when it carries an app id (Wayland) or window properties
// (XWayland). Containers that only split have neither -- the same test
// bin/moarchy-one-app-per-workspace makes, and for the same reason: sway has no
// "is this a window" flag and a split container looks like a node with children.
function isWindow(node) {
  return !!(node && (node.app_id || node.window_properties))
}

function windowOf(node, floating) {
  var props = node.window_properties || {}
  return {
    conId: node.id,
    // XWayland has no app_id; its class is the closest thing, and it is what
    // the drawer's index is keyed on for those windows too.
    appId: String(node.app_id || props["class"] || ""),
    title: String(node.name || ""),
    focused: !!node.focused,
    floating: !!floating
  }
}

// Every window under a node, in layout order, floating ones last.
//
// Floating is carried rather than dropped. A modal dialog belongs to the window
// it is over -- bin/moarchy-one-app-per-workspace deliberately leaves those with
// their parent -- so the card has to show the workspace is occupied by them, and
// P6 refuses to drag one away.
function windowsUnder(node) {
  var out = []

  function walk(n, floating) {
    if (isWindow(n)) out.push(windowOf(n, floating))
    var kids = n.nodes || []
    for (var i = 0; i < kids.length; i++) walk(kids[i], floating)
    var floats = n.floating_nodes || []
    for (var j = 0; j < floats.length; j++) walk(floats[j], true)
  }

  var kids = node.nodes || []
  for (var i = 0; i < kids.length; i++) walk(kids[i], false)
  var floats = node.floating_nodes || []
  for (var j = 0; j < floats.length; j++) walk(floats[j], true)
  return out
}

// The layout of the container that actually holds a workspace's windows.
//
// Not the workspace's own. Sway arranges a portrait output as `splitv`, and a
// window moved onto an occupied workspace joins the container already there --
// so a pair reads `workspace splitv > con splith > [foot, foot]` and the
// workspace says `splitv` over two windows that are plainly side by side. This is the
// node `layout` acts on when it is addressed through one of the windows, which
// is the same node bin/moarchy-one-app-per-workspace reconciles.
function holdingLayout(node) {
  var target = null

  function firstWindow(n) {
    if (target !== null) return
    var kids = n.nodes || []
    for (var i = 0; i < kids.length; i++) {
      if (isWindow(kids[i])) { target = kids[i].id; return }
      firstWindow(kids[i])
    }
  }

  function parentOf(n) {
    var kids = n.nodes || []
    for (var i = 0; i < kids.length; i++) {
      if (kids[i].id === target) return n
      var found = parentOf(kids[i])
      if (found) return found
    }
    return null
  }

  firstWindow(node)
  if (target === null) return String(node.layout || "")
  var holder = parentOf(node)
  return String((holder || node).layout || "")
}

function anyFocused(windows) {
  for (var i = 0; i < (windows || []).length; i++)
    if (windows[i].focused) return true
  return false
}

// The workspaces sway is holding, in number order, each with its windows.
//
// Numbered ones only. `__i3_scratch` is a workspace node with `num` -1 and the
// scratchpad is not a screen you can swipe to, so a card for it would be a card
// that goes nowhere. The same `> 0` test the gesture plugin's
// firstFreeWorkspace() makes, for the same reason (F1).
function workspaces(json) {
  var tree = null
  try {
    tree = JSON.parse(String(json || ""))
  } catch (e) {
    // A tree that did not parse is not an empty phone. The caller keeps the
    // board it had rather than drawing "no workspaces" over a screen that
    // plainly has some -- swaymsg answers nothing for a moment across a
    // compositor reload, and a card list that empties and refills is worse
    // than one that waits.
    return null
  }
  if (!tree) return null

  var out = []

  function walk(node) {
    if (!node) return
    if (node.type === "workspace") {
      var num = Number(node.num)
      if (num > 0) {
        var wins = windowsUnder(node)
        out.push({
          number: num,
          name: String(node.name || num),
          // Focused if the workspace node is, *or* if a window on it is.
          //
          // Both halves are needed and neither is enough. Sway marks the
          // deepest focused node: on an empty workspace that is the workspace,
          // and the moment it holds a window it is the window -- so a card that
          // asked only the workspace lost its marker exactly when there was
          // something on it to go back to.
          focused: !!node.focused || anyFocused(wins),
          // Sway's own word for how these windows are arranged: splith, splitv,
          // tabbed or stacked. Read off the container that holds them rather
          // than off the workspace, for the reason holdingLayout() gives -- a
          // card said SPLIT over two windows that were plainly tabs.
          layout: holdingLayout(node),
          windows: wins
        })
      }
      return
    }
    var kids = (node.nodes || []).concat(node.floating_nodes || [])
    for (var i = 0; i < kids.length; i++) walk(kids[i])
  }

  walk(tree)
  out.sort(function(a, b) { return a.number - b.number })
  return out
}

// The lowest positive number no workspace in this board is using.
//
// Answered off the board rather than off live sway, so the number matches the
// cards on screen: a drop onto the new-workspace card lands where the card sits.
// The gesture plugin owns the same rule against the compositor (F1) and
// bin/moarchy-one-app-per-workspace owns it in Python; this is a third reader of
// one rule and not a fourth copy of it -- it is handed the list rather than
// going and asking.
function freeNumber(board) {
  var taken = ({})
  for (var i = 0; i < (board || []).length; i++) taken[board[i].number] = true
  var free = 1
  while (taken[free]) free++
  return free
}
