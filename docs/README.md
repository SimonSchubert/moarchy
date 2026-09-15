# How these documents are written

Two genres live here, and the difference decides what belongs in a file.

**Contract docs** say what the phone must do. Behaviour, present tense, with a
check a terminal can run: `gestures.md`, `settings.md`, `shade.md`,
`windows.md`, `style.md`, and the T-series in `apps.md`. `bin/moarchy-selftest`
cites their ids, so a criterion with no test is visible.

**Decision records** say how the project is built and why it is built that way:
`structure.md`, `devices.md`, `upstream.md`. They have no checks. Rationale is
their content, not an intrusion into it.

`refactor.md` is a contract doc about the *shape of the code* rather than about
what the phone does, so its criteria are greppable rather than runnable on the
device. It is the only file with an end: every section is either done or the
work that is left, and when the last one is done it goes. Twenty-nine comments
across the tree cite it by section id, so it cannot simply be deleted — the
citations go first.

`build-log.md` is neither — it is the chronological account, and it is where the
archaeology belongs.

## A criterion is three things

```
**B3** The swipe lands on a workspace with nothing of the shell's drawn over it.
The shade, the drawer and the theme picker are put away on the way (A8). A shell
app is a window (K1), so it stays where it is and the swipe back returns to it
(K2).
→ with the shade down over an app, a sideways swipe leaves `shade state` ==
`closed` and a focused workspace that is not the one it started on
```

1. **One present-tense statement** of required behaviour. No dates. Not `until
   2026-…`, `used to`, `previously`, `the first pass`, `it was N until`.
2. **The `→` check** — the command whose output settles it. Mechanism belongs
   here: QML property names, `swaymsg -t get_tree`, a grep pattern. Not in the
   statement above it.
3. **At most one clause of why**, and only if it passes the test below.

### The re-break test

A *why* survives only if deleting it would let someone undo the constraint
without realising. G10's note that sway resolves exclusive zones Overlay-down
passes: without it, `ExclusionMode.Normal` looks like the obvious fix and gets
tried again. S6d-8's note that BlueZ will not power an adapter up underneath a
soft block passes: without it, the 700ms wait looks like superstition and gets
deleted.

A post-mortem of a fixed defect does not pass. Neither does the story of what
the code did before the commit that changed it. `git log -S` finds both,
alongside the change that made them untrue.

### Three rules that follow

- **An annulled criterion is deleted**, not kept with the argument for its own
  removal attached. If the failure it named must not return, it becomes one
  dated line in that document's `Known-bad` list.
- **A measurement keeps its number and loses its session.** `73px, measured
  against libadwaita's 47px header` stays; the write-up of the ssh session that
  measured it does not.
- **An answered question is deleted.** The criterion that now states the answer
  is the record.

## What must not change

- **Ids are never renumbered and never reused.** They are transcribed by hand
  into ~300 code comments and 220 assertion strings in `bin/moarchy-selftest`,
  and no tool notices when one moves.
- **Ids are not unique across files.** `L1`–`L13` is long-press in
  `gestures.md` and the launch splash in `windows.md`; `I*`, `D*` and `B*`
  collide across four files each. A new citation names the file —
  `gestures.md L12`, not a bare `L12`.
- **`**?**` means "my reading of the code, not your decision."** It flags
  unratified content. It is not decoration.
- **The table rows in `menu-coverage.md` are parsed** by
  `bin/moarchy-selftest` (G5, G6) against the pattern
  ``^| `id` | label | Native|Bridged|Shade |``. Their format is code. The prose
  around them is not.

## The files

| File | What it is |
| --- | --- |
| [`gestures.md`](gestures.md) | Contract — every touch gesture: the strip, the edges, the drawer, long-press |
| [`settings.md`](settings.md) | Contract — the Settings screens, their rows, and the IPC they answer on |
| [`shade.md`](shade.md) | Contract — the pull-down: tiles, sliders, media, notifications |
| [`windows.md`](windows.md) | Contract — the window area and the launch splash |
| [`style.md`](style.md) | Contract — type, colour, shape, touch targets, motion. Binds the keyboard and store repos too |
| [`apps.md`](apps.md) | What ships on the phone and what each app is for, with screenshots off the device |
| [`menu-coverage.md`](menu-coverage.md) | All 333 upstream menu entries, classified Native / Bridged / Shade / Unsupported |
| [`structure.md`](structure.md) | Decisions — repos, packages, the package repository, the image |
| [`devices.md`](devices.md) | Decisions — what a second device would need, and what is device-specific |
| [`upstream.md`](upstream.md) | Decisions — the boundary with Omarchy, and what a version bump may break |
| [`refactor.md`](refactor.md) | Contract — what has to be true when the duplication is gone. Cited by ~29 comments |
| [`build-log.md`](build-log.md) | How this went, including the dead ends. The archaeology lives here |
