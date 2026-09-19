# Project structure — specification

How the three repos, the packages, the package repository and the image builder
fit together, and what has to be true before an image can be built at all.

Status: **M1, M2, M3 and M4 done.** The image boots on a real phone and
`pacman -Syu` updates it without reflashing. The
acceptance criteria are the contract to argue with before any of them is; where
one is my reading rather than your decision it is marked **?**. Each AC below
carries its state, and §11 has the per-milestone summary.

The archaeology of how we got here lives in [build-log.md](build-log.md). This
file is the destination.

---

## 1. What this decides

*Written before M1. The present tense in this section is the starting point it
argues against, not the shape of the project today — `install.sh` and
`install/` were deleted with M2 (P9), and §11 records what replaced them.*

Then, the project was a config overlay with an on-device installer. `install.sh`
sourced eight scripts that cloned upstream Omarchy at a pinned SHA, mechanically
rewrote five QML files, built Go programs, and wrote `~/.config` — all on the
phone, at install time, over SSH.

That shape cannot produce an image. An image build has no phone, no SSH, no
network guarantees and no user session. Everything the installer does at run
time has to happen at *build* time instead, and the only mechanism Arch has for
"work done at build time, replayed identically later" is a package.

So the structural question is not "how do we arrange the repos". It is **"what
is a package, and where do packages come from"**, and the repo layout falls out
of the answer.

### 1.1 The deliverable is not an ISO

A phone has no BIOS, no UEFI and no El Torito. On the devices this project
targets (`devices.md` D0) the bootloader is Android's: it takes a `boot.img`
over fastboot, checks it against AVB, and boots the slot it was told to.

So the artifact is a **directory**, not a disk image (`devices.md` D10):

| | |
| --- | --- |
| `boot.img` | Android v0 header + gzipped kernel with the DTB appended |
| `vbmeta.img` | AVB header with verification disabled, or the bootloader refuses the kernel |
| `rootfs.simg` | ext4 as an Android *sparse* image — fastboot cannot flash a raw one over 4 GiB |
| `flash.sh` | the three `fastboot flash` calls and the `--set-active` that clears the A/B retry counter |

shipped as `moarchy-<device>-<version>-<date>.tar.xz`. Wherever this document
says "image", that is what it means.

> *Amended 2026-09-19.* It used to be a GPT disk image written with `dd`,
> because the first device booted by having the Allwinner A64 BROM read u-boot
> SPL from raw sectors at byte 131072. That is now the carve-out that does not
> exist, and D0 says a change which makes it the default shape of anything is
> wrong.

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

**B6** `moarchy-apps` is absorbed. Its 18 `org.moarchy.*` plugins live in
`default/omarchy/plugins/` beside the shell's own, `qml-apps/` and
`scripts/sync-qml-apps.sh` are deleted, and no PKGBUILD builds from a snapshot
of another repo's working tree. It is the exception B2 never covered: six of
those plugins are uncommitted upstream, which is why `moarchy-qml-apps` carries
"when those plugins are tagged, this package should grow a proper source" — and
why the pin B1 relies on could never be taken.
→ `test ! -e qml-apps && test ! -e scripts/sync-qml-apps.sh`, and
`ls default/omarchy/plugins | wc -l` == 32, of which 31 carry a `manifest.json`

**B7** There is exactly one editable copy of each app. `moarchy-apps` stops
being a source: it keeps only what this repo does not take — its tests,
`ui.catalog`, `install-on-device.sh` — or it is archived. **?** Which of the two
is yours to decide; the criterion is that no file is editable in both places,
because the snapshot's own README had to warn that "a change made to this
snapshot is undone by the next sync".
→ `grep -rn "moarchy-apps" --exclude-dir=.git .` matches prose only: no path,
no clone, no `source=`

**B8** Whatever `moarchy-apps` ran against those plugins runs here, or §12 says
it does not. The sync deliberately left tests, screenshots and the device
installer behind, so absorbing the plugins without them loses checks that
currently exist.
→ `scripts/` names the app test runner, or §12 carries the entry

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
│   ├── moarchy/               bin/ default/ config/
│   ├── omarchy-config/        upstream pin + port-4x.patch
│   ├── moarchy-meta/          the package list, as depends=()
│   └── moarchy-keyring/       the repo signing key (R5)
├── docker/                build container; the AUR rebuilds are cloned at the
│                          [aur.*] pins rather than kept as PKGBUILDs here
├── repo/                  repo-add → moarchy.db → publish
├── image/                 pacstrap a rootfs + boot chain → a flashable artifact
├── bin/ default/ config/  packaged by pkgbuilds/moarchy
├── scripts/               dev loop: provision.sh, build-image.sh
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
and theme layer at the pin in `manifest.toml`'s `[omarchy]` (`c668141`, v4.0.4 —
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
the AUR rebuilds, `moarchy`, `omarchy-config`, `moarchy-meta` and
`moarchy-keyring` (R5). Eleven today.

**R3** Packages are built in an `aarch64` container, natively on Apple Silicon —
the existing `docker/Dockerfile.builder`, generalised from a fixed list to
`manifest.toml`.

**R4** Adding the repo to a stock DanctNIX phone is one `pacman.conf` stanza,
and `pacman -S moarchy-meta` then installs the whole environment.

**R5** The repo database is signed, and the public key ships in a
`moarchy-keyring` package. `SigLevel = Required` in the stanza from R4.

**R6** Republishing is idempotent: running the build twice with an unchanged
`manifest.toml` produces the same package versions and does not bump `pkgrel`.

**R6a** A published repository contains **only** what its database names. Assets
that are no longer part of it are removed on publish. **Met 2026-09-07:**
`repo/publish.sh` prunes what is absent from `repo/dist`; `PRUNE=0` opts out.

> `gh release upload --clobber` replaces a file of the same name and does
> nothing about one with no counterpart, so the tag accumulated:
> `moarchy-store-git` r19 beside r22, and `moarchy` 0.1.0-1 and -2 both
> outliving the database that named them. `repo/build.sh` already rebuilds the
> database from scratch so a phone is never offered a version whose file is
> gone; this is the other half of that bargain.

**R7** The repo is how packages reach a phone in the field. **Met 2026-09-06,
with the dev loop as the stated exception:** `pacman -Syu` from `[moarchy]` is
the supported path, and nothing on the phone is a file no package owns — which
is the half that mattered. `scripts/provision.sh deploy` still `scp`s
`packages/*.pkg.tar.*` and installs them with `pacman -U`, on purpose: that is
D3, iterating on a build that has not been published, and it ships *packages*
rather than the tarball of the working tree it used to (D2). Publishing to test
a one-line QML change is not a development cycle.

**R8** The directory a release or an image is built from holds **one version of
each package**, and a build that finds two refuses rather than choosing.
**Met 2026-09-07:** `scripts/pkgset.sh`, called by `repo/build.sh` and
`image/build.sh`, which also print the set by name rather than by count.

> `docker/build-packages.sh` never clears its output, which is right — a build
> that fails halfway should not cost the packages that already built. The
> consequence is that a pkgrel bump or a moved pin leaves yesterday's file
> beside today's, and `repo-add ... *.pkg.tar.*` then takes whichever the glob
> puts last. It has happened twice: the published `repo` release carries
> `moarchy-store-git` r19 *and* r22, and `PKGDIR` exists because a
> `moarchy-0.1.0-2` from another session's work in progress was one glob away
> from being released.

**R8a** *Decided 2026-09-07: deliberately not done for 0.1.x.* The image's
`/etc/pacman.conf` carries `[moarchy]`, `[moarchy-apps]` since 2026-09-13
(R8c), and nothing else beyond what the `pacman` package ships. Stock Arch Linux ARM's copy is
`core`/`extra`/`alarm`/`aur`; `[danctnix]` is added by DanctNIX's own image
build and by `image/Dockerfile` for the *builder*, not by any package, so a
flashed phone never gets it.

> Nothing breaks. `pacman -Syu` works and updates the phone UI, which is what
> R4 promised.
>
> *Amended 2026-09-19.* It used to say the device stack could not move either,
> because the kernel, u-boot, modem daemon and camera app all came from a repo
> the phone is not configured for. That stopped being true when the device
> became an Android handset: `linux-moarchy-sdm670`, `firmware-moarchy-sargo`,
> `moarchy-qcom-modem`, `q6voiced`, `qbootctl`, `bootmac` and `megapixels` are
> all **ours**, published in `[moarchy]`, so `pacman -Syu` moves the whole
> device stack including the kernel — which is a larger promise than R4 made
> and is the open question §10 raises about publishing kernels at all.
>
> What is still frozen is what `[danctnix]` alone carries: `libdng` and
> `libmegapixels`, which `megapixels` links against and Arch Linux ARM does
> not have. `pacman -Qm` lists those two as foreign.
>
> Six lines in `image/configure.sh` beside the `[moarchy]` block would fix it,
> and `danctnix-keyring` is already pacstrapped so `SigLevel = Required` would
> work. Deliberately not done for 0.1.x: nobody has watched a DanctNIX kernel
> or u-boot upgrade land on a moarchy image, and the failure mode of getting
> that wrong is a reflash on a device whose only other way in is the card.
> Decided 2026-09-07.

**R8b** A package build reports **skipped** and **failed** as different things,
and every package in the output directory is one that build vouches for.
**Met 2026-09-07:** `docker/build-packages.sh` writes
`packages/.build-manifest` — a sha256 per file plus the commit — and
`pkgset_vouched` refuses a stray or a file whose bytes have changed under a
stable name.

> R8 catches two versions of one name. It cannot catch a *lone* leftover, and
> that is the one that shipped: `packages/` held `moarchy-store-git` r19 while
> `manifest.toml` pinned r22, with no duplicate to notice it against. The hash
> is the other half — three separate times in one day a filename outlived its
> contents: `moarchy-meta 0.1.0-1` existed as two different packages, seven
> cached `.pkg.tar.xz` files did, and so did the published `v0.1.0` image
> (`03f64c75` released, `5b6aa24c` locally under the same name).
>
> The skipped/failed split is the same lesson at the other end. `makepkg`
> refuses to overwrite an existing artifact, and that refusal was recorded as a
> build failure — so a rebuild into a populated directory ended with `FAILED:
> moarchy-keyboard …` and "the phone has no on-screen keyboard" about a package
> that was sitting right there. A build's loudest line being routinely wrong
> teaches you to skip it.

**R8c** *Done 2026-09-13.* `[moarchy-apps]` is the second stanza, and it is a
different decision from R8a rather than the same one revisited. R8a is about
somebody else's repo moving the device stack under us; this is our own repo,
signed by our own key -- the same key, in fact, so `moarchy-keyring` already
trusts it and nothing was added to the keyring.

> It had to happen because the store made it load-bearing. moarchy-store's
> catalogue lists ten packages that live only in `[moarchy-apps]`, and its
> helper installs by execing `pacman -S` against a name in a sync database. No
> stanza, no sync database, no Install button -- so every one of those rows was
> dead on a freshly flashed phone while working perfectly on the developer's
> own handset, which had the stanza added to it by hand one afternoon and never
> written down.
>
> `image/configure.sh` no longer reads one hardcoded `[repo]`: it loops over
> every manifest section that names a `server`, and `image/verify.sh` checks
> the stanza and the cached `.db.sig` for each of them rather than for
> `moarchy.db` alone. A third repo is now a manifest edit. Verified the way the
> claim is worth making: a clean Arch ARM container carrying exactly the two
> stanzas this writes, trusting nothing but the key fetched from the published
> URL, syncs both databases and installs `moarchy-chess` with `Validated By :
> Signature`.

**R9** A published image's own pacman keyring **trusts** the signing key, rather
than merely carrying the file. **Met 2026-09-07:** `image/verify.sh` asks
`pacman-key --gpgdir` and tells apart trusted, present-but-untrusted, and
absent.

> `moarchy-keyring`'s `post_install` runs `pacman-key --populate` and swallows
> its own failure into a stderr line that `pacstrap`'s output buries. If that
> ever silently fails, `SigLevel = Required` refuses every package in R1's repo
> and the phone's only symptom is that `pacman -Syu` stops — which is the exact
> thing R4 exists to make possible. Checking that the *file* is in
> `/usr/share/pacman/keyrings` cannot see it: pacman validates against
> `/etc/pacman.d/gnupg`, and nothing imports into that on its own.

---

## 7. The image

**I1** *Amended 2026-09-19.* `image/` produces
`moarchy-<device>-<version>-<date>/` — a **directory** of `boot.img`,
`rootfs.simg`, `vbmeta.img` and `flash.sh`, plus a `.sha256`, a `.build-info`
and a `.packages` manifest beside it (V4) — from a single command, with no
phone attached. **Met:** `./scripts/build-image.sh`; 0.5.0 is **1,334.5 MiB**
as the `.tar.xz` that ships.

> The measurement used to be of a `.img.xz` for a different device, and the
> numbers are not comparable, so they are not carried across. The version is in
> the directory name because several of them sit in `images/` at once.
>
> The `.packages` manifest was written by the `sunxi-gpt` backend and by
> nothing else, so **every sargo image ever built shipped without one** and V4
> was quietly met on one device only. It moved into `image/build.sh` beside the
> provenance block on 2026-09-19, where it belongs: what pacstrap installed is
> a fact about the rootfs and has nothing to do with how the thing boots.

**I2** The rootfs is built by `pacstrap`-ing into a directory: a base list that
names no hardware, `moarchy-device-<codename>`, and `moarchy-meta` from the
`moarchy` repo. It is never produced by booting a phone and imaging the
storage back.

> *Amended 2026-09-19.* The base used to be another distribution's own
> explicitly-installed list, read out of `/var/lib/pacman/local` in their
> release image, because their meta package pulled a whole device stack and
> hand-picking it had already lost the wifi once. That stopped being true when
> the device stack became ours: the kernel, the firmware and the modem daemons
> are `moarchy-device-<codename>`'s `depends` now (`devices.md` D2), so the
> list here is the *general* phone — an init, a network stack, an audio stack,
> and the filesystem tools — and the hardware is named exactly once.
>
> The repo is a local `file://` one built with `repo-add`, not a published
> HTTP one — which is the only reason §7 could be done before §6. `pacstrap`
> does not care which it is.

**I3** *Amended 2026-09-19.* The boot chain is **assembled from packages**, and
on an Android handset there is no bootloader in it at all: the vendor's `xbl`
and `abl` stay where they are, and what this project produces is a `boot.img`
carrying our kernel with its DTB appended, plus a `vbmeta.img` that disables
verification. `linux-moarchy-<soc>` is ours and pinned (`devices.md` D13);
nothing is copied verbatim out of somebody else's image.

> The original I3 was about reusing another distribution's u-boot SPL, FAT
> `boot` partition, kernel and DTB, and it resolved on 2026-09-06. Kept as an
> amendment rather than deleted because the *property* it asserts — the boot
> chain comes from packages, not from a donor image — is the one that still
> has to hold, and it is the reason `image/boot/android-image.py` reproduces
> postmarketOS's boot image byte-for-byte instead of shipping theirs.

**I4** The image boots to a session on a real phone with no SSH step in
between. This is the acceptance test for the whole document. **MET 2026-09-15**
on the Pixel 3a (`docs/devices.md` §9 item 7): flashed over fastboot from a
clean rootfs, the panel lit, tty1 autologin worked, the theme applied, the
compositor started and the shell came up.

> The two defects the *first* such boot found were both composition bugs, where
> every individual piece was present, correct and verified:
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

**I5** *Amended 2026-09-19.* **No USB network gadget is raised at all.** Access
to a running phone is over wifi.

> This used to say the gadget was left as the base image shipped it, which was
> a statement about a package (`danctnix-usb-tethering`) that left with the
> device that depended on it. Nothing raises a gadget on sargo today.
>
> If one is ever added, `devices.md` **D19** already decides its shape: CDC-ECM
> or NCM, never RNDIS, because macOS binds no driver to RNDIS and a debug
> network the only machine on the desk cannot speak to is not a debug network.
> The pinned kernel config has `USB_CONFIGFS_ECM=y` and `USB_CONFIGFS_NCM=y`,
> so it costs nothing but choosing correctly.

**I6** The builder can produce a **debug image** with wifi credentials
preseeded, so a freshly flashed card joins the network on first boot with no
keyboard. The PSK comes from the environment, never a flag or a checked-in file.

**I6a** A published image carries no credentials, no preseeded network and no
default password. Debug images are never published.

**I7** The rootfs is sized to its contents plus slack, and grows to fill the
partition it was flashed to on first boot. **Met:**
`moarchy-grow-rootfs.service` runs before `systemd-user-sessions`, calls
`resize2fs`, and stamps `/var/lib/moarchy/grown`.

> Only the filesystem grows. The partition is `userdata`, sized by the vendor
> and sitting in a GPT beside `xbl`, `abl`, `tz` and the A/B slots — running
> `sfdisk` there would rewrite a vendor partition table on a phone with no
> recovery image, which is the one irreversible thing this project could do to
> a device (`devices.md` D22). The partition-growing branch existed for a
> device whose image was written to a card of unknown size and went with it.

> The size is sensitive to one thing that is easy to miss: `pacstrap` leaves
> every downloaded package in `/var/cache/pacman/pkg`, 1.26 GiB of it, and
> sizing the partition before clearing it puts that straight into the download.

**I8** First boot creates the user and ships no default password. **Met, by
there being no password at all:** the account is created at build time with a
*locked* password, and root is locked too.

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

**I10** The image carries a time source. **Met:** `systemd-timesyncd` is
enabled, and `/var/lib/systemd/timesync/clock` is seeded at build time so the
clock has a floor before the network is up.

> Found the hard way on a freshly flashed 0.1.1 card: installing anything failed
> with `x509: certificate has expired or is not yet valid`. Nothing was wrong
> with the package repository or the release — the phone's clock was.
>
> Arch enables no NTP client by default, and this systemd ships no
> `/usr/lib/clock-epoch`, so nothing at all held the clock up except the PMIC
> RTC, which reads back nonsense once the battery has been off. A clock far
> enough out fails certificate validation on every TLS handshake, so `pacman`,
> `yay` and the store all stop working at once — and each blames its own
> endpoint, which is what makes it look like a server-side problem.
>
> NTP rather than a baked-in date, because it corrects the clock in both
> directions: a stale RTC reads into the past, a garbage one into the future,
> and either one breaks TLS.

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
> measurable rather than theoretical — see Q4 in §12. **?**

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

**D4** *Annulled 2026-09-19.* It required `scripts/flash-sd.sh` to keep
working on our own images as well as the base image it was written for. Both
the script and the device that needed it are gone; the artifact carries its own
`flash.sh` (D10) and `scripts/provision.sh flash` prints it.

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

**N4** One plugin id namespace: **`moarchy.<name>`**, for all 31 plugins. The
18 `org.moarchy.*` ids are renamed with B6. The id shares one registry keyspace
with upstream's 37 first-party plugins — `omarchy.bar`, `omarchy.media`,
`omarchy.workspaces` — every one of which is bare `<vendor>.<name>`, so
reverse-DNS there is a convention nothing else in the map follows.
→ every `default/omarchy/plugins/*/manifest.json` has an `id` matching
`^moarchy\.[a-z][a-z0-9-]*$`

**N5** Reverse-DNS stays where the namespace is system-wide. A `.desktop` file
lands in `/usr/share/applications` alongside every other application on the
machine, and its `Icon=` resolves in a shared theme, so both keep the
`org.moarchy.<Name>` form; only `Exec=` and `X-Moarchy-Plugin=` carry the
plugin id. This is not an inconsistency with N4 — it is two namespaces with
different collision risks, each following its own convention.
→ every installed desktop entry naming moarchy begins `org.moarchy.`;
`moarchy.device.desktop` and `moarchy.sim.desktop`, which break this today, are
renamed with the rest

**N6** A plugin's directory name is its id. The registry keys on the manifest's
`id` and treats the directory only as the source path for `entryPoints`, so the
two *may* diverge; they do not, so that a path in this repo, a path on the
phone and a string in `shell.json` are one string.
→ for each `default/omarchy/plugins/*/manifest.json`, the parent directory's
name equals its `.id`

**N7** The trust boundary narrows to the one namespace. `pluginIsTrusted` in
`port-4x.patch` returns true for `moarchy.` alone, and its comment is rewritten
rather than left describing two prefixes.
→ no `org.moarchy` in that function or its comment — **and**
`pkgbuilds/omarchy-config/PKGBUILD` carries both a regenerated `sha256sums` for
the patch and a bumped `pkgrel`. Either alone masks the other, and that pair has
shipped broken twice.

**N8** Nothing is migrated. Existing phones are reflashed, not upgraded through
the rename, so `~/.config/omarchy/shell.json` on a device already in the field
may name ids that no longer exist. Decided 2026-09-19.
→ no migration step in `bin/moarchy-user-setup`, and no rename table anywhere
in `bin/`

---

## 11. Sequencing

Five milestones. Each is independently useful; each is a prerequisite for the
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
> lines.
>
> That scan is `scan_thirdparty`, and from Omarchy v4.0.3 the word carries
> weight: 4.0.3 sandboxes installed third-party plugins behind a
> capability-scoped `PluginShellApi` with no `panelLoaders`, no `openPanelIds`
> and no cross-plugin `summon`. Our phone UI is third-party only in that
> bookkeeping sense — it *is* the shell — so the patch grew a second hunk,
> `pluginIsTrusted()` in `shell.qml`, returning the host shell for the
> `moarchy.` namespace at the three injection points. Marking our directory
> first-party instead would have been one word, and would have cost the
> override: `PluginRegistry` refuses a third-party id that collides with a
> first-party one, so a `~/.config` copy of `moarchy.shade` would stop loading
> and the on-device iteration loop with it. Genuinely foreign plugins stay
> scoped, which is a protection 4.0.2 did not offer at all. The stale-plugin sweep in `install/config.sh` — and
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
> **Some packages are not from Arch Linux ARM.** They come from `[danctnix]`
> (`archmobile.mirror.danctnix.org`), not `archlinuxarm.org` as
> `moarchy-base.packages` claimed at the top of the file for every entry. Found
> by `pacman -U --print` failing to resolve in a bare ALARM container, and
> settled by reading `/etc/pacman.conf` out of the shipped image rather than
> guessing repo URLs.
>
> It was three — `lisgd`, `mmsd-tng` and `portfolio-file-manager` — and is now
> `libdng` and `libmegapixels`, underneath `megapixels`. The finding stands as
> written: the repo is still needed, for fewer things each time.
>
> Verified in the container: the whole set resolves as **one transaction of 564
> packages**; `omarchy-config` and `moarchy` install together with no file
> conflict; `pacman -Ql` shows no path under `/home` for either; the plugin
> directories land in `/usr/share/moarchy/plugins` and the patched registry
> scans it; the packaged `shell.json` carries `bar.id = moarchy.bar`, the
> `moarchy.*` plugin list and the `HH:mm` clock; and every absolute `include` in
> the sway config points at a file that exists.
>
> The counts in that sentence were nine directories and eight plugins when it
> was written, grew to eleven and ten as `moarchy.wifi`, `moarchy.bluetooth` and
> `moarchy.splash` arrived, and are ten and nine today — `moarchy.recents` was
> deleted on 2026-09-13 when the drawer took over showing what is open
> (`gestures.md` M). They are deliberately no longer written down here: `default/omarchy/plugins/` and `port-4x.patch`'s `plugins[]` are
> the two places that answer it, and a third copy is the divergence P5 exists to
> prevent.

> **The collision the old installer hid.** `moarchy` ships 21 scripts whose
> names upstream Omarchy also uses — `omarchy-toggle-nightlight`,
> `omarchy-system-lock`, `omarchy-launch-browser` and the rest. On the phone they
> won by PATH order, because both were checkouts in `$HOME`. As packages they
> cannot both own `/usr/bin/omarchy-toggle-nightlight`, and pacman refuses the
> transaction. (22 until 2026-09-08: `omarchy-toggle-bar` went with the bar's
> Show switch, docs/settings.md C4a. The number is `ls bin/omarchy-*` against
> upstream's `/usr/bin`, not a constant anything checks.)
>
> So upstream's `bin/` goes to `/usr/bin`, where its own package puts it and
> where its `sudoers.d` entries name it by absolute path, and ours goes to
> `/usr/lib/moarchy/bin` with `/etc/profile.d/zz-moarchy.sh` putting that
> ahead of it. The shadowing is unchanged; only where it is written down is.
> Verified by installing both packages together and asking a login shell:
> `omarchy-toggle-nightlight` resolves to ours, `omarchy-theme-set` to
> upstream's.
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

**M5 — One tree. Not started.** B6–B8, N4–N8, and `refactor.md` E10–E11. The
two source trees become one, the id namespace becomes one, and the kit that
exists twice becomes one. Nothing here is user-visible: the phone comes up with
the same 31 plugins drawing the same surfaces, which is exactly what makes it
checkable.
→ the shell loads 31 plugins, `bin/moarchy-selftest --surfaces` passes, and the
drawer lists the same entries it lists today

> Sequenced after M4 and not before it because it moves every install path at
> once. The order within it matters: B6 first (one tree), then E10 (one kit,
> which B6 is what makes possible), then N4–N7 (one namespace). Doing the
> namespace first would rename 18 ids in a tree that is about to move, and
> `git log -S` would lose both.

Naming (§10) was not a milestone. It happened before M3 — 2026-09-05, ahead of
M1 — which is the only reason it cost 80 files rather than every phone.

---

## 12. Open questions

The questions this document opened, with what has since answered them. Two are
closed; the three that are still open are the ones to read.

1. ~~**I3 — the boot chain.**~~ **Answered 2026-09-06.** Everything the boot
   chain needs is in `uboot-pinephone`, `linux-megi`, `uboot-tools` and
   mkinitcpio, and the SPL assembled from packages is a byte-exact match for the
   one on the release image. Nothing is copied verbatim. See I3.
2. ~~**Where `moarchy.db` is hosted.**~~ **Decided 2026-09-06: GitHub
   Releases**, under a fixed `repo` tag whose assets are replaced in place so
   the `Server` URL never moves; the URL and the key are `[repo]` in
   `manifest.toml`. Pages was the cheap answer and was rejected because it
   serves from a branch — every publish would commit ~120 MB of binaries to git
   history, permanently, for everyone who clones. See M3.
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

   **Measured 2026-09-07: 9 files, 230 insertions, 30 deletions.** So the
   package stays, on the test this question set itself. Worth re-measuring on
   every upstream bump; the number to watch is this one. Reproduce it with
   `git diff --stat` against a clean v4.0.4 checkout, or count `+`/`-` lines in
   `pkgbuilds/omarchy-config/port-4x.patch`.
