#!/usr/bin/env python3
"""Run bin/moarchy-one-app-per-workspace's layout rule against a fixture tree.

    python3 scripts/test-workspace-layout.py

docs/gestures.md P7 -- "a workspace holding more than one window is split
vertically" -- is the rule that makes the overview's drag worth making: half of
360 logical px is 180 and nothing on this phone can use it, where half of 740 is
370 and everything does. It is also the rule with the most ways to be quietly
wrong: the direction has to be named or an inherited `splith` container keeps
its own, the criteria form of `layout` is a reading of sway's command handler
rather than a documented guarantee, the fallback focuses a window to set it, and
a fallback that forgot to put focus back would move the phone every time
somebody dragged an app.

None of that needs a phone to check. The daemon's own functions are called with
`swaymsg` and `command` stubbed, so what is asserted is the command string it
would send -- which is the whole of what it does.

The shipped file is executed rather than copied, for scripts/sheet-test.js'
reason: a test against a copy passes while the copy is the thing that drifted.
"""
import copy
import pathlib
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
DAEMON = ROOT / "bin" / "moarchy-one-app-per-workspace"


def window(con_id, app_id, name, focused=False):
    return {"id": con_id, "type": "con", "app_id": app_id, "name": name,
            "focused": focused, "nodes": [], "floating_nodes": []}


def workspace(num, layout, nodes, focused=False, floating=()):
    return {"id": 10 + num, "type": "workspace", "num": num, "name": str(num),
            "focused": focused, "layout": layout, "nodes": list(nodes),
            "floating_nodes": list(floating)}


def container(con_id, layout, nodes):
    """A split/tabbed container between the workspace and its windows.

    The shape a real phone produces, and the one the rule has to be written
    against: sway arranges a portrait output `splitv`, a window moved onto an
    occupied workspace joins the container already there, and tabbing therefore
    lands one level below the workspace."""
    return {"id": con_id, "type": "con", "layout": layout, "nodes": list(nodes),
            "floating_nodes": []}


# One window on 1, two on 2 already upright, an empty 3, five on 4 still
# sideways, and the scratchpad, which is a workspace with num -1 and not a
# screen.
def fixture():
    return {"id": 1, "type": "root", "nodes": [{
        "id": 2, "type": "output", "name": "HEADLESS-1", "floating_nodes": [], "nodes": [
            workspace(1, "splith", [window(100, "foot", "~")]),
            workspace(2, "splitv", [window(101, "org.gnome.Papers", "Handbook", True),
                                    window(102, "org.gnome.Epiphany", "omarchy.org")],
                      focused=True),
            workspace(3, "splith", []),
            workspace(4, "splith", [window(103 + i, f"app{i}", f"App {i}")
                                    for i in range(5)]),
            {"id": 90, "type": "workspace", "num": -1, "name": "__i3_scratch",
             "layout": "splith", "nodes": [], "floating_nodes": []},
        ]}], "floating_nodes": []}


def load():
    module = {}
    exec(compile(DAEMON.read_text(), DAEMON.name, "exec"), module)
    return module


GREEN, RED, OFF = "\033[32m", "\033[31m", "\033[0m"
failed = 0


def check(ok, what, detail=""):
    global failed
    if not ok:
        failed += 1
    print(f"  {GREEN}ok{OFF}  " if ok else f"  {RED}NO{OFF}  ",
          what, f" -- {detail}" if detail else "")


def run(trees):
    """reconcile_layouts() over a list of trees it will read in turn, returning
    the commands it sent. Two reads is the normal path: one to decide, one to
    check that the criteria form landed."""
    module = load()
    sent, queue = [], list(trees)
    module["swaymsg"] = lambda *a: queue.pop(0) if queue else None
    module["command"] = sent.append
    module["reconcile_layouts"]()
    return module, sent


module = load()
tree = fixture()
by_num = {w["num"]: w for w in module["workspaces"](tree)}

print("wanted_layout: the window count decides, and floating does not count")
check(module["wanted_layout"](by_num[1]) is None, "one window wants no layout at all")
check(module["wanted_layout"](by_num[2]) == "splitv", "two windows split vertically")
check(module["wanted_layout"](by_num[3]) is None, "an empty workspace wants nothing")
check(module["wanted_layout"](by_num[4]) == "splitv", "five windows split vertically")

dialog = copy.deepcopy(by_num[1])
dialog["floating_nodes"] = [window(200, "foot", "Save changes?")]
check(module["wanted_layout"](dialog) is None,
      "a dialog over an app is not two apps")

print("layout_fix: the question is asked of the container the command acts on")
nested = workspace(5, "splitv", [container(50, "splitv", [
    window(300, "foot", "one"), window(301, "foot", "two")])])
check(module["holding_container"](nested)["id"] == 50,
      "the parent of the first window, not the workspace",
      module["holding_container"](nested)["id"])
check(module["layout_fix"](nested) is None,
      "a pair already split vertically one level down is left alone -- this is "
      "the comparison that made the daemon redo the fix on every event")

sideways = workspace(6, "splitv", [container(60, "splith", [
    window(310, "foot", "one"), window(311, "foot", "two")])])
check(module["layout_fix"](sideways) == "splitv",
      "a pair inherited side by side is turned upright -- 180px each is the "
      "width this daemon exists to prevent", module["layout_fix"](sideways))

deceptive = workspace(9, "splitv", [container(90, "splith", [
    window(340, "foot", "one"), window(341, "foot", "two")])])
check(module["holding_container"](deceptive)["layout"] == "splith",
      "and the workspace saying `splitv` over it does not hide that",
      module["holding_container"](deceptive)["layout"])

lone = workspace(7, "splitv", [window(320, "foot", "one")])
check(module["layout_fix"](lone) is None,
      "a lone window on a splitv workspace is not touched -- naming `splith` "
      "here dispatched at every ordinary workspace on a portrait phone")

by_hand = workspace(8, "splitv", [container(80, "tabbed", [
    window(330, "foot", "one"), window(331, "foot", "two")])])
check(module["layout_fix"](by_hand) is None,
      "a workspace somebody tabbed by hand keeps its tabs -- sway has that "
      "layout and this daemon is not a policy about which are allowed")

print("workspaces(): the scratchpad is not a screen")
check([w["num"] for w in module["workspaces"](tree)] == [1, 2, 3, 4],
      "1..4 only", [w["num"] for w in module["workspaces"](tree)])
check(module["focused_con_id"](tree) == 101, "the focused window is found",
      module["focused_con_id"](tree))

print("reconcile: the criteria form, which moves nothing on screen")
settled = copy.deepcopy(tree)
[w for w in module["workspaces"](settled) if w["num"] == 4][0]["layout"] = "splitv"
# ws4's windows are direct children, so the workspace *is* the holder there.
_, sent = run([tree, settled])
check(sent == ["[con_id=103] layout splitv"],
      "one command for the one workspace that is wrong, and no focus", sent)

print("reconcile: and the fallback, for a sway that resolves criteria otherwise")
_, sent = run([tree, tree])
check(sent[:3] == ["[con_id=103] layout splitv", "[con_id=103] focus", "layout splitv"],
      "it focuses the window and sets the layout", sent[:3])
check(sent[-1] == "[con_id=101] focus",
      "and puts focus back where it found it", sent[-1])

print("reconcile: nothing to do, and nothing to do it to")
_, sent = run([settled])
check(sent == [], "a tree that already agrees is not touched", sent)
_, sent = run([])
check(sent == [], "a compositor that is not answering is a no-op", sent)

print("occupancy: who is already here, which is not who can be arranged")
# The shape the phone makes of an Android app: one tiled window, and over it a
# floating toplevel that covers the output because moarchy-waydroid-setup
# floats it (docs/android.md AC 5).
android = {"id": 1, "type": "root", "floating_nodes": [], "nodes": [{
    "id": 2, "type": "output", "name": "DSI-1", "floating_nodes": [], "nodes": [
        workspace(1, "splitv", [window(400, "org.kde.keysmith", "Keysmith")],
                  focused=True,
                  floating=[window(401, "waydroid.com.spotify.music", "Spotify")]),
    ]}]}
crowded = module["workspaces"](android)[0]
check(module["occupant_ids"](crowded) == [400, 401],
      "a floating Android window is somebody who is already here",
      module["occupant_ids"](crowded))
check(module["tiled_window_ids"](crowded) == [400],
      "and is still not something `layout splitv` can arrange",
      module["tiled_window_ids"](crowded))


def landed(tree, con_id):
    """on_new_window() for a window already in `tree`, returning its commands.

    The daemon re-reads the tree rather than trusting the event's container, so
    the fixture is the whole of what it sees -- which is also the only way the
    floating case can be written: `window::new` is serialised before sway has
    applied `for_window ... floating enable`, so the event says `con` for a
    window that is about to float (locate())."""
    mod = load()
    sent = []
    mod["swaymsg"] = lambda *a: (tree if a[0] == "get_tree"
                                 else [{"num": w["num"]}
                                       for w in mod["workspaces"](tree)])
    mod["command"] = sent.append
    mod["on_new_window"]({"id": con_id})
    return sent


print("on_new_window: windows.md W6, a new window never lands on top of one")
check(landed(android, 400) == ["[con_id=400] move container to workspace number 2",
                               "workspace number 2"],
      "an app opened over an Android one is moved to a free workspace, and "
      "focus follows it -- this is the launch that used to tile underneath "
      "Spotify, full width and invisible", landed(android, 400))
check(landed(android, 401) == [],
      "and the floating window itself is left where it is: this is the test "
      "that keeps a modal dialog with the document it belongs to")

alone = {"id": 1, "type": "root", "floating_nodes": [], "nodes": [{
    "id": 2, "type": "output", "name": "DSI-1", "floating_nodes": [], "nodes": [
        workspace(1, "splitv", [window(410, "foot", "~")], focused=True),
    ]}]}
check(landed(alone, 410) == [],
      "a window with the workspace to itself is not moved anywhere -- moving "
      "it would strand an empty workspace and renumber everything for nothing")

pair = {"id": 1, "type": "root", "floating_nodes": [], "nodes": [{
    "id": 2, "type": "output", "name": "DSI-1", "floating_nodes": [], "nodes": [
        workspace(1, "splitv", [window(420, "foot", "~"),
                                window(421, "org.gnome.Loupe", "cat.png")],
                  focused=True),
    ]}]}
check(landed(pair, 421) == ["[con_id=421] move container to workspace number 2",
                            "workspace number 2"],
      "and the ordinary tiled case is unchanged", landed(pair, 421))

print("first_free_workspace: the rule gestures.md F1 has three readers of")
module["swaymsg"] = lambda *a: [{"num": 1}, {"num": 2}, {"num": 4}, {"num": -1}]
check(module["first_free_workspace"]() == 3, "the lowest gap, not the highest plus one",
      module["first_free_workspace"]())
module["swaymsg"] = lambda *a: [{"num": n} for n in range(1, 11)]
check(module["first_free_workspace"]() == 11, "and no ceiling at ten",
      module["first_free_workspace"]())

print(f"\n{failed} failed" if failed else "\nall passed")
sys.exit(1 if failed else 0)
