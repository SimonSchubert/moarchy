# Project structure — specification

How the three repos, the packages, the package repository and the image builder
fit together, and what has to be true before a PinePhone image can be built at
all.

Status: **proposed, not agreed.** Nothing here is built yet. The acceptance
criteria are the contract to argue with before any of it is; where one is my
reading rather than your decision it is marked **?**.

The archaeology of how we got here lives in [build-log.md](build-log.md). This
file is the destination.

---

## 1. What this decides

Today the project is a config overlay with an on-device installer. `install.sh`
sources eight scripts that clone upstream Omarchy at a pinned SHA, mechanically
rewrite five QML files, build Go programs, and write `~/.config` — all on the
phone, at install time, over SSH.

That shape cannot produce an image. An image build has no phone, no SSH, no
network guarantees and no user session. Everything the installer does at run
time has to happen at *build* time instead, and the only mechanism Arch has for
"work done at build time, replayed identically later" is a package.

So the structural question is not "how do we arrange the repos". It is **"what
is a package, and where do packages come from"**, and the repo layout falls out
of the answer.

### 1.1 The deliverable is not an ISO

The PinePhone has no BIOS, no UEFI and no El Torito. It boots by having the
Allwinner A64 BROM read u-boot SPL from raw sectors near the start of the boot
medium. What ships is a GPT disk image, written with `dd`.

Measured on `archlinux-pinephone-barebone-20251224.img`, which is what
moarchy installs onto today:

| | |
| --- | --- |
| u-boot SPL | `eGON.BT0` magic at byte **131072** (128 KiB), ahead of the GPT's first partition |
| `boot` | FAT, LBA 16384, **122 MiB** |
| `rootfs` | ext4, LBA 266240, **2906 MiB** |
| Total | 3,183,512,064 bytes raw / 522 MB as `.img.xz` |

The artifact this project ships is therefore
`moarchy-pinephone-<date>.img.xz` plus a checksum. Wherever this document says
"image", that is what it means.

---

## 2. Non-goals

Explicitly out of scope, so the ACs stay honest:

- **A distribution.** We are not forking Arch Linux ARM or DanctNIX. Their
  kernel, u-boot, firmware, modem stack and ALSA UCM profiles are consumed as
  packages from their repos, never rebuilt here.
- **x86_64 anything.** No desktop image, no VM image, no CI matrix.
- **eMMC installer.** v1 is an SD image. Installing to internal storage is a
  later, separate artifact.
- **Reproducible builds in the Debian sense.** Byte-identical rebuilds are not
  a target. Reproducible *inputs* — the same pins producing the same package
  versions — are (§8).
- **Signed images or secure boot.** The package repo gets a signing key (R5);
  the image does not.
- **Hosting anyone else's packages.** The repo carries what this project builds
  and nothing more.

---

## 3. The shape

```
  moarchy-keyboard ──┐
  moarchy-store   ───┤            ┌──────────────┐        ┌─────────┐
  AUR rebuilds    ───┼──► build ──► moarchy.db   ├──► pacstrap ──► .img.xz
  omarchy-config  ───┤   (aarch64  │ (aarch64)   │        │ + boot  │
  moarchy   ───┘    container)             │        └─────────┘
                                  └──────┬───────┘
                                         │
                             pacman -Syu │ on a phone already in the field
                                         ▼
```

Two consumers, one producer. The image build and the running phone install the
*same bytes*, which is the property that makes "it works on my phone" mean
something about the image.

---

## 4. Repository boundaries

**B1** `moarchy-keyboard` and `moarchy-store` stay separate repos and are **not
submodules of anything.** They are consumed as built packages, pinned by
version (§8), never as source trees.

> Why not submodules, since that is the obvious answer: a submodule pins source,
> and this project needs binaries. Under a submodule every image build compiles
> Qt6 C++; under a package it is built once. A submodule also has no upgrade
> path — a phone in the field runs `pacman -Syu`, and no submodule can serve
> that. The one thing a submodule genuinely buys, a reproducible pin, §8 buys
> without dragging in the source. `docker/build-packages.sh:22` already clones
> the keyboard from GitHub rather than vendoring it; this makes that deliberate
> instead of incidental.
>
> Submodules would be right if the components were edited in lockstep with the
> configs every commit, or needed shared build flags. Neither is true: both have
> their own build, their own tests and their own README.

**B2** Each component repo owns the PKGBUILD that builds it. It is the single
source of truth for *how* that component is built. `moarchy` owns only
*which version* is built.

**B3** `moarchy` is the integration repo. It owns the package
definitions for things with no upstream of their own, the package repository
tooling, the image builder, the device docs, and the dev loop.

**B4** The package repository tooling and the image builder live in
`moarchy` under `repo/` and `image/`. They do not get their own repo until
one of them has CI worth isolating.

**B5** No component repo depends on `moarchy` at build time. The keyboard
builds from a clean checkout with `cd packaging && makepkg`, as it does today;
the store likewise. If either needs something from here, that thing is wrong.

### Target layout

```
moarchy-keyboard/          unchanged; packaging/PKGBUILD is its build recipe
moarchy-store/             unchanged; PKGBUILD + its own signed catalogue
moarchy/
├── manifest.toml          the version pins — the only file that says "v0.2.0"
├── pkgbuilds/
│   ├── moarchy/         bin/ default/ config/
│   ├── omarchy-config/        upstream pin + port-4x.patch
│   ├── moarchy-meta/    the package list, as depends=()
│   └── <aur rebuilds>/        yay, xdg-terminal-exec, ttf-ia-writer, …
├── repo/                  build container → repo-add → moarchy.db → publish
├── image/                 pacstrap a rootfs + boot chain → .img.xz
├── bin/ default/ config/  packaged by pkgbuilds/moarchy
├── scripts/               dev loop: provision.sh, flash-sd.sh
└── docs/
```

---

## 5. Packages

**P1** `moarchy` (`arch=any`) contains `bin/`, `default/` and `config/`
and nothing else. `pacman -Ql moarchy` lists no path under `/home` and no
path under `/etc` that another package owns.

> A package named `moarchy` inside a repository named `moarchy` (R1) is
> deliberate, not an oversight of the rename. Pacman namespaces the two
> separately — `moarchy/moarchy` is how it would be written out in full, and
> `[moarchy]` in `pacman.conf` never collides with a package of that name. It
> is also what upstream does: `omarchy` is a package in `pkgs.omarchy.org`.

**P2** `omarchy-config` (`arch=any`) contains upstream Omarchy's configuration
and theme layer at the pin currently in `install/vendor-omarchy.sh`
(`346e69e`, v4.0.2), installed to the path upstream hardcodes.

**P3** The Hyprland→Sway translation that `install/port-4x.sh` performs at
install time is applied at **build** time, in `omarchy-config`'s `prepare()`.

**P4** That translation is a checked-in `.patch` applied with `patch -p1`, not
a script of `sed` expressions.

> A patch that no longer applies fails the build loudly and names the hunk. A
> `sed` pass against a moved upstream silently matches nothing and ships a
> package whose QML still imports `Quickshell.Hyprland` — which is the exact
> class of failure this project keeps paying for. 342 lines of imperative
> rewriting is also not reviewable as a diff; a diff is.

**P5** `moarchy-meta` (`arch=any`) has no files. Its `depends=()` is the
package set, and it is the only place that set is written down.

> The failure mode this prevents has already happened once: `docker/` built
> `walker` and `elephant` while `install/build-src.sh` did not and
> `moarchy-base.packages` documented both as unused in 4.x — three lists,
> two of them right. That divergence is fixed, but nothing structural stops the
> next one. One list, in one file, with pacman resolving it, does.

**P6** `moarchy-base.packages` and `moarchy-extras.packages` are
deleted. Their contents become `moarchy-meta`'s `depends`, and their
comments — every one of which explains why a package is present or why an
upstream one is absent — move with them.

**P7** `moarchy-store` is in the package set. It is absent from every file in
this repo today.

**P8** Everything the installer does that a package cannot — group memberships
(`input`, `feedbackd`), the logind power-key drop-in, autologin, the
`~/.config` population in `install/config.sh` — is either a file the package
ships under `/etc` or `/usr/share/factory`, or runs once from a first-boot
systemd unit that disables itself.

**P9** `install.sh` and `install/` are deleted. What replaces them is one
pacman transaction (§11, M2).

**P10** No package in this project runs `git clone` in `build()`. Sources are
fetched by `source=()` with a checksum, or by a tag `makepkg` can verify.

---

## 6. The package repository

**R1** A pacman repository named `moarchy` is published for `aarch64`, with a
`moarchy.db` at a stable URL.

> This is the aarch64 half of the thing the README already measures as missing:
> `pkgs.omarchy.org/stable/x86_64/omarchy.db` → 200,
> `.../aarch64/omarchy.db` → 404.

**R2** It contains every package this project builds: the keyboard, the store,
the AUR rebuilds, `moarchy`, `omarchy-config`, `moarchy-meta`.

**R3** Packages are built in an `aarch64` container, natively on Apple Silicon —
the existing `docker/Dockerfile.builder`, generalised from a fixed list to
`manifest.toml`.

**R4** Adding the repo to a stock DanctNIX phone is one `pacman.conf` stanza,
and `pacman -S moarchy-meta` then installs the whole environment.

**R5** The repo database is signed, and the public key ships in a
`moarchy-keyring` package. `SigLevel = Required` in the stanza from R4.

**R6** Republishing is idempotent: running the build twice with an unchanged
`manifest.toml` produces the same package versions and does not bump `pkgrel`.

**R7** `packages/*.pkg.tar.*` as a directory of loose artifacts shipped over
`scp` (`scripts/provision.sh:108`) is gone. The repo is how packages reach the
phone.

---

## 7. The image

**I1** `image/` produces `moarchy-pinephone-<date>.img.xz` and a `.sha256`,
from a single command, with no phone attached.

**I2** The rootfs is built by `pacstrap`-ing into a directory: DanctNIX's base
plus `moarchy-meta` from the `moarchy` repo. It is never produced by
booting a phone and imaging the card back.

**I3** The boot chain — u-boot SPL at 128 KiB, the FAT `boot` partition, the
kernel and DTB — is reused from DanctNIX's packages, not rebuilt. **?** The
mechanism by which their images assemble it is unverified; this AC may become
"copy the boot partition and pre-GPT region out of their release image
verbatim", which is honest and works.

**I4** The image boots to a Sway session on a real PinePhone with no SSH step in
between. This is the acceptance test for the whole document.

**I5** The USB gadget is left as DanctNIX ships it. Access to a running phone is
over wifi.

> The RNDIS→CDC-ECM switch was tried and abandoned: the patch applied cleanly
> and `usb_f_ecm` really is built into the kernel, but macOS binds the interface
> and the gadget side never gains carrier. Carrying a gadget config that reads
> like it should work costs more than it saves.

**I6** The builder can produce a **debug image** with wifi credentials
preseeded, so a freshly flashed card joins the network on first boot with no
keyboard. The PSK comes from the environment, never a flag or a checked-in file.

**I6a** A published image carries no credentials, no preseeded network and no
default password. Debug images are never published.

**I7** The rootfs partition is sized to its contents plus slack, and grows to
fill the card on first boot.

**I8** First boot creates the user, and does not ship the default `123456`
password of the DanctNIX image.

**I9** `scripts/patch-image.sh` is deleted once I6 holds. Preseeding belongs in
the builder; editing someone else's ext4 with `debugfs` is only worth doing
while the image is not ours.

---

## 8. Version pins and reproducibility

**V1** `manifest.toml` names, for every input this project does not itself
version: the upstream repo and the exact tag or commit built. It is the only
place a version is written.

**V2** No build step clones at `HEAD`.

> This is broken today and it is the cheapest thing on this list to fix.
> `docker/build-packages.sh` clones the keyboard and all five AUR packages with
> `--depth 1` — no ref. Two builds a week apart produce different images and
> nothing records why. Until this holds, "reproducible image" is not a claim
> that can be made, so V1–V2 come before any of §6 or §7.

**V3** The upstream Omarchy pin moves out of `install/vendor-omarchy.sh` into
`manifest.toml` alongside the rest.

**V4** A published image records the exact version of every package in it, in a
manifest inside the image and next to it on the download.

**V5** Bumping a pin in `manifest.toml` and rebuilding is the only supported way
to change what an image contains.

---

## 9. The dev loop

**D1** `scripts/provision.sh` survives. Rebuilding a 3 GB image to test a
one-line QML change is not a development cycle.

**D2** It installs the *same packages the image ships*, from the same repo —
never a tarball of the working tree (`provision.sh:101`) that puts files on the
phone that no package owns.

**D3** There is a documented way to install a locally built, unpublished package
over the top for iteration, and a way to tell from the phone that this has
happened.

**D4** `scripts/flash-sd.sh` keeps working, on our own images as well as
DanctNIX's.

---

## 10. Naming

**N1** The project uses one prefix: **`moarchy`**. Settled 2026-09-05. Until
then this repo, its 22 `bin/mobileomarchy-*` scripts, its nine plugin ids and
both `.packages` files said `mobileomarchy`, while the keyboard and the store —
the two repos with an audience — were already published as `moarchy-*`.

**N2** The alternative was renaming those two into `mobileomarchy`. `moarchy`
won because it was already on the published repos, and because
`moarchy-keyboard` reads as part of a family in a way `mobileomarchy-keyboard`
does not.

**N3** It was decided before the first published package, which is the whole
reason it was cheap. A package name is the one thing here that is genuinely
expensive to change afterwards — it is in every `depends`, every `pacman.conf`
and on every phone. Nothing had been published, so the bill was 417 lines
across 80 files, 35 renamed paths, and a one-release migration in
`install/config.sh` for phones already carrying the old name. After M3 it would
have been that plus every installed device.

---

## 11. Sequencing

Four milestones. Each is independently useful; each is a prerequisite for the
next.

**M1 — Pins.** V1–V3. No new infrastructure, no restructuring; a manifest file
and six clone commands that take a ref. After this, two builds of the same
manifest agree.

**M2 — One transaction.** P1–P10. `install.sh` reduces to:

```
pacman -S moarchy-meta
```

**This is the gate.** Everything in §6 and §7 is downstream of it and none of it
is possible before it. The reason is worth stating plainly: an installer that is
one pacman transaction runs identically in a chroot, and a chroot is what an
image build is. The work of M2 *is* the work of making an image buildable — §7
is then mostly partition arithmetic.

**M3 — The repo.** R1–R7. Publishes what M2 defined.

**M4 — The image.** I1–I9. Consumes what M3 published.

Naming (§10) was not a milestone. It happened before M3 — 2026-09-05, ahead of
M1 — which is the only reason it cost 80 files rather than every phone.

---

## 12. Open questions

Marked **?** above, collected here:

1. **I3 — the boot chain.** Whether DanctNIX's boot partition and pre-GPT region
   can be assembled from their packages, or have to be copied verbatim out of a
   release image. Unverified; changes the shape of `image/` but not this plan.
2. **Where `moarchy.db` is hosted.** GitHub Pages off this repo is the cheap
   answer and needs no domain. A `pkgs.moarchy.org` mirrors what upstream
   Omarchy does and survives moving off GitHub. Not decided.
3. **Whether `omarchy-config` should be a package at all**, versus vendoring the
   ~95 QML files of upstream's shell directly into this repo with the port
   already applied. The package keeps the upstream diff visible and the update
   path mechanical; vendoring is simpler and admits that a Sway port of a
   Hyprland shell is a fork whether or not we call it one. The patch in P4 is
   the thing that decides this — if it grows past a few hundred lines, it is a
   fork, and pretending otherwise costs more than it saves.
