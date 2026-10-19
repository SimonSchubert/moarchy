# Fairphone 4 — roadmap to a daily-drivable moarchy

Where this port goes next, and why in this order. This is the strategy layer
above [`fp4-defects.md`](./fp4-defects.md) (what is broken) and
[`fp4-fixes.md`](./fp4-fixes.md) (what is solved); it says which of those to
attack first and what "done" looks like. Read
[`architecture.md`](./architecture.md) first for the stack this sits on.

## The one strategic question: wait for Omarchy-on-ARM ("dragon")?

**No. Don't wait — but keep the desktop layer thin so dragon is a cheap swap
later.**

The reasoning is the dividing line from
[`architecture.md`](./architecture.md#if-omarchy-ships-official-arm-dragon):
**dragon is a *desktop* layer, and everything hard in this build sits *below*
it.**

- **What dragon would actually save:** the `port-4x` patch (building x86
  Omarchy for aarch64) and the local base-package rebuilds. Real, but a
  maintenance cost — not a capability, and not the current bottleneck.
- **What dragon does not touch:** kernel and drivers, firmware, device
  services, the phone shell (gestures, OSK, dialer), power management, the
  modem. That is essentially the entire list of what is still unstable.

So waiting stalls every real blocker in exchange for saving patch-maintenance we
are not bottlenecked on. The hedge instead:

1. Keep `port-4x` **minimal and well-isolated**, so tracking Omarchy releases is
   cheap and dragon later drops in.
2. Track Omarchy loosely; do not couple hardware work to a specific Omarchy
   version.
3. Push everything below the desktop **upstream** (see Track B) — that work is
   valid no matter what happens with dragon.

Reframe worth internalizing: **the Omarchy apps already run** — this is Arch
Linux ARM + Hyprland + quickshell. What is missing is not app support, it is
*trust* (Track A) and *touch ergonomics* (Track C). dragon helps neither.

## Current readiness

Per the table in [`fp4-defects.md`](./fp4-defects.md), the phone is **partial**
across nearly every axis — audio, camera, wifi, calls, battery all `P`. It
boots and demos; it is not yet trustworthy as a sole device. The roadmap is
ordered to close that trust gap first.

## Track A — Trust: "safe as my only phone"

The gap that matters most, and the least explored. Do these first.

### A1. Power management, suspend and battery  *(start here)*
The single biggest unknown: there is no suspend/idle-drain investigation on
file and battery is rated `P`. Target:
- s2idle suspend that actually sleeps, and **wakes** for a call, an alarm and
  the power button (wake-source plumbing: modem, RTC, gpio-keys).
- measured idle drain overnight that is survivable, not a demo-only figure.
- fold in the stuck `gcc_camera_axi_clk` (D23) — a clock left on "can block
  suspend later".
**Done =** wakes reliably for calls/alarms and survives a night on standby.

### A2. Wi-Fi stability (D5)
Associates, then degrades — a phone whose Wi-Fi rots is not daily-drivable.
Tracked upstream (pmaports); the lever is coordination, not a local patch.
**Done =** a link that stays usable for hours without a reconnect.

### A3. Reboot / recovery reliability (D11)
Random drops into EDL on repeated reboots undermine trust. Needs a root cause,
not just the recovery script.
**Done =** N clean reboots in a row with no EDL drop.

### A4. Modem robustness
Calls both directions, SMS, mobile-data reconnection, remaining mic paths
(D14), and Bluetooth call audio (D21).
**Done =** a call placed and received reliably, with working audio, on cellular.

## Track B — Sustainability: keep it working with less effort

Highest long-term leverage, and **dragon-independent** — do it in parallel.

### B1. Upstream the enablement
Every driver that lands in mainline + pmaports shrinks the kernel package and
the maintenance surface **permanently**. In flight: NFC pivoted from our
standalone RFC (`upstream/nfc-st21nfcd/`, now superseded) onto Kristian Brox's
st-nci raw-NCI series, brought up on the FP4 with three fixes sent to LKML and
mirrored as [PR #14](https://github.com/sm6350-mainline/linux/pull/14); audio is
[PR #11](https://github.com/sm6350-mainline/linux/pull/11) (mic DT) and
[PR #12](https://github.com/sm6350-mainline/linux/pull/12) (aw88264 amp) with the
use-case config moved to
[sm6350-mainline/alsa-ucm-conf#2](https://github.com/sm6350-mainline/alsa-ucm-conf/pull/2);
the FP4 DT camss supplies are
[PR #15](https://github.com/sm6350-mainline/linux/pull/15). This is the durable
win and it waits on no one.

### B2. Reproducible / CI image builds
So a reflash is not a manual marathon and regressions are caught. The
build/flash/verify pipeline exists; make it repeatable and, ideally, automated.
A manual-trigger **debug kernel** variant now exists (`debug_kernel` input on the
FP4 build workflow, merging `config.debug`); see B3.

### B3. Harden / slim the release kernel
Now that debug instrumentation has a home in the `-debug` variant, the daily
release kernel should **shed it** - it currently still carries things that cost
battery, performance, size and attack surface in normal use (e.g. `FTRACE` /
`FUNCTION_TRACER` / `FUNCTION_GRAPH_TRACER`, `QCOM_STATS`, `DEBUG_INFO*`/`BTF`,
`*_DEBUG` leftovers). Audit the vendored config, move the debug-only symbols into
`config.debug`, and disable them in the release build; measure the battery, boot
and image-size delta. Keep it config-only (no patches), same as the rest of the
kernel package. Ties into A1 (battery) and the D29 suspend work.

## Track C — UX polish: where "runs Omarchy fine" actually lives

After trust. This is the touch-ergonomics layer.

- **First-launch wizard** — a fresh flash currently drops you into a phone you
  cannot get into: userdata is wiped, so there is no account password (the
  lock-screen PIN is rejected because the account is locked), sshd boots
  `inactive`, and WiFi has no saved network. Today the only way back in is the
  `/dev/ttyACM0` serial shell (set a password with `chpasswd`, start sshd,
  connect WiFi). A first-boot wizard should provision these on the device
  itself: set the screen PIN/password, join a WiFi network, and enable ssh, so a
  reflash does not require a cable. This is the on-device counterpart to the
  reflash-recovery pain in [A3](#a3-reboot-recovery-reliability-d11) / the CI
  image work in [B2](#b2-reproducible-ci-image-builds).
- **OSK reliability** — the app-drawer keyboard still does not type (D27).
- **Lock screen hardening** — failed-attempt backoff before the PIN is real
  security.
- **Telephony UX** — dialer, SMS/MMS, contacts, notifications ergonomics.
- **Feature depth** — GPS assistance (D8), and a camera **autofocus actuator
  driver** to unlock the main sensor (see D6/D23; the ultra-wide is a
  fixed-focus stand-in until then).

## The headline

Don't wait for dragon. Go after **power/suspend (A1)** and **Wi-Fi (A2)** next —
they are what stand between "works on the bench" and "trustworthy in the
pocket." **Upstream in parallel (B1)** because it is the durable, dragon-proof
win. Keep the desktop layer thin so dragon, when it lands, is a free upgrade
rather than a migration.
