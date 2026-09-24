# Architecture — what the FP4 build is made of

Every layer of the moarchy Fairphone 4 image, and where each piece comes from.
Read the stack bottom to top: silicon at the base, the phone UI at the top.

> A colour-coded graphical version of this is in
> [`architecture.html`](architecture.html) — open it in a browser. This page is
> the same content in text, and is the one to edit; keep the two in step.

The one thing to get straight first: **this is Arch Linux ARM, not
postmarketOS.** The base is `menci/archlinuxarm` plus the DanctNIX mobile repo,
populated by `pacstrap`. postmarketOS is a *donor* of a few pieces, not the OS —
see [§ Where postmarketOS actually fits](#where-postmarketos-actually-fits).

## The stack

```
┌────────────────────────────────────────────────────────────────────┐
│  PHONE SHELL & APPS            the mobile UI — what you touch          │
│  moarchy (Simon Schubert) · Omarchy 4.0.4 (basecamp) · keyboard ·     │
│  store/keep/apps · [moarchy.nfc + Location toggle — built here]        │
├────────────────────────────────────────────────────────────────────┤ ▲ renders on
│  COMPOSITOR & TOOLKIT         Wayland session                          │
│  Hyprland · quickshell · Qt6 / Wayland / PipeWire   (Arch Linux ARM)  │
├────────────────────────────────────────────────────────────────────┤ ▲ runs on
│  BASE OS USERLAND            the distribution — Arch, not pmOS         │
│  Arch Linux ARM (menci/archlinuxarm) · DanctNIX mobile repo ·         │
│  systemd · NetworkManager · ModemManager                              │
├────────────────────────────────────────────────────────────────────┤ ▲ device services & media
│  DEVICE SERVICES             making the phone act like a phone         │
│  qrtr · rmtfs · tqftpserv · qbootctl        (linux-msm / Qualcomm)    │
│  q6voiced · 81voltd · bootmac               (postmarketOS)            │
│  hexagonrpc (sensors) · megapixels (camera) · [libmegapixels fix]     │
├────────────────────────────────────────────────────────────────────┤ ▲ talks to
│  KERNEL                      Linux 7.2, mainline + SoC enablement      │
│  sm6350-mainline/linux · .config from pmaports (postmarketOS) ·       │
│  [aw88264 amp · st21nfcd NFC · mic/call-audio DT — written here]      │
├────────────────────────────────────────────────────────────────────┤ ▲ loads
│  FIRMWARE & SILICON          proprietary blobs on SM7225 (lagoon)     │
│  FP4-firmware (FairBlobs) · pil-squasher · Snapdragon 750G (SM7225)   │
└────────────────────────────────────────────────────────────────────┘
```

Items in `[brackets]` are built or patched in this project.

## Where each piece comes from

| Origin | What it provides | Source |
| --- | --- | --- |
| **Arch Linux ARM** | The actual distribution: base userland, Hyprland, quickshell, Qt6, camera app | `menci/archlinuxarm` + `archmobile.mirror.danctnix.org` |
| **Kernel source** | Mainline Linux with the SM6350 out-of-tree patch set | `github.com/sm6350-mainline/linux` (`v7.2.0-sm6350`) |
| **postmarketOS** | Not the OS here — the kernel `.config` and three modem/call daemons | `gitlab.postmarketos.org` (pmaports, q6voiced, 81voltd, bootmac) |
| **linux-msm** | Qualcomm's upstream Linux team: modem/DSP plumbing every msm phone needs | `github.com/linux-msm` (qrtr, rmtfs, tqftpserv, qbootctl, pil-squasher) |
| **Omarchy + moarchy** | The desktop identity (Omarchy) and its mobile port with the phone shell | `basecamp/omarchy` · `github.com/SimonSchubert` |
| **Proprietary firmware** | Signed vendor blobs the SoC will not run without — not open, not replaceable | `FairBlobs/FP4-firmware` |
| **Built / patched here** | Kernel drivers (audio, NFC), the NFC app, the location toggle, the FP4 device package | branch `fp4-claude`; upstream PRs #11/#12 and the ST21NFCD RFC |

Exact pins for all of these live in [`../manifest.toml`](../manifest.toml).

## Where postmarketOS actually fits

pmOS is often assumed to be the base of any Linux phone; here it is not. This
image is Arch Linux ARM. postmarketOS shows up as exactly three things:

1. **The kernel `.config`** — pulled from pmaports
   (`device/community/linux-postmarketos-qcom-sm6350/`).
2. **A few device daemons** — `q6voiced` (call-audio PCM), `81voltd` (VoLTE
   IMS), `bootmac` (WiFi/BT MAC from the serial).
3. **Knowledge** — the pmOS wiki and pmaports are the reference for how to make
   FP4 hardware work, and where our audio/NFC findings are offered back.

It is a knowledge-and-parts donor, not the operating system.

## If Omarchy ships official ARM ("dragon")

"Dragon" is the presumed Omarchy-on-ARM effort. It is **not** in this tree, so
this section is reasoning, not a repo fact — there were no dragon deliverables to
check against. The dividing line is simple: dragon is a *desktop* layer, and
almost everything hard in this build sits *below* the desktop.

**Could converge on dragon:**

- **Omarchy config & theming** *(likely)* — if dragon publishes ARM packages,
  moarchy's `port-4x` patch (the work of making x86 Omarchy build for aarch64)
  largely goes away; track dragon instead of porting each release.
- **Package sourcing** *(likely)* — Omarchy is currently fetched and rebuilt for
  ARM locally; dragon would make that a first-class target.
- **Compositor defaults** *(partial)* — Hyprland tuning and keybinds could come
  from dragon, but a phone still needs gestures and rotation a desktop config
  won't carry.

**Stays ours / upstream regardless:**

- **The whole phone shell** — gestures, on-screen keyboard, dialer, control
  centre, SIM. moarchy-specific; a desktop ARM Omarchy has no mobile UI to hand
  us.
- **Kernel + all drivers** — the SM6350 kernel and our audio/NFC/mic work are
  hardware enablement. No compositor project touches this; it belongs in
  mainline.
- **Firmware & Qualcomm stack** — blobs, qrtr, rmtfs, qbootctl, the modem
  daemons. SoC-level, identical whatever renders on top.
- **Sensors, camera, modem, GPS** — hexagonrpc, megapixels, the ModemManager
  glue. Device plumbing, not desktop.

**The headline:** dragon could let this project stop maintaining the desktop
*port* and theming, and maybe the base package sourcing. It would not replace the
phone shell, and it touches none of the hard hardware work. Becoming
"independent of postmarketOS" is a separate goal: even with dragon, the
pmOS-derived pieces (kernel config, call-audio daemons) stay in play until that
work lands in mainline.
