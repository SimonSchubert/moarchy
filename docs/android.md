# Android apps — specification

How moarchy runs Android apps, and what it costs to ship that by default.

Status: **measured on the Pixel 3a, 2026-09-17, and again 2026-09-18** (the
insets, the density and the launcher). Waydroid 1.6.3 from ALARM
`extra`, LineageOS 20 (Android 13) arm64 with GApps, on `moarchy-sargo`.
Telegram, Google Maps, Basecamp, CoinGecko, OKX, Wise and Curve all install,
launch and render. Google Play works, signed in, and installs apps that then
appear in moarchy's own app drawer with their icons.

`moarchy-waydroid` is packaged and ships in 0.4.0; the inset, density and
launcher work landed after it and is unreleased. Everything below was measured
on one device, and §7 is the list of what that leaves open.

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

**Every device moarchy ships on.** *Amended 2026-09-19:* this section used to
read "sargo only, and this is not a later — it is a no", because the other
device had 2 GB of RAM to share with an Android container and a Mali-400 that
is GLES 2.0 against LineageOS 20's expectations. Waydroid picks
`gralloc=gbm, egl=mesa` the moment it sees a DRI render node
(`tools/helpers/lxc.py:268-286`), so it would have tried that GPU with
`swiftshader` — software rendering on four A53s — as the only fallback.

That constraint left with the device, and the bar it set is worth keeping for
the next one: **an Android container needs a GPU Waydroid will actually use.**

sargo clears it: `ro.hardware.vulkan=freedreno` and
`ro.opengles.version=196610` (GLES 3.2) land in `waydroid_base.prop` without
help, and the hwcomposer reads `wp_fractional_scale_v1` and sets
`lcd_density = 180 × scale` — 540 at our scale 3, so Android renders at native
resolution but **not** at the right physical size: this panel is 1080x2220 in
62x127mm, which is 444 ppi, so 540 is 23% too dense. That is corrected by
AC 13; the sentence here claimed otherwise until it was measured on
2026-09-18.

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
| App drawer entries | Waydroid writes `~/.local/share/applications/waydroid.<pkg>.desktop` per launcher app (`tools/services/user_manager.py:97-131`) |
| Icons and names | the Wayland `app_id` is `waydroid.<pkg>` — the *same string* as the desktop id — so `Apps.index()` resolves both already; the icon is an absolute PNG path, which `AppLibrary.iconSource()` handles |
| Window management | Android apps are ordinary toplevels, so `moarchy-one-app-per-workspace` gives each its own workspace — though "no code" was too strong: the sway rule below floats them (AC 5), and both that daemon and the app drawer's hop had to learn that a floating window occupies a workspace before this was true (windows.md W6, L10) |
| Notifications | Waydroid forwards to `org.freedesktop.Notifications` (`tools/services/notification_manager.py:74`), so Android notifications land in moarchy's control center with their icons |
| Clipboard | bridged both ways |

What is **ours** is a small amount of configuration, and it is the whole
content of the proposed package:

```
persist.waydroid.multi_windows = false   # see AC 5
persist.waydroid.width  = <output logical width>
persist.waydroid.height = <output + both inset overhangs>   # AC 5, AC 10
+ a sway rule giving the toplevel that size at that offset  # AC 5, AC 10
+ a launcher that replaces `waydroid app launch`            # AC 11
+ a bar that steps aside, and a handle Android stops drawing # AC 12
+ a density that matches the panel rather than the scale     # AC 13
+ a Back rung in the gestures ladder                        # AC 7
```

The height is the **output** plus an overhang at each edge, not the workspace
rect. Pinning it to the workspace (what this file said until 2026-09-18) makes
Android's display exactly the tile sway gives it, which is self-consistent and
gives up the thing this is for: the app's own background behind our chrome, and
Android — rather than sway's tiling — doing the padding.

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

**AC 4** Android apps appear in the app drawer with their own icon and name, and
disappear when uninstalled.
→ install any app; `~/.local/share/applications/waydroid.<pkg>.desktop` exists
and the app drawer shows it **without a shell restart**.

**AC 5** An Android app fills the screen **and its content clears moarchy's own
chrome**, with no black band and no Android titlebar.
→ `wm size` equals the pinned size, the toplevel rect equals it, and the two
insets land on the bar and the strip: on sargo `wm size` 1080x2259, rect
`{0,-6,360,753}`, `ITYPE_STATUS_BAR` ending at screen y=77 against the bar's 78
and `ITYPE_NAVIGATION_BAR` starting at 2160, which is the strip's top edge.
Measured 2026-09-18.

The numbers are **derived, never hardcoded** (AC 10). Android's insets are
bigger than this phone's chrome — 28dp against a 26px bar, 24dp against a 20px
strip — so a window sized to the output leaves a gap at each edge. The window
overhangs both screen edges by the difference instead, which is why its height
exceeds the output and its `y` is negative.

**Floating, not fullscreen.** sway v1.12's scene order is
`tiling -> floating -> shell_top -> fullscreen -> shell_overlay`
(`include/sway/tree/root.h`), so a fullscreen window draws *over* the bar while
a floating one sits under both it and the strip. `move absolute position` is
load-bearing: plain `move position` is workspace-relative and lands at y=26.

**`multi_windows` stays false**: true hides the bars for free but puts Android
into freeform windowing — apps become small floating windows with Android
titlebars — and makes the IME its own tiled toplevel. Measured, both.

**AC 6** Both Android bars are **present as inset providers and never drawn**.
→ `dumpsys window -a | grep ITYPE_` reports `ITYPE_STATUS_BAR
frame=[0,0][1080,95] visible=true`, and no Android clock or status icon is on
screen. This **replaces** the old criterion, which was "neither Android bar is
visible" via `policy_control=immersive.full=*`. That is now the thing we must
not do: immersive is what sets the status bar inset to
`frame=[0,0][1080,0] visible=false`, and without the inset an app draws its
first line of content behind moarchy's bar.

Two mechanisms, both measured:

- `policy_control=null*` (the value Waydroid's own `show-full-ui` writes) keeps
  both insets. It must be in place **before the window's first layout** — AC 11.
- `cmd statusbar send-disable-flag clock system-icons notification-icons` blanks
  SystemUI's contents while keeping the 95px inset. Needed only because the bar
  is transparent over an Android window (AC 12): Android's status bar was always
  being drawn, and an opaque bar was hiding it. It is cleared by a SystemUI
  restart, so the launcher re-asserts it every launch — after its own restart of
  SystemUI rather than before, since that is one of the restarts that would
  clear it (AC 12).

`moarchy-waydroid-immersive` and its user unit are **gone**, not amended. A
`window::new` watcher cannot do this job: by the time a window exists the layout
has happened, and re-asserting afterwards does not re-pad the app (AC 11).

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

**AC 9** A duplicate name in the app drawer is resolved. Android Maps and Contacts
sit beside moarchy's own with nothing to tell them apart.
→ decide: a badge, or `launcher.hides` entries for Android apps that duplicate
something native.

**AC 10** The geometry is **computed on the device**, never a constant in a
file. `moarchy-waydroid-setup` reads the output rect, the workspace rect (which
is where the bar and strip heights come from, since layer surfaces are invisible
to sway's IPC) and Android's own inset frames, and emits both the size pin and
the sway rule.
→ `persist.waydroid.height` and the generated
`~/.config/sway/config.d/90-moarchy-waydroid.conf` agree, and neither 753 nor
-6 appears as a literal in the repo. The same script on a device with a
different scale, bar height or panel must produce different numbers without
being edited.

**AC 11** `policy_control` is `null*` **at the window's first layout**, after a
launch **from the app drawer**.
→ poison it (`settings put global policy_control "immersive.status=*"`), launch
from the app drawer, and read it back: `null*`, with the status inset non-zero.

This is the criterion the whole design turns on, and three orderings were
measured on 2026-09-18 to establish it:

| when `null*` is set | top padded? |
|---|---|
| after the launch | **no** — the inset returns but the app never re-flows |
| before `waydroid app launch` | **no** — its rewrite still wins the race to layout |
| before the activity starts, without `waydroid app launch` | **yes** |

So `waydroid app launch` cannot be used at all, and `moarchy-android-launch`
replaces it: unfreeze over `gdbus`, set `waydroid.active_apps` (without it a
cold app gets **no Wayland window**), then one `waydroid shell` attach that sets
`policy_control`, blanks the bar contents, resolves the launcher activity and
starts it. **One** attach because each costs ~1.1s measured, against
`waydroid app launch`'s ~0.9s to window.

It does **not** force-stop first, deliberately: that would kill playback on
every tap. The cost is that an app already running with the wrong insets keeps
them until it is stopped once.

**AC 12** Over an Android window the bar goes **transparent** and the strip
stays transparent, as it is everywhere else — so both bands are the app's own
background, with one pill in the lower one and it is ours.
→ sample both bands with `grim`. Over a Waydroid window the bar band is the
app's own pixels, continuous across y=78; on the home screen it is
`Color.bar.background`. The strip band is the app's background continuous across
y=2160 — 15 under YouTube, 255 under Maps — carrying our pill and no pixel above
100 anywhere else. Measured both ways and both apps, 2026-09-18.

**Android draws its own gesture handle inside the app surface**, 108dp wide and
10dp up from the bottom of its display. Measured: 296px wide at rows 2184–2198,
brightness 221–236, which is *the same rows* as our own pill at 2184–2196. Two
bars, one bright and one dim, reading as a single smudge.

For a few hours the answer was to cover it — the strip went opaque over an
Android window — and that is what this AC replaced. It stopped the app's
background 20px short of the screen and put a slab of chrome colour under every
light app, which is a worse thing to look at than the problem it solved. So take
the handle out at the source:

| | |
|---|---|
| `settings put secure sysui_nav_bar` | dead in Android 13 — `NavigationBarInflaterView` no longer implements `Tunable` |
| `cmd statusbar send-disable-flag home` | does not touch the handle (the clock and status icons it does blank — AC 6) |
| `org.lineageos.overlay.customization.navbar.nohint` | the wrong lever, and now measured rather than guessed: its idmap maps `navigation_bar_height`, `navigation_bar_height_landscape` and `navigation_bar_width`, and its own value for all three is **0dp**. It deletes the navigation bar, and the INSET with it — the one thing here worth keeping. That it also reverts to `STATE_DISABLED` on its own is still unexplained, and no longer matters |
| a **fabricated RRO** zeroing `com.android.systemui:dimen/navigation_handle_radius` | **this one.** `NavigationHandle.onDraw` fills a round rect of height `2 * radius`, so zero draws nothing, and nothing else in SystemUI reads that dimension. `cmd overlay fabricate` needs no APK, so no Android code enters the project, and the inset is untouched: `ITYPE_NAVIGATION_BAR frame=[0,2160][1080,2226]` before and after |

**`moarchy-android-launch` applies it, not `moarchy-waydroid-setup`**, and that
is forced rather than chosen. A fabricated overlay lives in
`/data/resource-cache` and is registered in `/data/system/overlays.xml`, and a
`waydroid session stop` takes both: after a restart the `.frro` file is gone,
`cmd overlay list` does not name it, and the resource reads `2.0dip` again — all
three measured. Every Android app on moarchy is started from the launcher, so
the launcher is the only place that can hold it, and the setup script's own last
line tells the operator to stop the session.

**Registering it is not enough**, which cost a run to find out. SystemUI reads
the radius when it inflates the navigation bar, and a freshly booted SystemUI
inflates *before* it notices an overlay registered a second earlier — the handle
came back 20s into a launch that had just enabled it. So the launcher restarts
SystemUI on that cold path and waits for its navigation bar to exist again
before `am start`: waiting for the process is not waiting for the window, and
the app's first layout is the one that counts (AC 11). It costs 4.2s for the
first launch of a session against 2.4s warm, and the disable flags are asserted
after the restart rather than before it, or they go with it.

**The pill carries its own contrast now.** It used to be given one, because the
band behind it was either this strip's colour or the wallpaper; over an Android
app it is the app's background, and a 30%-foreground pill measures 235 against
Maps' 255 — there, but only just. A ring of `Color.background` behind it is
invisible against everything the strip normally sits on and an outline against
everything else: 144 with a 125 ring on Maps' white, 67 with a 10 ring on
YouTube's 15.

The bar half is **not** the `bar.transparent` key `Bar.qml` refuses to read. That
was a global flag written by `omarchy-bar transparent`, whose config reload takes
this bar down and leaves upstream's in its place. This is derived from focus,
nothing writes it, and no config carries it across a reboot.

*Open, and known:* our bar glyphs are light, so a light-themed Android app puts
light text on a light header. Spotify and YouTube are both dark; Maps is not. If
it bites, the answer is a scrim rather than full transparency — one value in
`androidFocused`'s consumer in `Bar.qml`, not a redesign.

**AC 13** Android's density matches the panel, and is **computed from it**.
→ `wm density` equals `round(diagonal px / diagonal inches / 10) * 10` for the
DRM connector's reported size — 440 on sargo, against the 540 the hwcomposer
computes on its own.

`lcd_density = 180 × scale` (`finished_calibrating()`, and only when
`ro.sf.lcd_density` is unset) assumes a logical pixel is 1/180", where on this
panel it is 1/147". The cost is not only that everything is 23% too large:
540 also tells Android the screen is **320dp wide when it is 393dp**, which is
a narrower bucket than a 2014 phone, so apps choose small-screen layouts.
Spotify drew a one-column shortcut grid at 540 and its normal two-column grid
at 440, with four filter chips fitting instead of three and a bit.

The panel's physical size is read from the DRM connector with `modetest`, which
is the only source on the device: sway's `get_outputs` carries no mm anywhere,
and sargo's device tree has no `width-mm`.

**This is why AC 5's overhang is nearly zero at the correct density.** Android's
28dp status bar is 77px at 440 against this bar's 78, and its 24dp nav bar is
66px against the strip's 60 — so the computed geometry becomes `742 at y=0`
rather than `753 at y=-6`. The insets and our chrome agree to a pixel at the
top, which is a coincidence rather than a design, and it is the reason to
compute rather than choose: at 540 the same script produced 753 and -6, and
both were right for their density.

*Two-pass, and deliberately.* Changing the density needs a container restart
before the dp-measured insets mean anything, so the script writes it and stops
with the three commands to run. A single pass would compute the geometry against
the density it is replacing.

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
- The Back rung exists as a prototype on one device, under `/tmp`, surviving no
  reboot.
- **The app drawer is the only launch path covered.** `moarchy.app-drawer` routes
  `waydroid.*` entries through `moarchy-android-launch` itself, which Waydroid
  cannot race. Anything else that starts an Android app — `gtk-launch` by hand,
  `omarchy-launch-or-focus`, an intent from another app — still goes through
  `waydroid app launch` and lands with the status bar inset suppressed.
  Rewriting the generated `.desktop` files would cover every path, but
  `user_manager` regenerates them on each session start, so it needs a watcher
  and converges rather than holding; measured on 2026-09-18, 3 of 25 entries sat
  reverted between a regeneration and the re-fixup. Routing in our own code has
  no such window, which is why it is the shipped half. The same bullet now
  carries the gesture handle: the launcher is also what registers the overlay
  that stops Android drawing it (AC 12), so an app started any other way in a
  fresh session gets both the suppressed inset and the handle.
- **Duplicate surfaces after repeated launches.** Ten force-stop/`am start`
  cycles left three `waydroid.com.spotify.music` toplevels in `get_tree` at
  once, and Spotify eventually came up mapped but unpainted
  (`topResumedActivity` set, nothing drawn). A session restart clears both. Not
  understood, and not provoked by ordinary use.
