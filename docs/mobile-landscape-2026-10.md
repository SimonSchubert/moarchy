# Omarchy on phones: landscape, packaging and a recommendation (2026-10-17)

A comparative study of every public effort to run Omarchy (or an Omarchy-like
shell) on phones, measured against moarchy's four goals:

1. **Close to real Omarchy** - track upstream, do not drift.
2. **All phone features** - calls, SMS, modem, touch/gestures, OSK, rotation,
   sensors, camera, notifications, lock screen, suspend.
3. **Plugins like real Omarchy** - install and use Quickshell plugins through
   Omarchy's own plugin system, marketplace and registry.
4. **Do not reinvent the wheel** - reuse what others already solved.

Method: shallow clones read in full (not just READMEs) of
`SimonSchubert/omarchy-mobile`, `derekross/omarchy-mobile`,
`danieljohnmorris/omarchy-phone`, `Cube-Oakley/omarchy-mobile` and
`omacom/omarchy` (branch `quattro` at `4a9c83de`, 2026-10-17); GitHub API via
`gh-taufderl`; the `pkgs.omarchy.org` aarch64 databases and file lists for
`stable`/`rc`/`edge` fetched today; one upstream package
(`omarchy-4.0.5rc1-1-aarch64`) downloaded and inspected; the plugin catalog at
`plugins.omarchy.org/catalog.json`. Nothing was installed, pushed or posted.
**[V]** marks a fact verified in code or data; **[I]** marks inference.

---

## 1. Recommendation (read this first)

**Switch from "vendor Omarchy + patch it" to "install upstream's `omarchy`
package from pkgs.omarchy.org and add a phone overlay on top of it". Copy the
mechanism `derekross/omarchy-mobile` already built and proved for this. Keep
our FP4 device stack, kernel, firmware and telephony, which nobody else has.
Rework our plugins so they no longer need the `moarchy.*` trust patch, so they
become ordinary Omarchy plugins.** Do not fork either omarchy-mobile project
wholesale. Do not keep the current vendoring model.

Concretely:

- **Base:** upstream `omarchy` + `omarchy-settings` + `omarchy-keyring` + their
  `quickshell`/`hyprland` builds from `pkgs.omarchy.org/rc/aarch64` (move to
  `stable` once aarch64 `omarchy` lands there). Note the correction in
  section 6.1: the shell is in `omarchy`, **not** in `omarchy-settings`, so
  our existing migration plan's "track omarchy-settings only" target would not
  have removed the vendored shell at all.
- **Patches:** a small series, re-applied by a pacman hook after every Omarchy
  upgrade, verified all-or-nothing against the package mtree. Reuse (MIT)
  Derek's `omamobile-omarchy-patches` tool and hook rather than writing our
  own. Each patch is an upstream PR candidate. `port-4x.patch` shrinks to
  what upstream will not take.
- **Updates:** `omarchy update` handed to a phone wrapper that runs upstream's
  update with phone stand-ins and holds boot/Limine/UKI migrations. Again
  Derek's `omamobile-update` is the model, and on the FP4 this matters *more*
  than on his Pixel because `omarchy-hw-platform` will call the FP4
  `aarch64-qualcomm` (a Snapdragon laptop) [V, section 4.4].
- **Plugins:** each phone plugin (or group) a git repo with `manifest.json` at
  its root, listed on plugins.omarchy.org, installable with
  `omarchy plugin add <url>`; the image preinstalls them from a pacman package
  that symlinks them into `~/.config/omarchy/plugins` (Derek's method) until
  upstream offers a system plugin directory, which we should propose.
- **Talk to Derek Ross.** His project is the most active (117 stars, 491
  commits in 6 days, on Omarchy's own packages), solves the same upstream-seam
  problems, and has no working modem yet; we have FP4 calls/SMS. A shared
  phone shell and a shared "phone platform" upstream conversation are worth
  more than two parallel ones. This is an outward action and needs the user's
  go-ahead.

**What we lose:** byte-level reproducibility of the Omarchy layer (upstream's
repo moves; we can only record and gate versions, not pin commits), freedom to
edit upstream's shell in place (the lock PIN pad and host-trust hacks must go
upstream or into a hook-applied patch), some image size and inert packages
(`sddm`, `uwsm`, `plymouth` get installed as dependencies), and the
cross-plugin shortcuts our gestures and apps take today (a real refactor of
the ~61k-line plugin tree, section 7).

**What we gain:** D35-class breakage disappears as a category we fix alone
(upstream's `4.0.5rc1`, built today, already carries the Qt 6.12 fix [V]),
`omarchy update` and `omarchy plugin add` work like on every other Omarchy
machine, third-party plugins from a 5,646-entry marketplace become usable, and
our work becomes upstreamable instead of trapped in a 575-line patch.

---

## 2. Comparison table

| | **moarchy (ours, taufderl fp4)** | **SimonSchubert/moarchy (our base)** | **SimonSchubert/omarchy-mobile** | **derekross/omarchy-mobile** | **danieljohnmorris/omarchy-phone** | **Cube-Oakley/omarchy-mobile** |
| --- | --- | --- | --- | --- | --- | --- |
| Target | Fairphone 4 (also sargo) | PinePhone, Pixel 3a | aarch64 QEMU VM only | Pixel 7 Pro (Pixel Fold, Pixel 6 WIP community) | OnePlus 6T | OnePlus 7 Pro, Pixel 7 Pro, OnePlus 13 |
| Compositor | Hyprland 0.56 | Sway, Hyprland in last commit | Hyprland 0.56 | Hyprland 0.56 (patched) | Hyprland 0.56 | Hyprland 0.56 + own plugin |
| Omarchy source | vendored git pin `c668141e` (4.0.4) + 3 patches | vendored pin + port patch | vendored pin v4.0.3, 6 small patches | **upstream `omarchy` package, edge channel**, patch series re-applied by pacman hook | upstream x86_64 `arch=any` packages relabelled noarch, touch patches re-applied | none: Omarchy-inspired, own shell |
| Shell / UI | 33 `moarchy.*` Quickshell plugins hosted via patched `shell.qml` (trusted namespace) | same lineage | **one** ordinary user plugin `mobile.shell`, no host patch | 10 ordinary `omamobile.*` plugins, no host trust patch | Omarchy's shell + a few QML overrides | separate Quickshell config `~/.config/quickshell/omarchy-mobile` |
| Gestures | edge gestures, layer surfaces, needs host internals | same | edge gestures inside one plugin | **none**: tap/pull UI, IPC between plugins | some (`fajita-longpress`) | own, plus `touch-fingers` Hyprland plugin |
| OSK | moarchy-keyboard (input-method-v2) | moarchy-keyboard | moarchy-keyboard | squeekboard | squeekboard | own in-shell keyboard |
| Telephony | ModemManager 1.24 (patched build), q6voiced, callaudiod, 81voltd; own Phone/Messages plugins; **calls and SMS verified on FP4** | ModemManager, plugins | none (VM) | custom: omatel agent + omaphone/omamessages (Rust GTK4) + ModemManager D-Bus shim; **not tested with a SIM** | ModemManager (patched), q6voiced, 81voltd; **SMS, data, IMS calls verified** | claims calls/texts on Pixel 7 Pro (not verified here) |
| Lock screen | PIN pad patched into upstream `LockView.qml` | patched | upstream lock, width patch | PIN pad + password patched into upstream lock (patches 0003/0011), fingerprint | swipe-up, cosmetic | own |
| Updates in the field | `pacman -Syu` against live ALARM + our repo; `omarchy-update` unsupported | same | rebuild VM | `omarchy update` -> phone wrapper | weekly custom updater | none |
| Packaging | 22 PKGBUILDs, docker builder, image/build.sh, manifest.toml (721 lines), own repo | same lineage | VM disk builder, manifest pins | ~26 PKGBUILDs, signed `[omamobile]` repo first, then `[omarchy]`, then ALARM; rootfs + fastboot installer | shell scripts + Docker | per-device scripts |
| Qt/quickshell handling | ALARM's, unpinned; vendored shell broke on Qt 6.12 (D35) | same | ALARM's | Omarchy's quickshell build, ALARM's Qt; Qt 6.12 fix carried as backport patch 0000 | ALARM's | unknown |
| Plugin compat (goal 3) | **no**: our plugins need the trust patch; foreign plugins work but scoped | no | **yes** | **yes** | partial | **no** (not Omarchy's plugin host) |
| Activity | daily | **dormant since 2026-09-19** | dormant since 2026-09-13 (licence commit 10-10) | very active (2026-10-11 -> 10-16) | dormant since 2026-09-18 | active to 2026-10-12 |
| License | MIT | MIT | MIT | MIT (apps GPL-3.0) | MIT | none stated |
| Stars | 0 | 83 | 8 | 117 | 6 | 15 |

---

## 3. The projects in detail

### 3.1 SimonSchubert/moarchy (our direct base)

- **Verified:** upstream `main` is `edb4bd8e` (2026-09-19, "Swipe between the
  workspaces that exist"), which is exactly our merge base
  (`git merge-base origin/main HEAD`). Nothing has landed since. One unmerged
  branch `right-edge-overview` (PR #3, closed). Our PR #9 ("Fairphone 4
  support") is open and unanswered since 2026-09-24. Five open issues
  (PinePhone/sargo boot loops, BT) unanswered.
- Simon's attention moved: `omarchy-mobile` (VM, Sep 9-13), then
  `omalauncher` (Android launcher with Omarchy themes and Arch under proot,
  350 stars), `omarchy-widgets` (OWL widget store, 68 forks),
  `moarchy-apps` (the Quickshell apps we vendored as `moarchy.*` apps, now
  standalone, in a signed `[market-apps]` repo), `app-finder`,
  `omarchy-mobile-market` (a plugin-market app for phones).
- **Conclusion:** there is nothing to re-sync. Treat upstream moarchy as
  finished history; Simon's newer repos are the place to reuse from (apps,
  OWL widgets, market UI), not moarchy itself.

### 3.2 SimonSchubert/omarchy-mobile

- **What it is [V]:** upstream Omarchy v4.0.3 on Hyprland 0.56.2 in an aarch64
  QEMU VM at phone geometry, mobile UI as **one** user plugin
  `default/etc/skel/.config/omarchy/plugins/mobile.shell/` (~11.8k lines
  QML/JS) switched on by `bar.id` in `shell.json`. No real hardware, ever
  (README: "The trade: moarchy runs on a phone you can hold, and this does
  not").
- **Why one plugin [V]:** "Omarchy 4.0.3 sandboxes plugins so that each can
  summon only itself ... moarchy patches the host to get round the sandbox;
  this project does not." The one plugin owns all edges and sheets, so it never
  needs another plugin's internals. Its documented limit: it cannot see or
  close a *vendored* popup (no `openPanelIds` in the facade).
- **Patches [V]** (`patches/`, each meant for upstream):
  `notification-card-max-width` (#11034), `lock-field-max-width` (#11244),
  `weather-panel-fit` (#11238), `plugin-manifest-kinds` (a real bug: manifest
  `kinds` loses `Array`-ness after a QVariant round trip; Derek found the same),
  `notification-popups-bar-opt-out` (identical in purpose to ours),
  `launch-osd-bar-opt-out`.
- **Measured Hyprland behaviour worth reusing [V]** (README "What Hyprland does
  differently from Sway"): implicit pointer grab ends at a layer surface's
  edge (edge surfaces must open their input mask full-screen during a drag);
  exclusive-keyboard layers eat pointer events; exclusive zones arrange from
  Background up; `Toplevel.activate()` ignores shell windows, so focus by
  dispatcher address; the `empty` workspace selector for one-app-per-workspace.
- **Packaging:** VM disk built by `vm/build-disk.sh` from `vm/packages/*`;
  rebuilt Hyprland because ALARM shipped a stale soname. Not a phone image.
- **Verdict:** a design reference (single-plugin shell, upstreamable patches,
  acceptance tests driven through `/dev/uinput`), not a base. Dormant.

### 3.3 derekross/omarchy-mobile (the important one)

- **What it is [V]:** "Native Omarchy on Google Pixel phones: Arch Linux ARM,
  Hyprland and Omarchy's own packages". Pixel 7 Pro (gs201) with Derek's own
  mainline v7.3 kernel work. Status 2026-10-13: "a pocket computer, not yet a
  phone". Works: display 120 Hz, GPU (Panthor, patched Mesa), touch, Wi-Fi, BT
  audio, sensors/auto-rotate, GNSS, NFC, fingerprint, haptics (feedbackd).
  Modem boots but registration/SMS/calls "need a SIM test that hasn't happened
  yet" (`docs/DEVICES.md`). Suspend WIP. 485 of 491 commits by Derek; first
  commit 2026-10-11.
- **How it tracks upstream [V]:** `rootfs/pacman.conf` orders
  `[omamobile]` -> `[omarchy]` (`pkgs.omarchy.org/@OMARCHY_CHANNEL@`, edge) ->
  ALARM. `rootfs/packages.base` installs `omarchy-keyring omarchy
  omarchy-settings` and `tools/build-rootfs` installs Omarchy's own
  `install/omarchy-base.packages` minus a skip list (one entry). This is
  Omarchy as the ISO installs it, on a phone.
- **Patch series [V]:** `packages/omamobile-omarchy/patches/` (13 patches:
  Qt 6.12 backport `b83d3df`, lock number pad, lock-state backport `d1a614c`,
  touch image picker, screensaver/OSK, idle, `bl_power` brightness, lock IPC
  wake, polkit OSK, PIN-or-password, update hand-off, a 4.0.4 menu bridge).
  `libalpm/95-omamobile-omarchy-patches.hook` fires PostTransaction on
  `omarchy`, `omarchy-dev` and itself; `bin/omamobile-omarchy-patches`
  restores pristine files from the package mtree/cache, applies with
  `--fuzz=0` in a scratch tree, verifies by reversing, then swaps; a patch
  whose reverse applies is reported as "already upstream"; failure leaves
  upstream's files untouched and notifies the user. The same tool runs at
  image build. This is a better seam than our `prepare()`-time patching
  because it survives `pacman -Syu`.
- **Update path [V]:** patch 0012 hands `omarchy update` to
  `omamobile-update`, which runs upstream's `omarchy-update -y` with stand-ins
  on `PATH` (`lib/update-bin/`): no Snapper, no AUR rebuilds, no gum prompts,
  refusals on low battery / wrong repo order / kernel or bootloader packages,
  and migrations mentioning Limine, mkinitcpio, UKIs, efibootmgr, `/boot/`,
  fwupd and others **held** for review (`docs/RELEASES.md` 5.4). An
  `omamobile.update` sheet is the UI.
- **Shell [V]:** `packages/omamobile-shell/plugins/` - `omamobile.bar`,
  `.quicksettings` (19 tiles), `.launcher`, `.home` (OWL widgets, Simon's
  `omarchy-widgets`), `.fingerprint`, `.keyboard`, `.update`, `.access`
  (portal permission sheet), `.switcher` (~20.6k lines). "Written as ordinary
  third-party Omarchy plugins. Nothing in Omarchy is patched." Installed to
  `/usr/share/omamobile/shell/plugins` and **symlinked** into
  `~/.config/omarchy/plugins` by `omamobile-setup-user` (upstream's catalog
  walks that dir with `find -L`). Cross-plugin control goes through
  `omarchy-shell`/`qs ipc` calls instead of host internals. No edge-swipe
  gesture layer: the UI is tap/pull driven. OSK is squeekboard.
- **Plugin API limits it documents [V]** (`plugins/README.md`, "Plugin API
  limits found"): no third-party lock input (hence lock patches in Omarchy),
  `menu`-kind plugins lose their facade (the `kinds` bug), panel plugins get no
  inline settings, panel plugins cannot reach do-not-disturb. These are the
  same walls we hit; they are a ready-made upstream issue list.
- **Telephony [V]:** Exynos modem has no ModemManager plugin, so he wrote
  `omatel` (agent, GPL-3.0), `omaphone`, `omamessages` (Rust, GTK4/libadwaita)
  and `omamobile-mmd` (a ModemManager D-Bus facade so GNOME Calls/Chatty/NM
  can work). None in the default image yet. **Not reusable for the FP4** as a
  backend (we have real ModemManager); the apps might be, since they speak
  their own D-Bus API, not MM - **[I]** probably not worth it versus our
  plugins.
- **Verdict:** the best available *architecture*. Its hardware layer is
  Pixel-specific and its telephony is behind ours.

### 3.4 Other phone efforts (found by search, read briefly)

- **danieljohnmorris/omarchy-phone** (OnePlus 6T, SDM845, pmOS kernel) [V]:
  closest *hardware stack* to ours - ModemManager rebuilt with four patches
  (`scripts/mm-patches/`), q6voiced, 81voltd, squeekboard. Status claims SMS
  both ways, LTE data and IMS calls with earpiece audio. Omarchy installed from
  x86_64 `arch=any` packages relabelled (`repack-noarch.sh`), touch patches
  re-applied, weekly custom updater. Dormant since 2026-09-18. Worth reading
  for its ModemManager patches and q6voiced call-audio notes against our D33.
- **Cube-Oakley/omarchy-mobile** [V]: "Omarchy-inspired" separate Quickshell
  shell (`overlay/mobile/`, Python backends) on OnePlus 7 Pro / Pixel 7 Pro /
  OnePlus 13. Not Omarchy's plugin host, so drift by design. Reusable piece:
  `overlay/mobile/touch-fingers/` - a Hyprland plugin fixing 0.56 sending all
  fingers' motion to the last finger's surface (relevant to our gestures).
- **turbineBMW/omarchy-mobile-packages** (OnePlus 6T signed repo, empty
  otherwise), **modpunk/Omarchy-Phone** (iPhone 6s, no touch),
  **cbarland/omarchy-mobile-android** (rootless Android adapter built on
  Derek's shell), **ToniMcQueen/oneplus6t-...** (Hyprland + wvkbd +
  ModemManager + GNOME Calls). All small or early.
- **Tablet/convertible plugins on the marketplace** (all ordinary Omarchy
  plugins) [V, catalog]: `orientation` (auto-rotate), `andreiyurik
  omarchy-tablet-mode`, `djc.tomb-stone`, `cavacuz.tablet`, OSKs
  (`m44f4.omatouch`, `ekollof.osk`, `io.github.mtolhuys.onscreen-keyboard`),
  `rainan16.workspace-touch-swipe` (edge swipes), WWAN/LTE widgets over
  ModemManager (`tomv.lte`, `erruviel.wwan`, `serg3k ... wwan`),
  `io.github.sirmenef.workspace-overview`. `yeutterg/omarchy-tablet` also has a
  lock PIN pad. **Upstream demand for touch exists outside phones**, which
  helps our upstream PRs.
- **hyprgrass** (603 stars, active 2026-10-16): Hyprland touch-gesture plugin.
  We do gestures in QML layer surfaces instead; hyprgrass is the off-the-shelf
  alternative for workspace/edge swipes **[I]** worth a spike, but Hyprland
  plugins break on every Hyprland bump (Cube-Oakley documents this).

### 3.5 Reusable phone-stack pieces (postmarketOS world)

Already used by us: ModemManager, callaudiod, feedbackd group, iio-sensor-proxy
via libssc rules (`pkgbuilds/moarchy-device-fp4/81-libssc-fairphone-fp4.rules`),
q6voiced, 81voltd, megapixels. Available and used by peers: squeekboard (OSK,
Derek and Daniel), GNOME Calls and Chatty (ModemManager UIs), wvkbd, neard.
**[I]** We should not replace our working Phone/Messages plugins with GNOME
Calls/Chatty (they are GTK apps outside Omarchy's theming), but Calls is the
reference behaviour for edge cases (DTMF, call waiting, emergency) and its
`callaudiod` integration is the one we already share.

---

## 4. Upstream Omarchy: what it already provides

### 4.1 Platform and packages [V]

- aarch64 is a supported platform with families `aarch64`, `aarch64-apple`,
  `aarch64-qualcomm`, `aarch64-n1x`, `aarch64-gb10`
  (`bin/omarchy-hw-platform`, `install/omarchy-aarch64*.packages`).
- `pkgs.omarchy.org`, counted today: stable/aarch64 ~99 packages, **no
  `omarchy`**; rc/aarch64 ~176 incl. **`omarchy 4.0.5rc1-1`,
  `omarchy-settings 4.0.5rc1-1`, `omarchy-keyring`, `quickshell
  0.3.2.r7.g2b4501a-1`, `hyprland 0.56.2-7`** (new since yesterday's scan);
  edge/aarch64 ~199 incl. `omarchy 4.0.4-2`.
- Recipes are public: `omacom/omarchy-pkgs` (PKGBUILD per package, pinned
  sources mandatory, CI builds x86_64 and aarch64, PRs accepted from anyone).
  `omarchy` and `omarchy-settings` 4.0.4 build `_commit=c668141e` - **the same
  commit as our `[omarchy]` pin**, so a switch at 4.0.4 changes no Omarchy
  code.
- `omarchy 4.0.5rc1` depends on `omarchy-keyring omarchy-themes-intros
  omarchy-settings=4.0.5rc1 hyprland quickshell uwsm sddm
  xdg-desktop-portal-hyprland wireplumber pipewire gnome-keyring gum jq git perl
  fakeroot pacman-contrib ttf-jetbrains-mono-nerd-basic networkmanager`.
  `quickshell` is unversioned and itself depends on ALARM's unversioned
  `qt6-base`/`qt6-declarative`. **Upstream does not pin Qt either.** What it
  does is ship a fixed shell fast: `b83d3df0` (2026-10-08) is in the
  `4.0.5rc1` package built 2026-10-17 [V: `import qs.Commons as Commons` in
  its `Bar.qml`], but **not** in 4.0.4 on edge/stable.

### 4.2 Plugin system, marketplace, registry [V]

- A plugin is a git repo with `manifest.json` at its root. `omarchy plugin
  add <git-url>` clones into `~/.config/omarchy/plugins/<id>/` after
  `omarchy-plugin-validate`; `update` shows a diff and fast-forwards; also
  `enable/disable/clone/remove/list/catalog` (`bin/omarchy-plugin-*`,
  `docs/omarchy-shell.md`). Only `$OMARCHY_PATH/shell/plugins` (first-party)
  and `~/.config/omarchy/plugins` are scanned; **there is no system-wide
  plugin directory** (checked in `4.0.5rc1`'s `PluginRegistry.qml`).
- Third-party plugins get capability-scoped facades: own service and
  lifecycle only; full-bar plugins get more (bar config snapshots, proxies for
  non-auth services, lifecycle of configured UI plugins); authentication is
  stamped only on first-party manifests.
- **Marketplace:** `plugins.omarchy.org` (was omarchyplugins.com,
  `omacom/omarchy-plugin-marketplace`, 355 stars): 5,646 listings, 4,057
  "verified" (commit-pinned scan + maintainer approval). Install commands
  still clone mutable HEAD.
- **Registry:** `omacom/omarchy-plugin-registry` (Rails, crates.io-style signed
  index + immutable tarballs, `publisher/name`, kill-bit). Registry side built;
  the Quattro client (`omarchy plugin add publisher/name`) "not yet done,
  required before launch".
- Simon's `omarchy-mobile-market` README links "Omarchy Mobile" to
  `github.com/omacom/mobile`, which returns 404 to us. **[I]** Either private
  or never created; do not plan around it, but ask.

### 4.3 Touch and mobile upstream [V]

No phone, OSK or touch-first work upstream: `git log` shows touchpad/touchscreen
toggles and rotated-monitor fixes only; no squeekboard/OSK code. Input methods
are Fcitx (`docs/input-methods.md`). Upstream policy "the experience should be
the same on every platform" (AGENTS.md) means touch fixes are in scope, not
alien.

### 4.4 Lifecycle dispatch and platform detection [V]

`docs/lifecycle-dispatch.md`: platforms whose boot chain the generic flows
cannot drive (Apple: m1n1 -> U-Boot -> Limine) register a boot package and a
runtime package (`omarchy-mac-boot`, `omarchy-mac`) that implement fixed
operations (`update-verify`, `update-takeover`, `setup-boot`, `setup-system`,
`setup-user`, ...). **Registration is code in `bin/omarchy-lifecycle-dispatch`,
not config.** A phone (Android ABL, `boot.img`, no Limine/UKI) is exactly this
case. Today any `qcom,*` compatible makes the FP4 `aarch64-qualcomm`, whose
`install/hardware/qualcomm/` extracts Windows firmware and builds a UKI. Derek's
Pixel resolves to plain `aarch64` and dodges this; **we cannot**. The clean
upstream fix is a phone family (e.g. `aarch64-phone`, matched on phone DT
vendors or an image-target manifest) with an `omarchy-phone-boot` package
implementing `update-verify`/`setup-boot` as no-ops or as `boot.img` checks.

---

## 5. Our pipeline, critically

### 5.1 What is fragile

1. **Vendored pin + floating ALARM underneath [V].** `manifest.toml` pins
   Omarchy to `c668141e`; `image/build.sh` pacstraps from the live
   `mirror.archlinuxarm.org`; phones update with `pacman -Syu` against it.
   Qt/quickshell are pinned nowhere (`moarchy-meta` depends on bare
   `quickshell`). Result: D35 (commit `360b644`) - a 1,874-line backport
   patch plus 16 plugin edits, and a hand hotfix on the handset. Every future
   Qt/quickshell API change repeats this, because our shell is frozen while
   the runtime moves. Upstream fixed it nine days earlier.
2. **The trust hack [V].** `port-4x.patch` makes `pluginShellFor()` return
   the real `shell` for any manifest whose id starts with `moarchy.`. The
   comment says the namespace "cannot be squatted from ~/.config", but
   `omarchy plugin add` will install any repo whose manifest says
   `"id": "moarchy.anything"` into `~/.config/omarchy/plugins`, and the host
   then trusts it with full host objects. **[I]** That is a privilege
   escalation path for third-party code (bounded, since all plugins run
   unsandboxed in the same process anyway, but it defeats upstream's
   facade/auth separation). It also guarantees our plugins can never be
   distributed as normal plugins.
3. **Patch at build time only.** `prepare()` patches the vendored tree; there
   is no path where upstream's package and our patch coexist on a phone. The
   A1-A4 guards in `docs/upstream.md` are good, but they guard a model that
   should go.
4. **Unsigned third-party repo in the builder [V].** `docker/Dockerfile.builder`
   and `image/Dockerfile` add `[danctnix]` with `SigLevel = Never`, still used
   for `libdng`/`libmegapixels`. Build those ourselves or vendor them.
5. **No upgrade-path test.** `image/verify.sh` checks the built image; nothing
   boots an image and runs `pacman -Syu` against today's ALARM to see what an
   in-field phone will get tomorrow. D35 would have been caught by that.
6. **CI is manual-only** (`.github/workflows/build-fp4.yml`,
   `workflow_dispatch`). Nothing notices an upstream or ALARM move until a
   human builds.

### 5.2 What is over-engineered

- `manifest.toml` is 721 lines, much of it prose. Pins for things upstream
  now ships (`yay`, `xdg-terminal-exec`, `ttf-ia-writer`, `mise-bin` exist on
  pkgs.omarchy.org) are maintenance we can drop.
- R8-style "one version per directory" machinery protects our own repo from
  stale globs, which is real, but it does not deliver what its wording implies
  (reproducible images) because the bulk of the image comes from unpinned
  ALARM. Either pin ALARM (local snapshot mirror) or stop implying
  reproducibility.
- `moarchy-meta` still pulls Sway-era and desktop-heavy packages
  (`swaylock`, `swayidle`, `xdg-desktop-portal-wlr`, `wlsunset`,
  `libreoffice-fresh`, `kdenlive`) [V, dependency list]. **[I]** Most are
  dead weight on a Hyprland phone whose lock is Omarchy's.
- Re-implementing app hosting (33 plugins, 61k lines, focus/hide by name)
  where upstream's model is "apps are windows, the shell is plugins".
  Simon himself moved his apps out to standalone Quickshell processes
  (`moarchy-apps`).

### 5.3 What is missing

- A channel concept (rc/stable) and `omarchy update` support.
- Any way for a user to install our plugins or third-party plugins the
  Omarchy way and have them work alongside ours.
- A phone platform identity upstream (section 4.4).
- Pinning or gating of the Qt/quickshell/hyprland stack.

### 5.4 Against the alternatives

| Concern | ours | Derek | Simon VM | upstream itself |
| --- | --- | --- | --- | --- |
| Omarchy layer | vendored + build-time patch | upstream package + hook-applied patches | vendored, minimal patches | the source |
| Update in field | pacman -Syu, no omarchy-update | omarchy update via phone wrapper | n/a | omarchy update |
| Repo order | moarchy, ALARM | omamobile, omarchy, ALARM | n/a | omarchy, Arch |
| Pinning | own builds pinned, ALARM floating | own builds pinned, omarchy+ALARM floating, MANIFEST records versions | pins | pinned sources, channels |
| Image | image/build.sh, verify.sh | build-rootfs + fastboot installer + release bundle | VM disk | ISO + image-target manifest |
| Plugin delivery | packaged, trusted namespace | packaged, symlinked into user dir | skel copy into user dir | git clone into user dir |

---

## 6. Corrections to our own docs

1. **`omarchy-settings` does not contain the shell [V].** In the `4.0.5rc1`
   file list, `omarchy` owns all 223 `usr/share/omarchy/shell/` files plus
   `bin/` and `themes/`; `omarchy-settings` owns `usr/share/omarchy/default`,
   `config`, `/etc/skel`, plymouth and sddm themes. The target in
   `docs/omarchy-aarch64-migration-plan.md` ("Track `omarchy-settings`, not
   `omarchy`") would keep the vendored shell. To track upstream's shell we
   must install `omarchy` and live with its dependencies (install `sddm` and
   `uwsm` but do not enable them; keep tty1 autologin) - Derek does install
   `omarchy` (he uses SDDM autologin).
2. **Gate 0 is closer than the scan said:** aarch64 `omarchy`,
   `omarchy-settings` and `omarchy-keyring` are on **rc** now, not only edge.
   **[I]** Waiting for stable is optional; rc is a reasonable channel for a
   pre-1.0 phone image, and rc already has the Qt 6.12 fix that stable lacks.
3. `omarchy-settings` ships Limine and mkinitcpio drop-ins on aarch64 (its
   PKGBUILD says so). Check they do not alter our initramfs/boot.img path
   before switching.
4. `docs/upstream.md` still describes the Sway port in places (it carries an
   override note); the comparison tables in Simon's READMEs describe moarchy as
   Sway. Neither matters after the switch.

---

## 7. Options rated against the goals

Scores 1 (bad) to 5 (good). Effort is relative to today.

| Option | G1 close to Omarchy | G2 phone features | G3 plugins like Omarchy | G4 reuse | Effort | Notes |
| --- | --- | --- | --- | --- | --- | --- |
| **A. Keep ours** (vendor + patch + trusted plugins) | 1 | 4 | 1 | 2 | none now, recurring D35s | drift grows; every Qt/quickshell move is ours to fix |
| **B. Upstream packages + hook-applied patches + our plugins made ordinary** (recommended) | 4 | 4 | 4 | 4 | medium-high | keeps FP4 features; plugin refactor is the cost |
| **C. Rebase onto derekross/omarchy-mobile** (adopt his shell + infra, add FP4 device package, port our Phone/Messages as plugins) | 4 | 3 (lose edge gestures, our settings/control center; modem stack is ours anyway) | 5 | 5 | high, plus coordination | best long-term if Derek agrees to a shared shell; his repo is Pixel-centric |
| **D. Rebase onto SimonSchubert/omarchy-mobile** | 3 (pinned 4.0.3, vendored) | 1 (no hardware, no telephony) | 5 | 3 | high | dormant, VM-only |
| **E. Separate Quickshell shell** (Cube-Oakley style) | 1 | 4 | 1 | 2 | very high | the drift we are trying to escape |
| **F. Re-sync with SimonSchubert/moarchy** | 1 | 2 | 1 | 1 | n/a | nothing new upstream since our fork point |

B and C converge: B is C done incrementally, starting with infrastructure
(which is uncontroversial to reuse, MIT) and deciding the shell question with
Derek once our plugins are ordinary plugins and can run on either base.

### How our plugins become installable like normal Omarchy plugins

1. **Remove the dependency on host internals.** Inventory every use of
   `shell.panelLoaders`, `shell.openPanelIds`, hiding other plugins by name and
   the registry objects (8 plugin trees touch `panelLoaders`/`openPanelIds`
   today [V]). Three tools, in order of preference:
   - merge the tightly coupled core (bar, gestures, app-drawer, control
     center, overview, splash) into **one** `moarchy.shell` full-bar plugin,
     as Simon did - inside one plugin, "hide the drawer" is a local call;
   - for apps and screens, use upstream IPC (`omarchy-shell shell summon/hide
     <id>`, `call <id> <method>`) as Derek does;
   - for what neither can do (see/close a first-party popup, raise a shell
     window), propose a facade extension upstream for full-bar plugins.
2. **Apps out of the shell where it makes sense.** Calculator, games, coins,
   habits, launches, editor, files, keep: either keep them as panel plugins
   that need nothing from the host, or adopt Simon's standalone
   `moarchy-apps` builds (same lineage, already packaged for aarch64). Phone,
   Messages, Contacts, Settings, NFC stay plugins (they need to stay loaded).
3. **Qt 6.12-clean imports** (`import qs.Commons as Commons`), which upstream
   now requires of third-party plugins (`docs/omarchy-shell.md`).
4. **Repo layout:** one git repo per plugin (or a monorepo plus one thin repo
   per listed plugin), `manifest.json` at root, README, LICENSE, so
   `omarchy plugin add https://github.com/taufderl/moarchy-<x>.git` works and
   the plugin can be submitted to plugins.omarchy.org (and later the signed
   registry as `taufderl/<x>`).
5. **Image delivery:** a `moarchy-shell` pacman package installs the plugins
   under `/usr/share/moarchy/plugins` and a first-run step symlinks them into
   `~/.config/omarchy/plugins` and seeds `shell.json` once (Derek's
   `omamobile-setup-user` pattern, using `omarchy-done` markers). Propose
   upstream a read-only system plugin dir (our `systemPluginsDir` hunk is
   already that patch) so the symlink step can go.

---

## 8. Migration path (ordered)

Each step keeps the previous image flashable. Outward steps (PRs, posting,
contacting people, flashing) need the user's explicit go-ahead.

1. **Pin the runtime now (stopgap, small).** Record `qt6-base`,
   `qt6-declarative`, `quickshell`, `hyprland` versions in `manifest.toml` and
   make `image/verify.sh` fail on a mismatch; add an upgrade-path check (boot
   the image in a container/chroot, `pacman -Syu --print` against ALARM, flag
   Qt/quickshell moves). Catches the next D35 before a phone does.
2. **Inventory `port-4x.patch` and the two other patches** into: upstreamable
   (lock PIN pad, notification opt-out, user-units tolerance, system plugin
   dir, manifest-kinds fix), overlay (shell.json profile, AppLibrary splash
   hook), obsolete (Qt 6.12 at >= 4.0.5). Compare with Derek's 13 and Simon's
   6 patches; several are the same change three times.
3. **Make the plugins ordinary** (section 7). Prove it on the current
   vendored base by deleting `pluginIsTrusted()` from the patch and passing
   the FP4 UI checks (bar, drawer, control center, gestures, lock, Phone ring
   with window closed, OSK, rotation). This is the largest step and is
   independent of the package switch.
4. **Switch the base to upstream packages** on a branch:
   `[moarchy]` -> `[omarchy]` (`pkgs.omarchy.org/rc/$arch`, keyring in the
   image trust) -> ALARM; install `omarchy` (+ its deps, `sddm`/`uwsm` not
   enabled), drop `omarchy-config`'s vendoring (final empty release with
   `replaces`/`conflicts`), drop our `yay`/`xdg-terminal-exec`/`ttf-ia-writer`
   builds. Port Derek's `omamobile-omarchy-patches` + hook (MIT, keep
   attribution) as `moarchy-omarchy` with our reduced series.
5. **Guard the platform.** Until upstream has a phone family, make the phone
   update wrapper (port of `omamobile-update`) refuse or hold anything that
   runs `install/hardware/qualcomm/`, Limine, UKI, mkinitcpio or `/boot`
   migrations, and verify on the FP4 that `omarchy-hw-platform` /
   first-run do not touch the boot path.
6. **Turn on `omarchy update`** through the wrapper; remove the "unsupported"
   rows in `docs/settings.md` and `docs/menu-coverage.md`.
7. **Upstream, smallest first:** the manifest-kinds bug, notification/launch
   opt-outs, lock PIN input mode (Derek's README already specifies the
   design), system plugin directory, then the phone platform family +
   lifecycle registration. Coordinate with Derek so one PR exists per topic.
8. **Publish the plugins** to plugins.omarchy.org once they install cleanly on
   a stock Omarchy desktop too (where hardware allows).
9. **Decide the shell question with Derek** (option C): one shared phone
   shell with device packages per phone, or two shells sharing upstream
   patches and plugins.

### Risks

- **Misdetection as a Snapdragon laptop** (highest). Mitigation: step 5
  before step 6; a boot-path diff check after every update on the handset.
- **Upstream moves faster than our patches.** Mitigated by the hook's
  all-or-nothing behaviour (worst case: upstream's files unpatched, lock
  without PIN pad until a fixed series ships). Keep the series short.
- **rc channel instability.** Pre-releases can break; record the version
  installed in the image, and keep the previous image as a release.
- **Upstream assumes a laptop** beyond hardware scripts (sddm session,
  floating window sizes, keyring prompts: Daniel's README lists several).
  Expect an overlay of Hyprland Lua overrides, as all three peers carry.
- **Size and inert packages.** The `omarchy` aarch64 package alone is ~120 MB
  compressed [V]; plus Omarchy's base list. Check userdata headroom.
- **Coordination cost** with another maintainer, and GPL-3.0 on Derek's
  telephony apps if we ever take them (we should not need to).

### What we would lose

- Exact control of every Omarchy byte and the "one pin moves everything"
  model (R8 becomes "versions recorded and gated").
- Direct edits to upstream's shell; lock PIN pad lives in a hook-applied
  patch until upstream takes an input mode.
- The trust shortcut: some cross-plugin behaviour must be rebuilt over IPC
  or inside one plugin.
- sargo/PinePhone parity, unless they move too (they are not the focus).

---

## 9. Evidence index

- Ours: `pkgbuilds/omarchy-config/{PKGBUILD,port-4x.patch,qt612-qualify-color.patch}`,
  `manifest.toml` `[omarchy]` (`c668141e`), commit `360b644`,
  `image/build.sh` (pacman.conf, lines ~225-246), `docker/Dockerfile.builder`,
  `pkgbuilds/moarchy-meta/PKGBUILD`, `.github/workflows/build-fp4.yml`,
  `docs/structure.md` R8/R8a, `docs/omarchy-aarch64-migration-plan.md`.
- SimonSchubert/moarchy: head `edb4bd8e` (2026-09-19) = our merge base; PR #9.
- SimonSchubert/omarchy-mobile: `README.md`, `manifest.toml`, `patches/`,
  `default/etc/skel/.config/omarchy/plugins/mobile.shell/`.
- derekross/omarchy-mobile (`1155a7c`, 2026-10-16): `rootfs/{pacman.conf,packages.base,packages.omamobile}`,
  `tools/build-rootfs`, `packages/omamobile-omarchy/{libalpm,bin,patches}`,
  `packages/omamobile-shell/{install,bin/omamobile-setup-user,plugins/README.md}`,
  `docs/RELEASES.md` 5.4, `docs/DEVICES.md`.
- danieljohnmorris/omarchy-phone: `omarchy-android-oneplus6t/README.md`,
  `scripts/mm-patches/`, `scripts/repack-noarch.sh`.
- Cube-Oakley/omarchy-mobile: `README.md`, `overlay/mobile/README.md`.
- Upstream: `omacom/omarchy` `quattro` `4a9c83de` (`bin/omarchy-plugin-*`,
  `bin/omarchy-hw-platform`, `docs/lifecycle-dispatch.md`,
  `docs/omarchy-shell.md`, `manual/32-shell-plugins.md`), `b83d3df0`;
  `omacom/omarchy-pkgs` (`pkgbuilds/{omarchy,omarchy-settings,quickshell}`);
  `omacom/omarchy-plugin-marketplace`; `omacom/omarchy-plugin-registry`;
  `pkgs.omarchy.org/{stable,rc,edge}/aarch64/omarchy.{db,files}` and
  `omarchy-4.0.5rc1-1-aarch64.pkg.tar.zst` (2026-10-17);
  `plugins.omarchy.org/catalog.json` (5,646 entries).
