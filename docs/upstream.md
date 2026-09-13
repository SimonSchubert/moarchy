# Upstream boundary — specification

What has to be true for bumping `[omarchy]` in `manifest.toml` to be a safe
operation. [structure.md](structure.md) says the pin is the only supported way
to change what an image contains (V5); it does not say what has to hold when
the pin moves. This file is that.

Present tense, normative. The archaeology lives in
[build-log.md](build-log.md); the shape of our own code is
[refactor.md](refactor.md); this is the contract at the seam between the two.

Status: **§A landed 2026-09-13.** §B–§E are the contract to argue with before
any of them is; where an AC is my reading rather than a decision it is marked
**?**.

---

## Why this file exists

The port was moved from `install/port-4x.sh` to `port-4x.patch` on 2026-09-06,
and `pkgbuilds/omarchy-config/PKGBUILD` records the reason: a sed pass against
a moved upstream "matches nothing and ships a shell that still imports
`Quickshell.Hyprland`, which is a failure this project has paid for before."
The patch was supposed to close that.

**Measured 2026-09-13, against upstream's current default branch.** `quattro`
is 363 commits ahead of the pin (and 103 behind — the branches have diverged).
Applied in the builder's own toolchain, GNU patch 2.8 on `linux/arm64`
(`menci/archlinuxarm:base-devel`):

```
patching file shell/plugins/bar/widgets/KeyboardLayout.qml
Hunk #2 succeeded at 102 (offset 19 lines).
patching file shell/plugins/menu/Menu.qml
Hunk #3 succeeded at 1282 (offset 48 lines).
patching file shell/shell.qml
Hunk #1 succeeded at 721 (offset -15 lines).
Hunk #2 succeeded at 784 (offset -15 lines).
EXIT=0
```

The build succeeds. What it produces is a half-ported shell:

```
shell/plugins/background/Background.qml:2   import Quickshell.Hyprland
shell/plugins/background/Background.qml:236 Hyprland.monitorFor(modelData)
```

`Background.qml` did not exist at the pin, so the patch was never aimed at it,
so it applies cleanly and the wallpaper plugin ships unported. The same run
leaves `shell.qml.orig`, `Menu.qml.orig` and `KeyboardLayout.qml.orig` in the
tree, which `package()`'s `cp -a shell` would install.

The control is clean: the same patch against the pinned v4.0.3 tree reports no
offsets and leaves no `.orig`.

Two separate defects, both silent:

1. **`--fuzz=0` does not mean "no offset".** It bounds fuzz — how many context
   lines may mismatch. Offsets are always permitted, reported on stdout, and
   `patch` exits 0 either way. The PKGBUILD header's claim that a hunk "must
   apply with no offset and no fuzz, so a moved upstream fails the build" is
   not a property the build has.
2. **A patch can only assert about files it names.** Completeness of the port
   is a property of the whole tree, and nothing measures it.

Neither is an argument against the patch. The patch is doing its job — it is
the *only* thing here that can fail loudly at all, and it applied across 363
commits of drift without a reject. The gap is that "applied" was being read as
"ported", and those are different claims.

---

## Vocabulary

| Term | What it means |
| --- | --- |
| **the pin** | `[omarchy]` in `manifest.toml`: url, ref, version. Moving it is a bump. |
| **the port** | The Hyprland→Sway translation. Permanent; it will never go upstream. |
| **a carried change** | A change to upstream's tree that is *not* the port — config, a feature, or how our plugins are hosted. Each one has its own reason to exist and its own way of ending. |
| **the seam** | Everything that couples us to upstream: the patch, the `bin/` shims, the `shell.*` API the plugins call, and the theme template directory. |
| **loud** | A failure that stops the build or fails a check by name. The opposite is what §A is about. |

---

## A. A moved upstream fails the build

*Landed 2026-09-13.*

**A1** A hunk that applies at a non-zero offset fails the build. GNU patch has
no flag for this; what it does have is `--backup-if-mismatch`, on by default,
which writes a `.orig` for exactly the files that did not apply cleanly. So the
signal already exists and is merely unread: `prepare()` fails if any `.orig` or
`.rej` survives it.
→ Verified in both directions on 2026-09-13: fails against `quattro`
(three `.orig`), passes against the pin (none).

**A2** The port is complete or the build fails. After both patches,
no file under `shell/` matches `Quickshell\.Hyprland` or `\bHyprland\.`.
This is the assertion a patch structurally cannot make, and it is the one that
catches the case §A's measurement found — a *new* upstream file with a
Hyprland import in it.
→ Fails against `quattro` (`Background.qml`), passes against the pin.

**A3** No `.orig` or `.rej` reaches a package. A1 makes this automatic — the
build is already dead by then — and it is written down separately because the
two failures are independent: A1 is about whether the port is right, this is
about what `cp -a` sweeps up. It is the same class as
[[packages-dir-accumulates]] and [[stage-by-explicit-path]]: a wildcard that
takes whatever is in the directory.

**A4** The guards live in `prepare()`, next to the patches, not in a script a
bump is expected to remember to run. `makepkg` is the one thing that always
runs. **?** — the alternative is `scripts/` and a line in the bump procedure,
which is the arrangement that has already failed once for the keyboard's pkgrel
([[manifest.toml]] `[moarchy-keyboard]`).

---

## B. The patch is split by lifetime

One file mixes five changes that expire for five different reasons, so a bump
that breaks any of them breaks "the patch" and tells you nothing further. Split,
each failure names its own kind.

**Measured 2026-09-13**, `port-4x.patch`, 10 files, +242/−33:

| Concern | Files | Size | Ends when |
| --- | --- | --- | --- |
| The port | `PopupCard`, `Bar`, `KeyboardLayout`, `Workspaces`, `idle/Service` | +36/−21 | Never |
| Shell config | `config/omarchy/shell.json` | +36/−4 | Upstream reads a second config path |
| Launch feedback | `services/AppLibrary.qml` | +21/−3 | The splash moves out of upstream's launch path |
| Plugin hosting | `PluginRegistry`, `shell.qml` | +43/−4 | Upstream ships a system plugin dir and a trust model |
| The menu back button | `plugins/menu/Menu.qml` | +106/−1 | It lands upstream (§C1) |

**B1** Each row is its own `.patch`, applied in order, named for what it is:
`10-port.patch`, `20-shell-config.patch`, `30-launch-feedback.patch`,
`40-plugin-hosting.patch`, `50-menu-back-button.patch`. The
`notification-popups-bar-opt-out.patch` already sets this pattern and its
PKGBUILD comment already gives the reason — "it is MEANT to go upstream and be
deleted here once it lands" — which is a statement no hunk inside `port-4x.patch`
can make about itself.

**B2** `structure.md` Q5's fork test is measured per concern as well as in
total. The total is what Q5 asks for; the split is what says *where* it grew.
Q5 measured 9 files, +230/−30 on 2026-09-07 and it is 10 files, +242/−33 six
days later — still inside "a few hundred lines", and the growth is one new file
(`shell.qml`) in the hosting row.

**B3** The port row stays mechanical. Four of its five files change only an
import and an identifier; `Workspaces.qml` (+27/−9) is the one that carries
real semantics — sway's workspace `number` versus Hyprland's conflated `id`,
and `representation` versus a toplevel model. That asymmetry is worth keeping
visible, because it is the row that a future Quickshell I3/sway API could
delete outright.

---

## C. What leaves

**C1** The menu back button is offered upstream. It is +106/−1 — 44% of the
whole patch — and it is not a port: touch-or-no-hardware-keyboard detection and
a back affordance are not PinePhone-specific, and upstream's own launcher
dead-ends on a touchscreen exactly the same way. It is also the file with the
most drift to absorb (85 changed lines between the pin and `quattro`), so it is
the row that costs the most to carry and the most to rebase.
**?** — whether upstream wants it is not ours to decide, but the shape it would
take there is the shape it already has.

**C2** `notification-popups-bar-opt-out.patch` is deleted here when it lands
upstream, not merged into anything. It stays byte-identical to the sibling
project's copy meanwhile, which is what keeps one patch rather than two
drifting ones.

**C3** Nothing else leaves. The port is permanent by construction, the config
row is ours, and the hosting row exists because upstream sandboxed third-party
plugins in 4.0.3 and we are not a third party. That last one is the row to
re-read on every bump: it is a hole in someone else's security boundary, and it
is the only row where upstream changing its mind is a reason for us to change
ours rather than to rebase.

---

## D. The shim boundary

**D1** The set of upstream `bin/` scripts that need Hyprland is measured on
every bump, and the ones we do not shadow are a list with reasons, not a
remainder.
**Measured 2026-09-13:** upstream ships 444 scripts in `bin/`; 75 reference
`hyprctl`, `hyprland`, `hyprlock` or `Hyprland`; `bin/omarchy-*` shadows 16.
The other 59 ship as-is.

**D2** Most of the 59 are unreachable on a phone — `omarchy-hyprland-monitor-*`
is laptop and external-display plumbing, of which this device has neither. That
is a reason, and it is not the same reason as "nobody has looked".
`omarchy-system-reboot`, `omarchy-system-sleep-lock` and `omarchy-system-wake`
are in the same 59 and are *not* unreachable.
→ The check is `docs/menu-coverage.md`'s question asked of a list rather than of
a menu: for each of the 59, is there a path from the UI to it.

**D3** A bump that adds a 76th is loud. This is the `bin/` half of A2, and it
has the same shape: a count that moves without anyone deciding it should is the
failure. **?** — a count is a weak assertion (a rename keeps it steady), but it
is cheap, and the alternative is a checked-in list of 75 names that a bump has
to be diffed against by hand.

---

## E. What must not change

The seam that is already right, stated so a refactor cannot quietly take it
away.

**E1** The theme layer stays patch-free. One file — `default/themed/sway.conf.tpl`
— themes Sway from any upstream theme, through
`omarchy-theme-set-templates`'s *user* template directory. 22 themes, zero
upstream lines touched. This is the best mechanism in the project and everything
else in this file is an argument for being more like it.

**E2** The plugin layer keeps its narrow API. **Measured 2026-09-13:** 14 QML
and 5 JS files, 13,748 lines, calling **11 distinct `shell.*` members** across
169 sites — `appLibrary` (41), `hide` (36), `summon` (34), `isPluginOpen` (26),
`panelLoaders` (8), `serviceFor` (7), `toggle` (6), `bar` (6), `openPanelIds`
(2), `plugins` (2), `callIfLoaded` (1). A change that grows that list is a
change that makes the next bump harder, and the number is the thing to quote
when arguing about it.

**E3** That API survived the drift. **Measured 2026-09-13 against `quattro`:**
all 11 members still present; `Commons/` has an identical file set;
`Style.qml` is 515 lines in both; `PluginRegistry.qml` is 743 in both;
`Util.qml` moved 155→159. Seven of the ten patched files are untouched by 363
commits. The low-coupling bet is paying, and E2 is why.

**E4** `refactor.md` §F still applies and is still the largest slimming win
inside our own layer — four surfaces carry their own drag tracker (`shade` 62
lines of drag vocabulary, `drawer` 48, `recents` 40, `gestures` 32). It is not
restated here; it is not an upstream-boundary problem.

---

## Sequencing

Ordered by value over risk.

1. **§A** — six lines in `prepare()`, no behaviour, converts two silent
   failures into named ones. *Done 2026-09-13.*
2. **§D1** — a measurement, not a change. Cheap, and it sizes §D2.
3. **§B** — mechanical: split one file into five by `git diff` of the same
   tree. The result must be byte-identical to what `port-4x.patch` produces,
   which is the same test the patch itself was held to when it replaced
   `port-4x.sh`.
4. **§C1** — offered upstream; out of our hands after that.
5. **§D2** — the audit. Last, because its output is a list of reasons and
   possibly no code at all.

---

## Constraints

Not acceptance criteria — the boundaries any implementation works inside.

- **Upstream has moved.** `basecamp/omarchy` is now `omacom/omarchy`, and the
  default branch is `quattro`, not `master`. `manifest.toml:31` still names
  `basecamp` and works today by GitHub's redirect, for both the API and the
  tarball. A redirect is not a pin: the ref is what makes the build
  reproducible, and the URL is what makes it fetchable, and only one of those
  is currently under our control.
- **`quattro` is not a bump target.** v4.0.3 is still the newest tag; `quattro`
  is where the next major is being built, and it is *behind* the pin by 103
  commits as well as ahead by 363. Everything measured against it here is a
  forecast of what a bump meets, not a bump.
- **A guard that only runs on the maintainer's machine is not a guard.** §A is
  in `prepare()` because `makepkg` runs in the container, on CI, and on a bump,
  and a `scripts/` entry point runs when someone remembers.
- **The port cannot be checked by parsing QML.** `qmllint` is not on PATH under
  its own name ([[qmllint-not-on-path]]) and an offscreen parse dies at the bar
  ([[offscreen-cannot-parse-check]]). A2 is a `grep` for that reason, and a
  `grep` is enough: the import is the thing that fails to resolve.

---

## Open questions

- **Whether `20-shell-config.patch` should be a patch at all.** It is +36/−4 of
  pure configuration — a clock format, a bar id, ten plugin ids — patched into
  upstream's default `shell.json` because `structure.md` P1 forbids writing into
  `$HOME` and there is no system-level config path to write instead. If upstream
  reads a second path (`/etc/omarchy/shell.json`, or a `.d/` directory), this
  row disappears and takes the most conflict-prone hunk with it: upstream adding
  one default plugin to that array is a reject. Worth asking upstream for
  before carrying it further.
- **Whether the hosting row survives contact with upstream's trust model.**
  `pluginIsTrusted()` trusts the `moarchy.` namespace because the scoped
  `PluginShellApi` has no `panelLoaders`, no `openPanelIds` and no
  cross-plugin summon — which is most of what `moarchy.gestures` is (E2's list
  is the evidence). If upstream's sandbox grows those capabilities for scoped
  plugins, the right move is to drop the hunk and take the sandbox, not to keep
  the hole.
- **Whether A2 should also assert the positive.** It proves no Hyprland
  reference survives; it does not prove `Quickshell.I3` arrived — a hunk that
  deleted an import without adding one would pass. The counter is that
  `Workspaces.qml` and the bar would fail at runtime immediately and the
  selftest would say so, which makes it a check with a cheaper twin already in
  place. **?**
- **Whether the 59 unshadowed scripts should be removed from the package
  rather than audited.** `omarchy-config`'s `package()` installs all 444 by
  glob. A `NoInstall` list is a second list to keep in step
  ([[empty-list-means-unreadable]] is the shape of how that goes wrong), and the
  saving is a few hundred KB of shell scripts. Probably not — but D2's output is
  what decides it.
