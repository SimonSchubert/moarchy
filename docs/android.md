# Android apps — specification

How moarchy runs Android apps, and what it costs to ship that by default.

Status: **measured on the Pixel 3a, 2026-09-17.** Waydroid 1.6.3 from ALARM
`extra`, LineageOS 20 (Android 13) arm64 with GApps, on `moarchy-sargo`.
Telegram, Google Maps, Basecamp, CoinGecko, OKX, Wise and Curve all install,
launch and render. Google Play works, signed in, and installs apps that then
appear in moarchy's own drawer with their icons.

Nothing in this file is packaged yet. Everything below ran by hand on one
device, and §7 is the list of what that leaves open.

Companion to [devices.md](devices.md), whose §2 non-goal this amends, and to
[structure.md](structure.md), which decides what a package is.

---

## 1. The amendment

`devices.md` §2 says:

> - **Not an Android app compatibility layer.** No Waydroid, no Halium.

**Halium stays out.** It is a different device stack, it replaces the kernel
story this project just finished building, and nothing about it is additive.

**Waydroid comes in, narrowly:** an *optional* package that a user installs, on
devices with the RAM and the GPU for it, carrying configuration this project
owns and no Android code of its own. The same shape as the `devices.md`
amendment: we package what upstream has already brought up, at a pin, and we do
not do bring-up.

The reason the old answer was no is in `moarchy-meta`'s PKGBUILD (2026-09-06):
the first run downloads about a gigabyte, and a dependency should not commit a
fresh phone to that. §4 is how that objection is answered rather than ignored.

---

## 2. Device scope

**sargo only.** Not the PinePhone, and this is not a "later" — it is a no.

The PinePhone has 2 GB of RAM to share with an Android container, and a
Mali-400 that is GLES 2.0 against LineageOS 20's expectations. Waydroid picks
`gralloc=gbm, egl=mesa` the moment it sees a DRI render node
(`tools/helpers/lxc.py:268-286`), so it will try the Mali and the only fallback
is `swiftshader` — software rendering on four A53s. That is a demo, not a phone.

sargo is the opposite: `ro.hardware.vulkan=freedreno` and
`ro.opengles.version=196610` (GLES 3.2) land in `waydroid_base.prop` without
help, and the hwcomposer reads `wp_fractional_scale_v1` and sets
`lcd_density = 180 × scale` — 540 at our scale 3, so Android renders at native
resolution and correct physical size.

**The kernel needs no change.** `linux-moarchy-sdm670`'s config already has
`CONFIG_ANDROID_BINDER_IPC=y` with `ANDROID_BINDER_DEVICES="binder,hwbinder,vndbinder"`.
`BINDERFS` is off, and that is fine: `probeBinderDriver` only modprobes and
mounts binderfs when one of `/dev/binder`, `/dev/vndbinder`, `/dev/hwbinder` is
*missing* (`tools/helpers/drivers.py:66-105`), and all three are static nodes
here. Verify the `BRIDGE`/`VETH`/`TUN`/`IP_NF_*` modules ship, which
`waydroid-net.sh` needs.

---

## 3. What is device-independent and what is ours

Waydroid gets more right than expected. These need **no code**:

| | why |
|---|---|
| Drawer entries | Waydroid writes `~/.local/share/applications/waydroid.<pkg>.desktop` per launcher app (`tools/services/user_manager.py:97-131`) |
| Icons and names | the Wayland `app_id` is `waydroid.<pkg>` — the *same string* as the desktop id — so `Apps.index()` resolves both already; the icon is an absolute PNG path, which `AppLibrary.iconSource()` handles |
| Window management | Android apps are ordinary toplevels, so `moarchy-one-app-per-workspace` gives each its own workspace |
| Notifications | Waydroid forwards to `org.freedesktop.Notifications` (`tools/services/notification_manager.py:74`), so Android notifications land in moarchy's shade with their icons |
| Clipboard | bridged both ways |

What is **ours** is a small amount of configuration, and it is the whole
content of the proposed package:

```
persist.waydroid.multi_windows = false   # see AC 5
persist.waydroid.width  = <output logical width>
persist.waydroid.height = <workspace logical height>
+ an immersive watcher                   # see AC 6
+ a Back rung in the gestures ladder     # see AC 7
```

---

## 4. The two decisions that are not mine

### D1. Image size

Waydroid supports **preinstalled images**: `system.img` and `vendor.img` under
`/usr/share/waydroid-extra/images` make `waydroid init` set
`system_ota = "None"` and download nothing (`tools/actions/initializer.py:56-76`).
That answers the 2026-09-06 objection completely — a fresh phone is committed to
no download at all.

It costs image size, raw:

| | size |
|---|---|
| VANILLA `system.img` | 1.98 GB |
| GAPPS `system.img` | 2.91 GB |
| `vendor.img` | 422 MB |

So +2.4 GB (VANILLA) or +3.3 GB (GAPPS) before compression, on an image that is
currently a fraction of that. **This is a judgement about what moarchy's
published artifact is for**, and it is not mine to make. The alternative is
shipping the package without images and leaving `waydroid init` to download —
which is honest, but then "installed by default" means "installable", and the
first run is a gigabyte over the user's connection.

### D2. Google Apps are not ours to redistribute — **decided 2026-09-18: no**

**The Play Store cannot ship in a published moarchy image.** The GAPPS system
image is LineageOS plus Google's proprietary apps, and baking it into an image
this project publishes is redistributing Google's software without a licence to
do so. That is a legal question, not a packaging one, and the answer does not
change because it is technically easy.

What is defensible:

- ship **VANILLA** preinstalled (LineageOS, redistributable), and
- make `waydroid init -s GAPPS` a documented, one-command user action that
  replaces the image on their own device, with the 1.33 GB download and the
  `google.com/android/uncertified` registration their choice to make.

Play certification is a per-device registration of the `android_id` and cannot
be done for the user in advance either.

**Decided 2026-09-18.** No Android app ships preinstalled — not the Play Store,
not YouTube, not Spotify. The first two are Google's to license and the third
is Spotify's, and a published image carrying any of them is redistribution
whatever the packaging looks like. `pm list packages -3` on the test device is
the tell: YouTube and Spotify were *third-party* installs pulled from Play by
the user, never part of the image. That stays the shape — Play installs them in
about a minute under the user's own account, and moarchy ships the
configuration that makes them behave like a phone app once they are there.

This closes D2. **D1 (whether a published image grows to carry the system
images) is still open.**

---

## 5. Acceptance criteria

**AC 1** `moarchy-waydroid` exists as a package, is **not** in `moarchy-meta`'s
`depends`, and is installable from the Store.
→ `pacman -Qi moarchy-waydroid` after a Store install; `moarchy-meta`'s depends
does not name it.

**AC 2** It depends on `waydroid`, which resolves entirely from ALARM `extra`
(`waydroid 1.6.3-1`, pulling `lxc python-gbinder nftables dnsmasq gtk3
python-dbus pulse-native-provider`). Nothing is built from source.
→ a clean `pacman -S moarchy-waydroid` in the builder container succeeds.

**AC 3** On a device with no network, `waydroid init` completes using
preinstalled images and downloads nothing.
→ `waydroid.cfg` has `system_ota = None`; `cache_http` stays empty.
*(Conditional on D1.)*

**AC 4** Android apps appear in the drawer with their own icon and name, and
disappear when uninstalled.
→ install any app; `~/.local/share/applications/waydroid.<pkg>.desktop` exists
and the drawer shows it **without a shell restart**.

**AC 5** An Android app fills the screen: no black band, no Android titlebar.
→ `wm size` equals the sway window rect in physical pixels.
**`multi_windows` stays false**: true hides the bars for free but puts Android
into freeform windowing — apps become small floating windows with Android
titlebars — and makes the IME its own tiled toplevel. Measured, both.

**AC 6** Neither Android bar is visible, **after a launch from the drawer**.
→ `settings get global policy_control` reads `immersive.full=*` with an app
foreground. The drawer's entries are `Exec=waydroid app launch <pkg>`, and
`waydroid app launch` **rewrites `policy_control` on every launch**
(`tools/actions/app_manager.py:78-85`), so this cannot be a one-time setting.
The prototype re-asserts it from a sway `window::new` subscription.
*Known gap:* it fires on new windows, so an activity change inside an existing
window (Play Store installing, say) can still bring the bar back.

**AC 7** The left-edge back swipe navigates *inside* an Android app rather than
closing it.
→ with an Android app focused, one back swipe goes up one screen; on the root
screen it finishes the activity, which closes the toplevel — G4's outcome.
Waydroid forwards the **raw evdev keycode** into Android's InputFlinger
(`wayland-hwc.cpp:696-720`), so a synthetic `KEY_BACK` is native Back.
`waydroid shell -- input keyevent 4` is **not** viable: measured **1.153 s**.
The uinput device must be long-lived — creating one per gesture costs a ~2 s
settle before sway routes it.

**AC 8** `docs/apps.md` and `docs/devices.md` move in the same commit: the
non-goal amended, the package listed.

**AC 9** A duplicate name in the drawer is resolved. Android Maps and Contacts
sit beside moarchy's own with nothing to tell them apart.
→ decide: a badge, or `launcher.hides` entries for Android apps that duplicate
something native.

---

## 6. Measured, not estimated

Basecamp on sargo, container running, load ~1.1:

| | |
|---|---|
| cold start (`am start -W` after force-stop) | **2442 / 2557 / 2515 ms** |
| warm start | **248 / 203 ms** |
| `waydroid app launch` → sway window | **891 / 904 ms** |
| from a **frozen** container → window | **892 ms** |
| from a **frozen** container → activity resumed | **1928 ms** |

Two things fall out. **The window appears before the app is drawn** — ~0.9 s
versus ~2.5 s — so anything measuring launch by window appearance reports about
a third of the real wait. And **freezing costs nothing**: the frozen case
resumed *faster* than a cold start, because the process was still alive.
`suspend_action: freeze` suspends rather than tears down, and needs no tuning.

The expensive states are one-offs: a stopped session is ~24 s to boot, and the
first launch after an install adds `dex2oat`.

---

## 7. Open, and honest about it

- **No location, at all.** There is no GNSS HAL in the container and no `gps`
  provider — only `passive`, `network`, `fused`. With location enabled and
  permissions granted, every provider held `locations = 0` over 15 minutes, and
  Last Known Locations stayed empty. The host cannot help either: ModemManager
  has `gps-nmea` as a *capability* but only `3gpp-lac-ci, cdma-bs` enabled and
  `signals: no`. Maps draws, and shows the wrong continent.
- **Audio works; camera untested.** Spotify plays through to the speaker. The
  path is Android -> `audio.primary.waydroid.so` -> the bind-mounted
  `/run/xdg/pulse/native` -> a PulseAudio sink-input named `Waydroid` -> the
  speaker sink. Two things cost an hour and are worth writing down, because both
  *looked* like the cause and neither was:

  1. **Android's own `STREAM_MUSIC` volume starts at 5 of 15** on a fresh
     container. The host stream is then present, uncorked and at 100% while
     carrying almost nothing — which reads exactly like a broken route. Check
     `dumpsys audio | grep -A6 STREAM_MUSIC` *first*; `input keyevent 24` raises
     it (`media volume` is not a command in this image).
  2. **sargo's UCM defines only a `VoiceCall` verb** — there is no `HiFi`, and
     `pactl list cards` offers only `off`, `VoiceCall x4` and `pro-audio`. That
     looks fatal for media and is not: the VoiceCall profile plays media to the
     speaker correctly. Do not go chasing a missing HiFi verb on this evidence.

  `ro.hardware.audio.primary` is unset in the image, so Android loads
  `audio.primary.default.so` rather than `audio.primary.waydroid.so`. Setting it
  to `waydroid` in `waydroid_base.prop` is correct, but it was **not** what made
  sound appear -- a `Waydroid` sink-input existed before the change.

  Camera is still untested; `ro.hardware.camera=v4l2` is in the base prop.
- **Widevine L1 and NFC/HCE are out**, so DRM video and Google Pay cannot work.
- **App hardening is per-app and not predictable from a list.** Revolut
  10.147.1 is killed by its own SDK — `android.app.TerminateException`, before
  any UI, unaffected by Play services or a signed-in account. Wise warns and
  offers *Continue anyway*, reaching a real login screen. Curve behaved
  **differently installed from Play than sideloaded**, which is the caution
  worth keeping: a sideloaded APK failing is not evidence the app fails.
- The immersive watcher and the Back rung exist as prototypes on one device,
  under `/tmp`, surviving no reboot.
