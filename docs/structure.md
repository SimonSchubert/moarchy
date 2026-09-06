# Project structure — specification

How the three repos, the packages, the package repository and the image builder
fit together, and what has to be true before a PinePhone image can be built at
all.

Status: **M1, M2, M3 and M4 done (2026-09-06).** The image boots on a real
PinePhone and `pacman -Syu` updates it without reflashing. The
acceptance criteria are the contract to argue with before any of them is; where
one is my reading rather than your decision it is marked **?**. Each AC below
carries its state, and §11 has the per-milestone summary.

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
> without dragging in the source. `docker/build-packages.sh` already clones the
> keyboard from GitHub rather than vendoring it; this makes that deliberate
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
and theme layer at the pin in `manifest.toml`'s `[omarchy]` (`346e69e`, v4.0.2 —
it lived in `install/vendor-omarchy.sh` until V3), installed to the path
upstream hardcodes.

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
from a single command, with no phone attached. **Met 2026-09-06:**
`./scripts/build-image.sh` → **1.2 GB compressed**, 747 packages, and a
`.packages` manifest beside it (V4).

**I2** The rootfs is built by `pacstrap`-ing into a directory: DanctNIX's base
plus `moarchy-meta` from the `moarchy` repo. It is never produced by
booting a phone and imaging the card back.

> The base set is DanctNIX's own explicitly-installed list, read out of
> `/var/lib/pacman/local` in their release image, rather than a reading of what
> the device needs. Hand-picking it was tried and was wrong: `linux-megi
> uboot-pinephone danctnix-tweaks` looks like the device stack and leaves out
> `linux-firmware-realtek`, which is the wifi. `device-pine64-pinephone` is
> their meta package and pulls all of it, so a device fix from them arrives
> without an edit here.
>
> The repo is a local `file://` one built with `repo-add`, not a published
> HTTP one — which is the only reason §7 could be done before §6. `pacstrap`
> does not care which it is.

**I3** The boot chain — u-boot SPL at 128 KiB, the FAT `boot` partition, the
kernel and DTB — is reused from DanctNIX's packages, not rebuilt. **Resolved
2026-09-06: assemblable from packages; nothing has to be copied verbatim.**

> Measured against the cached `archlinux-pinephone-barebone-20251224.img`:
>
> | | |
> | --- | --- |
> | `uboot-pinephone` 2024.01-1 | `/boot/u-boot-sunxi-with-spl-pinephone-{492,528,552,624}.bin`, `boot.txt`, `mkscr`, and `/usr/bin/update-u-boot` |
> | `linux-megi` 6.15.6-2 | `/boot/Image.gz` and the DTBs |
> | `uboot-tools` | `mkimage`, which `mkscr` turns `boot.txt` into `boot.scr` with |
> | mkinitcpio | `initramfs-linux.img`, from the preset `linux-megi` ships |
>
> The SPL on the shipped image is a **byte-exact match** for the `528` variant —
> `update-u-boot`'s `default_freq` — written at byte 131072, which is its
> `bs=128k seek=1` for a GPT disk (`bs=8k seek=1` is the DOS-label path, and is
> why the magic is not at 8 KiB).
>
> `boot.txt` also settles a question §7 would otherwise have had to: it selects
> the root device at boot with `root=/dev/mmcblk${linux_mmcdev}p${rootpart}`
> and `rootwait`, choosing partition 2 when one exists, and handles SD vs eMMC
> itself. So the image needs no UUID rewriting and no per-device boot script.

**I4** The image boots to a Sway session on a real PinePhone with no SSH step in
between. This is the acceptance test for the whole document. **MET 2026-09-06.**

> Flash, insert, power on. The A64 BROM accepted the SPL, megi's kernel booted,
> the panel lit, `moarchy-firstboot` completed, tty1 autologin worked, the theme
> applied, sway started, and the rootfs grew to fill a 64 GB card — partition 2
> came back 63.7 GB with our `BOOT` label on partition 1, so I7 is confirmed on
> the device and not only against a loop file.
>
> **Both defects it found were composition bugs**, where every individual piece
> was present, correct and verified:
>
> 1. `moarchy-firstboot` wrote the autologin drop-in but raced `getty@tty1`, so
>    the first boot stopped at a login prompt that a *locked password cannot
>    answer*. The image build knows the username, so the drop-in is written at
>    build time now.
> 2. `/etc/profile` sources `profile.d` in sorted order, and
>    `zz-moarchy-session.sh` sorts before `zz-moarchy.sh` — `-` is 0x2D, `.` is
>    0x2E. The session `exec`'d sway before the file that puts
>    `/usr/lib/moarchy/bin` on `PATH` ever ran, so `swaybg` painted the wallpaper
>    and `moarchy-restart-shell` was simply not found: no bar, no gesture strip,
>    and no log, because the missing script is the one that writes the log. They
>    are one file now.
>
> Neither was reachable by checking files in isolation, which is the lesson. The
> suite now checks the image *as shipped* rather than after running first-boot,
> and simulates a tty1 login with `sway` replaced by a stub that reports the
> environment it was handed. Both checks fail on the images that failed.
>
> `/var/log/journal` exists now too. It did not, so the first failure left
> nothing to read and the card had to come out and be read on the Mac with
> `debugfs` to find a two-character sort-order bug.

**I5** The USB gadget is left as DanctNIX ships it. Access to a running phone is
over wifi. **Met:** `danctnix-usb-tethering` is installed unmodified.

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
fill the card on first boot. **Met:** `moarchy-grow-rootfs.service` runs before
`systemd-user-sessions`, grows the last partition with `sfdisk` and follows it
with `resize2fs`, then stamps `/var/lib/moarchy/grown`.

> The size is sensitive to one thing that is easy to miss: `pacstrap` leaves
> every downloaded package in `/var/cache/pacman/pkg`, 1.26 GiB of it, and
> sizing the partition before clearing it puts that straight into the download.

**I8** First boot creates the user, and does not ship the default `123456`
password of the DanctNIX image. **Met, by there being no password at all:** the
account is created at build time with a *locked* password, and root is locked
too.

> tty1 autologin does not consult a password, so the phone comes up usable with
> no secret to leak or change; `sshd` is disabled and password authentication
> is off if it is enabled, so a locked password cannot be attacked remotely.
> `sudo` is passwordless for the account, which concedes nothing on a device
> with no disk encryption — anyone holding the phone can read the card. `passwd`
> from the phone's own terminal is how a user opts into SSH.

**I9** `scripts/patch-image.sh` is deleted once I6 holds. Preseeding belongs in
the builder; editing someone else's ext4 with `debugfs` is only worth doing
while the image is not ours. **Met 2026-09-06.**

> `debugfs` earned its keep on the way out, though: reading `/etc/pacman.conf`
> and `/var/lib/pacman/local` straight out of the cached release image is what
> identified the `[danctnix]` repo and the device package set, after three
> guesses at repo URLs returned nothing.

---

## 8. Version pins and reproducibility

**V1** `manifest.toml` names, for every input this project does not itself
version: the upstream repo and the exact tag or commit built. It is the only
place a version is written. **Met 2026-09-06.**

**V2** No build step clones at `HEAD`. **Met 2026-09-06.**

> This was broken and it was the cheapest thing on this list to fix.
> `docker/build-packages.sh` cloned the keyboard and every AUR package with
> `--depth 1` — no ref. Two builds a week apart produced different images and
> nothing recorded why. Until this held, "reproducible image" was not a claim
> that could be made, so V1–V2 came before any of §6 or §7.
>
> Four things clone now, and each checks out a commit named in `manifest.toml`
> and then asserts `rev-parse HEAD` equals it. Trusting the exit status is not
> enough: a clone that was already on disk at another commit, and a fetch that
> quietly did nothing, both leave a working tree that looks correct.
>
> The builder container was the fifth. `menci/archlinuxarm:base-devel` is a
> floating tag, which is a clone at `HEAD` by another name, so it is pinned by
> digest. `FROM` cannot read a file, so that digest is the one pin written in
> two places — `Dockerfile.builder` and `[builder]` — and both say so.
>
> **What V2 does not yet cover: the toolchain.** The container still runs
> `pacman -Syu`, which installs whatever Arch Linux ARM has today. So the
> *sources* are pinned and the *build environment* is not, and that gap is
> measurable rather than theoretical — see Q3 in §12. **?**

**V3** The upstream Omarchy pin moves out of `install/vendor-omarchy.sh` into
`manifest.toml` alongside the rest. **Met 2026-09-06.**

> `scripts/test-themes.sh` used to recover that pin by `sed`-ing the assignment
> out of the installer, having already once tested a theme set the phone did not
> install. It reads `manifest.toml` now, as the installer does.

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

**M1 — Pins. Done 2026-09-06.** V1–V3. No new infrastructure, no restructuring;
a manifest file and the clone commands taught to take a ref. Two builds of the
same manifest now agree.

> `manifest.toml` and its reader, `scripts/manifest.sh`, are what landed.
> Six consumers read it: the builder container and its `Dockerfile`, the
> on-device fallback build, the Omarchy vendoring step, the SD flasher and the
> provisioner. Nothing else names a version.
>
> The reader dies on a pin it cannot read instead of returning `""`. That is the
> whole point of it: an unread pin that degrades to an empty string is a clone
> at `HEAD` wearing a disguise, and it would have passed every check here.
>
> Two things came out of writing it down that were not in the plan. `cbonsai`
> shipped in `packages/` as a prebuilt tarball with no recipe anywhere — built
> once by hand, never recorded — and is now in the manifest with the rest. And
> the AUR package list existed twice, in the container build and in the
> on-device fallback; both read the `[aur.*]` sections now, which is P5's
> argument arriving three milestones early because the cost of not doing it was
> already visible.

**M2 — One transaction. Done 2026-09-06.** P1–P10. `pkgbuilds/` builds
`omarchy-config`, `moarchy` and `moarchy-meta`; `install.sh`, `install/`, both
`.packages` files and `scripts/test-plugin-sweep.sh` are deleted.

> **Almost nothing is copied into $HOME, which was not the plan.** P8 offered
> two mechanisms — a file under `/etc` or `/usr/share/factory`, or a first-boot
> unit. Reading upstream showed most of the copying was unnecessary: sway takes
> `-c`, `omarchy-theme-set-templates` already globs `$OMARCHY_PATH/default/themed`
> after the user's, and `shell.qml:30` already reads
> `$OMARCHY_PATH/config/omarchy/shell.json` as defaults with the user's file
> overriding. So the bar id, the plugin list and the Sway theme template are
> packaged files, not per-user copies, and an upgrade takes effect because the
> files the shell reads *are* the package's files.
>
> Plugins needed the one addition: `PluginRegistry.pluginsDir` was a single
> hardcoded path, so the patch adds `/usr/share/moarchy/plugins`, scanned
> *before* the user directory so a user copy of the same id still wins. Twelve
> lines. The stale-plugin sweep in `install/config.sh` — and
> `scripts/test-plugin-sweep.sh` with it — is gone: pacman owns the files now,
> so a plugin removed from the repo is removed from the phone by the upgrade.
>
> What genuinely needed a first-boot unit is small: group membership (`input`,
> `feedbackd`), tty1 autologin, and the three app configs — alacritty, foot,
> btop — that only ever read `~/.config`.
>
> **`/etc/sway/config` is owned by the `sway` package**, so moarchy cannot ship
> one. `/etc/profile.d/zz-moarchy-session.sh` names ours with `sway -c` instead.
> Found by pacman refusing the transaction, which is the point of packaging.
>
> **Three packages are not from Arch Linux ARM.** `lisgd`, `mmsd-tng` and
> `portfolio-file-manager` come from `[danctnix]`
> (`archmobile.mirror.danctnix.org`), not `archlinuxarm.org` as
> `moarchy-base.packages` claimed at the top of the file for every entry. Found
> by `pacman -U --print` failing to resolve in a bare ALARM container, and
> settled by reading `/etc/pacman.conf` out of the shipped image rather than
> guessing repo URLs.
>
> Verified in the container: the whole set resolves as **one transaction of 564
> packages**; `omarchy-config` and `moarchy` install together with no file
> conflict; `pacman -Ql` shows no path under `/home` for either; nine plugin
> directories land in `/usr/share/moarchy/plugins` and the patched registry
> scans it; the packaged `shell.json` carries `bar.id = moarchy.bar`, eight
> plugins and the `HH:mm` clock; and every absolute `include` in the sway config
> points at a file that exists.

> **The collision the old installer hid.** `moarchy` ships 19 scripts whose
> names upstream Omarchy also uses — `omarchy-toggle-bar`, `omarchy-system-lock`,
> `omarchy-launch-browser` and the rest. On the phone they won by PATH order,
> because both were checkouts in `$HOME`. As packages they cannot both own
> `/usr/bin/omarchy-toggle-bar`, and pacman refuses the transaction.
>
> So upstream's `bin/` goes to `/usr/bin`, where its own package puts it and
> where its `sudoers.d` entries name it by absolute path, and ours goes to
> `/usr/lib/moarchy/bin` with `/etc/profile.d/zz-moarchy.sh` putting that
> ahead of it. The shadowing is unchanged; only where it is written down is.
> Verified by installing both packages together and asking a login shell:
> `omarchy-toggle-bar` resolves to ours, `omarchy-theme-set` to upstream's.
>
> This also fixes a known-bad entry for free. `omarchy-theme-set-browser-policy`
> failed on every theme change because its `sudoers.d` entry names
> `/usr/bin/...` and we shipped a checkout rather than a package. There is a
> package now.

`install.sh` reduces to:

```
pacman -S moarchy-meta
```

**This is the gate.** Everything in §6 and §7 is downstream of it and none of it
is possible before it. The reason is worth stating plainly: an installer that is
one pacman transaction runs identically in a chroot, and a chroot is what an
image build is. The work of M2 *is* the work of making an image buildable — §7
is then mostly partition arithmetic.

**M3 — The repo. Done 2026-09-06.** R1–R7. Publishes what M2 defined.

> Hosted on **GitHub Releases**, under a fixed `repo` tag whose assets are
> replaced in place so the `Server` URL never changes. Pages was the cheap
> answer §12 named, but it serves from a branch — every publish would commit
> ~120 MB of binaries to git history, permanently, for everyone who clones.
>
> Signed with a dedicated ed25519 key, `3CA83612…`, generated by
> `repo/genkey.sh` and never given a passphrase so `repo/build.sh` can run
> unattended. The private half exists in exactly one place and losing it means
> every phone in the field rejects updates until it is taught a new one.
>
> The database is signed on the **host**, not in the container: gpg 2.4 keeps
> public keys in keyboxd's `pubring.db`, which does not travel by bind-mounting
> `~/.gnupg`, so `repo-add --sign` inside a container reports the key missing
> while the same key signs fine outside. Doing it on the host also keeps the
> private key out of a container entirely.
>
> **Bootstrapping needs the armored key published beside the packages.**
> `moarchy-keyring` is itself signed, so a phone that does not yet trust the key
> cannot install the package that would teach it — `required key missing from
> keyring`. The image sidesteps this by installing the keyring at build time;
> anyone adding the repo by hand imports `moarchy.asc` first.
>
> Verified in a container: the key imports and locally signs, the signed keyring
> installs, `pacman -Sy` accepts the signed database, all four of our packages
> are offered, `pacman -S moarchy-meta` completes under `SigLevel = Required` —
> and a package with one byte flipped is **refused** as `invalid or corrupted`,
> which is the check that makes the rest mean anything.

**M4 — The image. Done 2026-09-06, ahead of M3.** I1–I9, I4 included: it boots.

> The sequencing said M3 first because "M4 consumes what M3 published". A
> *local* `file://` repo built with `repo-add` satisfies that just as well —
> `pacstrap` does not care — so the image did not have to wait for publishing.
> What M3 is still needed for is the other consumer in §3: `pacman -Syu` on a
> phone already in the field.
>
> Six defects were found by building it and then booting it, each of which
> would have shipped:
> a hand-picked device package set that omitted `linux-firmware-realtek` and so
> had **no wifi**; `jack2` silently chosen over `pipewire-jack` by a provider
> prompt with no tty; `OMARCHY_PATH` set but not exported, so the theme never
> generated and the phone would have come up with no colours and no keyboard
> palette; upstream's `install/` excluded from `omarchy-config` while a dozen
> runtime `omarchy-*` scripts source out of it; and then, on the device, the two
> composition bugs in I4 — the autologin race and the `profile.d` sort order.
>
> The split is worth noting. The first four were found by *building*, and a
> container caught them. The last two needed the hardware, and both were cases
> where every file was individually correct.

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
3. **`moarchy-store` cannot be pinned from this side.** Its PKGBUILD builds
   `moarchy-store-git` from `source=("...::git+$url.git")` — a VCS package, so
   makepkg fetches at HEAD however the repo is cloned. `[moarchy-store]` in
   `manifest.toml` therefore pins what we review, not what gets built. The fix
   is `#commit=` in that PKGBUILD's source array, and B2 says the component repo
   owns how it is built — so it belongs there, not in a local edit to someone
   else's recipe. This is the one entry in the package set V2 does not cover.

4. **How to pin the build environment, given that ALARM has no archive.**
   `Dockerfile.builder` pins the base image by digest and then runs
   `pacman -Syu`, which floats. The two builds of `moarchy-keyboard` on
   2026-09-05 measure the cost: same pinned source, same `0.1.0-1`, identical
   file list, and an installed size of 470,286 vs 540,529 bytes seven hours
   apart. Arch proper would be pinned with `archive.archlinux.org`; Arch Linux
   ARM publishes no equivalent (`archive.archlinuxarm.org` does not resolve,
   while the live mirror answers), so the options are a mirror snapshot we host
   ourselves, freezing the whole toolchain into the base image, or accepting
   that the environment floats and saying so on every image. Not decided, and
   it belongs to M3 rather than M1 — the package repo is what would host a
   snapshot.
5. **Whether `omarchy-config` should be a package at all**, versus vendoring the
   ~95 QML files of upstream's shell directly into this repo with the port
   already applied. The package keeps the upstream diff visible and the update
   path mechanical; vendoring is simpler and admits that a Sway port of a
   Hyprland shell is a fork whether or not we call it one. The patch in P4 is
   the thing that decides this — if it grows past a few hundred lines, it is a
   fork, and pretending otherwise costs more than it saves.

   **Measured 2026-09-06: 9 files, 224 insertions, 30 deletions.** So the
   package stays, on the test this question set itself. Worth re-measuring on
   every upstream bump; the number to watch is this one.
