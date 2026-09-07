# Omarchy menu coverage

Which of Omarchy 4.0.2's menu entries the phone supports, which it adapts, and
which it drops. This file is the *record*; `docs/settings.md` is the contract the
Settings UI is built to, and `bin/moarchy-selftest --settings` checks both
against the code.

Upstream ships **320 entries** in `default/omarchy/omarchy-menu.jsonc`, pinned at
v4.0.2 (`346e69e1`). Every one of them appears below exactly once.

## How to read this

| Class | Meaning |
| --- | --- |
| **Native** | Reimplemented as a phone control or screen. moarchy code, not Omarchy's. Container rows that become one of our screens are Native too -- nothing of upstream's runs. |
| **Bridged** | Upstream's own script runs unchanged; only the way it is launched changes -- a tiled TUI-sized terminal instead of a floating one, epiphany instead of a Chromium web app. |
| **Shade** | Already a control in the pull-down shade. Deliberately not repeated in Settings. |
| **Unsupported** | Hidden from the UI. The reason names the missing binary, the x86_64 constraint, or the Hyprland dependency. |

Two rules decide the hard cases.

**A package that is aarch64-verified but not installed by default is Bridged,
not Unsupported.** That set used to be a file, `moarchy-extras.packages`; since
M2 deleted both `.packages` files (`docs/structure.md` P6) it is the commented
"Not installed by default" block at the foot of
`pkgbuilds/moarchy-meta/PKGBUILD`. The row gets a
`when: omarchy-cmd-present <bin>` guard and appears once the user installs it.
"Not installed" is not "impossible". Genuine hardware blocks stay Unsupported --
today that is the microphone, which records digital silence at PipeWire and at
raw ALSA. It is no longer the camera: Megapixels 2.1.0 streams both sensors as
of 2026-09-06 (`docs/apps.md`), so any row still resting on `VIDIOC_STREAMON`
is resting on a diagnosis that was wrong.

**Bridged means the command is untouched.** 128 of the 320 rows are
`omarchy-launch-floating-terminal-with-presentation <script>`, and every
`omarchy-*` script they name exists upstream. Because `bin/` here shadows
`$OMARCHY_PATH/bin` by PATH order, one shim for that wrapper -- routing to
`moarchy-launch-tui`, a foot at font size 7 -- makes the whole class work
without reimplementing any of it. Of the 58 Bridged rows, all but four run a
command byte-identical to upstream's `action`; `docs/settings.md` E2 names the
four and the selftest diffs them statically.

That terminal is a normal tiled window. It was fullscreened until 2026-09-06,
which made every row that asks a question unanswerable: sway draws a fullscreen
view above the Top layer, the keyboard is a Top-layer surface, so the prompt
appeared and the keys did not.

## Totals

| Class | Entries |
| --- | ---: |
| Native | 70 |
| Bridged | 58 |
| Shade | 1 |
| Unsupported | 191 |
| **Total** | **320** |

Roughly a third of the menu survives. That is not a gap to be closed: the
dropped two thirds are Steam and Battle.net, twenty language runtimes behind
`mise`, six desktop browsers with no aarch64 build, and Hyprland's own
configuration files.

Three rows in the tree carry no upstream id at all and so appear in none of
these numbers: **Wi-Fi networks**, **Bluetooth devices** and **Update system**.
The last is not `update.omarchy` renamed -- that id stays Unsupported for the
reason its row below gives, and this one runs `sudo pacman -Syu`, which
`docs/structure.md` R8a says works on this image and cannot move the frozen
device stack. `docs/settings.md` records why claiming the id would be a
promise the row does not keep.

Where an entry lands is written with `>` for one level down, e.g.
`Appearance > Status bar > Battery percentage`. A container row that dissolves
into several screens says so.

---

## Root (2)

Native 1 · Bridged 1

The two root entries that are not the head of a route of their own.

| id | label | class | lands at | note |
| --- | --- | --- | --- | --- |
| `apps` | Apps | Native | App drawer | the drawer is the `apps` provider; not repeated in Settings |
| `about` | About | Native | About phone > About Omarchy | a page of rows; `omarchy-launch-about` re-execs through the default terminal with `--render`, and qmlkonsole refuses it |

## System (8)

Native 3 · Bridged 2 · Unsupported 3

| id | label | class | lands at | note |
| --- | --- | --- | --- | --- |
| `system` | System | Native | System > Power | also the shade's power glyph target |
| `system.screensaver` | Screensaver | Unsupported | -- | `omarchy-launch-screensaver` exits 1 unless `ttfx` is present, and ttfx has no aarch64 build in any repo here; it failed silently, which looked like a screensaver that ran |
| `system.lock` | Lock | Native | System > Power > Lock | `moarchy-system-lock`; blanks unless a hardware keyboard is present |
| `system.suspend` | Suspend | Unsupported | -- | suspending locks the session: the session starts sway-session.target (config/sway/config, the target itself shipped by pkgbuilds/moarchy; install/config.sh started it until 2026-09-06), which brings up 4.x's omarchy-sleep-lock unit, and the lock it raises is an ext-session-lock surface -- so the on-screen keyboard is hidden by the very prompt asking for a password. Same trap idle-lock was disabled for. Locked a phone out on 2026-09-05 |
| `system.hibernate` | Hibernate | Unsupported | -- | `omarchy-hibernation-available` tests for swap; the SD root has no resume device or RAM-sized swap |
| `system.logout` | Logout | Native | System > Power > Log out | needs a new `moarchy-system-logout` (`swaymsg exit`); upstream's exits Hyprland |
| `system.reboot` | Reboot | Bridged | System > Power > Restart |  |
| `system.shutdown` | Shutdown | Bridged | System > Power > Power off |  |

## Learn (10)

Native 2 · Bridged 6 · Unsupported 2

| id | label | class | lands at | note |
| --- | --- | --- | --- | --- |
| `learn` | Learn | Native | About phone > Help & docs |  |
| `learn.keybindings` | Keybindings | Native | About phone > Keybindings | native list from `omarchy-menu-keybindings --print`; upstream's `less` fallback shows nothing |
| `learn.omarchy` | Omarchy | Bridged | About phone > Help & docs | link via the `omarchy-launch-webapp` shim |
| `learn.hyprland` | Hyprland | Unsupported | -- | Hyprland needs a GLES 3.0 context; the Mali-400 tops out at GLES 2.0 |
| `learn.arch` | Arch | Bridged | About phone > Help & docs | link |
| `learn.neovim` | Neovim | Bridged | About phone > Help & docs | link; neovim is installed |
| `learn.bash` | Bash | Bridged | About phone > Help & docs | link |
| `learn.tmux-keybindings` | Tmux | Bridged | About phone > Help & docs | `omarchy-menu-select`; tmux is installed |
| `learn.herdr-keybindings` | Herdr | Unsupported | -- | herdr is not installed and has no aarch64 build in Omarchy's repo |
| `learn.community` | Community | Bridged | About phone > Help & docs |  |

## Trigger (47)

Native 15 · Bridged 6 · Shade 1 · Unsupported 25

| id | label | class | lands at | note |
| --- | --- | --- | --- | --- |
| `trigger` | Trigger | Native | dissolved: Tools, Display, Sound, Appearance | verb-shaped container; children move next to their subject |
| `trigger.emoji` | Emoji | Bridged | Tools > Emoji | `omarchy-shell shell toggle omarchy.emojis`, a vendored QML picker |
| `trigger.reminder` | Reminder | Native | Tools > Reminders | the screen, and the list on it, are moarchy's; the timers underneath stay `omarchy-reminder`'s |
| `trigger.capture` | Capture | Native | Tools | only Screenshot survives |
| `trigger.capture.screenshot` | Screenshot | Native | Tools > Screenshot | `moarchy-capture-screenshot` (grim); no satty -- it needs a GL context this GPU cannot give and blocks the capture |
| `trigger.capture.screenrecord.stop` | Stop Screenrecording | Bridged | Tools > Screen record | upstream `when` on the running process kept |
| `trigger.capture.screenrecord` | Screenrecord | Native | Tools > Screen record | container, presence-guarded on gpu-screen-recorder: extras-only but aarch64-verified |
| `trigger.capture.text` | Text | Unsupported | -- | `omarchy-capture-text` needs tesseract, which has no aarch64 build |
| `trigger.capture.qr` | QR Code | Unsupported | -- | `omarchy-capture-qr` needs zbarimg; zbar is not in the package set |
| `trigger.capture.color` | Color | Unsupported | -- | `hyprpicker` is Hyprland-only |
| `trigger.capture.screenrecord.no-audio` | With no audio | Bridged | Tools > Screen record | presence-guarded on gpu-screen-recorder |
| `trigger.capture.screenrecord.desktop-audio` | With desktop audio | Bridged | Tools > Screen record | presence-guarded on gpu-screen-recorder |
| `trigger.capture.screenrecord.microphone` | With desktop + microphone audio | Unsupported | -- | the microphone records digital silence (RMS 0) at PipeWire and at raw ALSA |
| `trigger.capture.screenrecord.webcam` | With desktop + microphone audio + webcam | Unsupported | -- | `omarchy-hw-webcam` is false: there is no `/dev/video*` a generic app can stream, because the sensors only work through `libmegapixels` configuring the media graph. The microphone half is unsupported anyway |
| `trigger.transcode` | Transcode | Unsupported | -- | `omarchy-transcode` shells out to ffmpeg, which is not installed |
| `trigger.share` | Share | Unsupported | -- | every child unsupported |
| `trigger.toggle` | Toggle | Native | dissolved: Appearance > Status bar, Display, Sound | grouped by mechanism upstream, by subject here |
| `trigger.hardware` | Hardware | Unsupported | -- | every child unsupported |
| `trigger.tests` | Speed Test | Native | Tools > Speed tests |  |
| `trigger.hardware.laptop-display` | Laptop Display | Unsupported | -- | `omarchy-hyprland-monitor-internal` is Hyprland-only; one fixed 720x1440 panel |
| `trigger.hardware.mirror-display` | Mirror Display | Unsupported | -- | `omarchy-hyprland-monitor-internal-mirror` is Hyprland-only |
| `trigger.hardware.hybrid-gpu` | Hybrid GPU | Unsupported | -- | `omarchy-hw-hybrid-gpu` is false; one Mali-400 |
| `trigger.hardware.touchpad` | Touchpad | Unsupported | -- | `omarchy-hw-touchpad` is false; no touchpad |
| `trigger.hardware.touchpad-haptics` | Touchpad Haptics | Unsupported | -- | Dell XPS only |
| `trigger.hardware.touchpad-haptics.low` | low | Unsupported | -- | `dell-xps-touchpad-haptics` is not installed |
| `trigger.hardware.touchpad-haptics.mid` | mid | Unsupported | -- | `dell-xps-touchpad-haptics` is not installed |
| `trigger.hardware.touchpad-haptics.high` | high | Unsupported | -- | `dell-xps-touchpad-haptics` is not installed |
| `trigger.hardware.touchscreen` | Touchscreen | Unsupported | -- | `omarchy-toggle-input-device` drives hyprctl, and disabling the only input device from a touch-only UI is unrecoverable without ssh |
| `trigger.reminder.set` | Set one | Native | Tools > Reminders > Set a reminder | presets, a minutes field and a message field; upstream's `-i` is a keyboard-only prompt with no field |
| `trigger.reminder.show` | Show all | Native | Tools > Reminders | the page is the list; upstream answers in a notification |
| `trigger.reminder.clear` | Clear all | Native | Tools > Reminders | confirmed, and hidden when there is nothing to clear; still runs `omarchy-reminder clear` |
| `trigger.share.clipboard` | Clipboard | Unsupported | -- | `omarchy-menu-share` targets localsend; not installed |
| `trigger.share.file` | File | Unsupported | -- | `omarchy-menu-share` targets localsend; not installed |
| `trigger.share.folder` | Folder | Unsupported | -- | `omarchy-menu-share` targets localsend; not installed |
| `trigger.share.receive` | Receive | Unsupported | -- | localsend is not installed |
| `trigger.toggle.idle-lock` | Stay Awake | Native | Display > Stay awake | switch; reads `omarchy-toggle-idle status`. Needs swayidle in autostart.conf to consult the flag |
| `trigger.toggle.notifications` | Notifications | Shade | shade > Silent tile | already a shade control; not repeated |
| `trigger.toggle.crash-capture` | Crash Capture | Native | Sound & notifications > Crash capture | switch; negative-polarity flag `crash-capture-off` |
| `trigger.toggle.screensaver` | Screensaver | Unsupported | -- | the `screensaver-off` flag gates Omarchy's idle screensaver; the phone's swayidle blanks the panel instead |
| `trigger.toggle.nightlight` | Nightlight | Native | Display > Night light | switch; needs a wlsunset-backed `moarchy-toggle-nightlight` keeping the `--status` JSON shape |
| `trigger.toggle.top-bar` | Menu Bar | Native | Appearance > Status bar > Show status bar | switch; `omarchy-toggle bar-off` + `syncHidden()`, NOT today's shell-killing `moarchy-toggle-bar` |
| `trigger.toggle.battery-percentage` | Battery Percentage | Native | Appearance > Status bar > Battery percentage | upstream targets a desktop-bar widget we never instantiate; new flag read by Bar.qml |
| `trigger.toggle.workspace-layout` | Workspace Layout | Unsupported | -- | `omarchy-hyprland-workspace-layout-toggle` switches Hyprland dwindle/master |
| `trigger.toggle.window-gaps` | Window Gaps | Unsupported | -- | Hyprland-only; one app per workspace means gaps only inset a single fullscreen window |
| `trigger.toggle.one-window-ratio` | 1-Window Ratio | Unsupported | -- | Hyprland-only and meaningless at 360px |
| `trigger.tests.network-speedtest` | Network Speed Test | Bridged | Tools > Speed tests | `omarchy-shell shell summon omarchy.speedtest` |
| `trigger.tests.disk-speedtest` | Disk Speed Test | Bridged | Tools > Speed tests | `omarchy-shell shell summon omarchy.disk-speedtest` |

## Style (21)

Native 7 · Bridged 6 · Unsupported 8

| id | label | class | lands at | note |
| --- | --- | --- | --- | --- |
| `style` | Style | Native | Appearance |  |
| `style.theme` | Theme | Native | Appearance > Theme | `moarchy.themes` with `returnTo` |
| `style.background` | Background | Native | Appearance > Wallpaper | native 2-up grid; the vendored image-selector is a 300-unit desktop card with no tap-outside dismiss |
| `style.unlock` | Unlock | Unsupported | -- | plymouth is not installed; the phone boots u-boot from SD with no plymouth stage |
| `style.font` | Font | Native | Appearance > Font | provider list from `omarchy-font-list` / `-current` / `-set` |
| `style.bar` | Menu Bar | Native | Appearance > Status bar |  |
| `style.bar.position` | Position | Unsupported | -- | `moarchy.bar` declares `readonly property string position: "top"` |
| `style.bar.transparency` | Transparency | Unsupported | -- | `omarchy-bar transparent` reloads the shell config, and the reload leaves upstream's `omarchy.bar` drawing in place of the phone bar; the row was removed rather than repaired |
| `style.hyprland` | Hyprland | Unsupported | -- | edits `~/.config/hypr/looknfeel.lua`; Hyprland cannot run here |
| `style.screensaver` | Screensaver | Unsupported | -- | nothing on this phone renders the art: About Omarchy is a page of rows now (settings.md N) and `omarchy-screensaver` needs ttfx, which has no aarch64 build |
| `style.about` | About | Unsupported | -- | nothing on this phone renders the art: About Omarchy is a page of rows now (settings.md N) and `omarchy-screensaver` needs ttfx, which has no aarch64 build |
| `style.bar.position.top` | Top | Unsupported | -- | the bar is hard-coded to the top |
| `style.bar.position.bottom` | Bottom | Unsupported | -- | the gesture strip owns the bottom edge |
| `style.bar.position.left` | Left | Unsupported | -- | the back-gesture band owns the left edge |
| `style.bar.position.right` | Right | Unsupported | -- | the bar is hard-coded to the top |
| `style.about.text` | Edit Text | Unsupported | -- | nothing on this phone renders the art: About Omarchy is a page of rows now (settings.md N) and `omarchy-screensaver` needs ttfx, which has no aarch64 build |
| `style.about.image` | Set From Image | Unsupported | -- | nothing on this phone renders the art: About Omarchy is a page of rows now (settings.md N) and `omarchy-screensaver` needs ttfx, which has no aarch64 build |
| `style.about.default` | Restore Default | Unsupported | -- | nothing on this phone renders the art: About Omarchy is a page of rows now (settings.md N) and `omarchy-screensaver` needs ttfx, which has no aarch64 build |
| `style.screensaver.text` | Edit Text | Unsupported | -- | nothing on this phone renders the art: About Omarchy is a page of rows now (settings.md N) and `omarchy-screensaver` needs ttfx, which has no aarch64 build |
| `style.screensaver.image` | Set From Image | Unsupported | -- | nothing on this phone renders the art: About Omarchy is a page of rows now (settings.md N) and `omarchy-screensaver` needs ttfx, which has no aarch64 build |
| `style.screensaver.default` | Restore Default | Unsupported | -- | nothing on this phone renders the art: About Omarchy is a page of rows now (settings.md N) and `omarchy-screensaver` needs ttfx, which has no aarch64 build |

## Setup (62)

Native 25 · Bridged 14 · Unsupported 23

| id | label | class | lands at | note |
| --- | --- | --- | --- | --- |
| `setup` | Setup | Native | dissolved: Network, Apps & defaults, Security, Shell & plugins |  |
| `setup.monitors` | Monitors | Unsupported | -- | edits `~/.config/hypr/monitors.lua`; the single output is set in `default/sway/pinephone.conf` |
| `setup.keybindings` | Keybindings | Unsupported | -- | guard `[[ -f ~/.config/hypr/bindings.lua ]]` is false; bindings live in `default/sway/bindings.conf` |
| `setup.input` | Input | Unsupported | -- | guard `[[ -f ~/.config/hypr/input.lua ]]` is false; input lives in `default/sway/input.conf` |
| `setup.network` | Network | Native | Network & internet |  |
| `setup.network.dns` | DNS | Native | Network & internet > Private DNS | radio group on `omarchy-dns` |
| `setup.network.dns.dhcp` | DHCP | Native | Network > Private DNS |  |
| `setup.network.dns.cloudflare` | Cloudflare | Native | Network > Private DNS |  |
| `setup.network.dns.google` | Google | Native | Network > Private DNS |  |
| `setup.network.dns.custom` | Custom | Bridged | Network > Private DNS | bridged write inside a native radio group; the tick still comes from `omarchy-dns` |
| `setup.network.qr` | QR Code | Bridged | Network & internet > Wi-Fi QR code | `omarchy-shell shell summon omarchy.wifiqr`; upstream `when` kept |
| `setup.default` | Defaults | Native | Apps & defaults > Default apps |  |
| `setup.default.agent` | Agent | Native | Default apps > AI agent | we add `when: omarchy-cmd-present <bin>`; upstream ships these unguarded |
| `setup.default.agent.claude` | Claude | Native | Default apps > AI agent | radio row; presence-guarded, so the page hides when no agent is installed |
| `setup.default.agent.codex` | Codex | Native | Default apps > AI agent | radio row; presence-guarded, so the page hides when no agent is installed |
| `setup.default.agent.copilot` | Copilot | Native | Default apps > AI agent | radio row; presence-guarded, so the page hides when no agent is installed |
| `setup.default.agent.crush` | Crush | Native | Default apps > AI agent | radio row; presence-guarded, so the page hides when no agent is installed |
| `setup.default.agent.gemini` | Gemini | Native | Default apps > AI agent | radio row; presence-guarded, so the page hides when no agent is installed |
| `setup.default.agent.grok` | Grok | Native | Default apps > AI agent | radio row; presence-guarded, so the page hides when no agent is installed |
| `setup.default.agent.omp` | omp | Native | Default apps > AI agent | radio row; presence-guarded, so the page hides when no agent is installed |
| `setup.default.agent.opencode` | OpenCode | Native | Default apps > AI agent | radio row; presence-guarded, so the page hides when no agent is installed |
| `setup.default.agent.pi` | Pi | Native | Default apps > AI agent | radio row; presence-guarded, so the page hides when no agent is installed |
| `setup.default.browser` | Browser | Native | Default apps > Browser | empty on a base install, so the parent row hides |
| `setup.default.browser.chromium` | Chromium | Bridged | Default apps > Browser | extras-only, aarch64-verified; presence-guarded |
| `setup.default.browser.chrome` | Chrome | Unsupported | -- | x86_64-only |
| `setup.default.browser.brave` | Brave | Unsupported | -- | x86_64-only |
| `setup.default.browser.brave-origin` | Brave Origin | Unsupported | -- | x86_64-only |
| `setup.default.browser.edge` | Edge | Unsupported | -- | x86_64-only |
| `setup.default.browser.firefox` | Firefox | Bridged | Default apps > Browser | firefox has an aarch64 build in Arch Linux ARM; hidden until installed |
| `setup.default.browser.zen` | Zen | Unsupported | -- | x86_64-only |
| `setup.default.terminal` | Terminal | Native | Default apps > Terminal |  |
| `setup.default.terminal.alacritty` | Alacritty | Native | Default apps > Terminal | installed |
| `setup.default.terminal.foot` | Foot | Native | Default apps > Terminal | installed |
| `setup.default.terminal.ghostty` | Ghostty | Unsupported | -- | no aarch64 build, so the `omarchy-cmd-present` guard can never pass |
| `setup.default.terminal.kitty` | Kitty | Bridged | Default apps > Terminal | aarch64-available; hidden until installed |
| `setup.default.editor` | Editor | Native | Default apps > Editor |  |
| `setup.default.editor.neovim` | Neovim | Native | Default apps > Editor | installed; reads and writes `nvim` |
| `setup.default.editor.vscode` | VSCode | Unsupported | -- | x86_64-only |
| `setup.default.editor.cursor` | Cursor | Unsupported | -- | x86_64-only |
| `setup.default.editor.zed` | Zed | Unsupported | -- | no aarch64 zed package. Read/write asymmetry: `checked` reads `zeditor`, the action writes `zed` -- modelled as readValue/value |
| `setup.default.editor.sublime` | Sublime Text | Unsupported | -- | x86_64-only |
| `setup.default.editor.helix` | Helix | Bridged | Default apps > Editor | aarch64-available; hidden until installed |
| `setup.default.editor.vim` | Vim | Bridged | Default apps > Editor | aarch64-available; hidden until installed |
| `setup.default.editor.emacs` | Emacs | Unsupported | -- | x86_64-only |
| `setup.plugin` | Plugins | Native | Shell & plugins > Plugins |  |
| `setup.plugin.enable` | Enable Plugin | Native | Shell & plugins > Plugins | a switch per plugin, built at open; the page covers this id, not a row |
| `setup.plugin.disable` | Disable Plugin | Native | Shell & plugins > Plugins | the same switch, the other way; two launches of the select box became one list |
| `setup.plugin.add` | Add Plugin | Bridged | Shell & plugins > Plugins | TUI; prompts for a repo URL |
| `setup.plugin.clone` | Clone Plugin | Bridged | Shell & plugins > Plugins | `omarchy-menu-select` |
| `setup.plugin.remove` | Remove Plugin | Bridged | Shell & plugins > Plugins | hidden while `~/.config/omarchy/plugins` is empty, which it now is -- the phone UI is packaged, and `omarchy-plugin-remove` only deletes inside that directory. Confirm sheet kept for a user-cloned plugin |
| `setup.security` | Security | Native | Security |  |
| `setup.config` | Config | Unsupported | -- | every child unsupported |
| `setup.security.fingerprint` | Fingerprint | Unsupported | -- | `omarchy-hw-fingerprint` is false; fprintd is not installed |
| `setup.security.fido2` | Fido2 | Unsupported | -- | pam-u2f is not installed |
| `setup.security.sshd` | SSHD | Bridged | Security > Remote access (on) | openssh is installed; this is the path the selftest itself arrives on |
| `setup.security.passwordless-sudo` | Passwordless Sudo | Bridged | Security > Passwordless sudo |  |
| `setup.security.sudoless-docker` | Sudoless Docker | Unsupported | -- | docker is not installed |
| `setup.config.hyprland` | Hyprland | Unsupported | -- | edits `~/.config/hypr/hyprland.lua`; Hyprland cannot run here |
| `setup.config.hyprsunset` | Hyprsunset | Unsupported | -- | hyprsunset is Hyprland-only; night light is wlsunset here |
| `setup.config.xcompose` | XCompose | Unsupported | -- | `omarchy-restart-xcompose` restarts fcitx5, which `default/sway/autostart.conf` deliberately drops |
| `setup.direct-boot` | Direct Boot | Unsupported | -- | limine is not the bootloader; the phone boots u-boot from SD |
| `setup.reset` | Reset Computer | Unsupported | -- | guard `findmnt -no FSTYPE / == btrfs` is false (ext4); factory reset needs Snapper |

## Install (87)

Native 6 · Bridged 19 · Unsupported 62

| id | label | class | lands at | note |
| --- | --- | --- | --- | --- |
| `install` | Install | Native | Apps & defaults > Packages | merged with `remove` |
| `install.package` | Package | Bridged | Packages > Install package | fzf + pacman; both installed |
| `install.aur` | AUR | Bridged | Packages > Install from AUR | yay is built for aarch64 from the `[aur.yay]` pin and installed from the `[moarchy]` repo |
| `install.webapp` | Web App | Bridged | Apps & defaults > Web apps > Add | creates a .desktop running our `omarchy-launch-webapp` shim |
| `install.tui` | TUI | Bridged | Apps & defaults > Terminal apps > Add |  |
| `install.style` | Style | Native | Appearance > Get more |  |
| `install.style.theme` | Theme | Bridged | Appearance > Get more | git clone of a theme |
| `install.style.background` | Background | Bridged | Appearance > Get more |  |
| `install.style.font` | Font | Native | Appearance > Get more > Install a font |  |
| `install.style.font.cascadia` | Cascadia Mono | Bridged | Appearance > Get more > Install a font | `any`-arch package |
| `install.style.font.meslo` | Meslo LG Mono | Bridged | Appearance > Get more > Install a font | `any`-arch package |
| `install.style.font.fira` | Fira Code | Bridged | Appearance > Get more > Install a font | `any`-arch package |
| `install.style.font.victor` | Victor Code | Bridged | Appearance > Get more > Install a font | `any`-arch package |
| `install.style.font.bitstream` | Bitstream Vera Mono | Bridged | Appearance > Get more > Install a font | `any`-arch package |
| `install.style.font.iosevka` | Iosevka | Bridged | Appearance > Get more > Install a font | `any`-arch package |
| `install.service` | Service | Unsupported | -- | every child unsupported |
| `install.development` | Development | Unsupported | -- | every child unsupported; `omarchy-install-dev-env` drives mise, which is not installed |
| `install.editor` | Editor | Native | Packages > More software | Vim and Helix survive |
| `install.terminal` | Terminal | Native | Packages > More software | Ghostty and Kitty survive |
| `install.browser` | Browser | Native | Packages > More software | only Firefox survives |
| `install.ai` | AI | Unsupported | -- | every child unsupported |
| `install.gaming` | Gaming | Unsupported | -- | every child unsupported |
| `install.windows` | Windows | Unsupported | -- | `omarchy-windows-vm` needs x86 KVM |
| `install.preinstalls` | Preinstalls | Unsupported | -- | the preinstall set is Omarchy's desktop apps; none are in the phone's package set |
| `install.browser.chrome` | Chrome | Unsupported | -- | x86_64-only |
| `install.browser.edge` | Edge | Unsupported | -- | x86_64-only |
| `install.browser.brave` | Brave | Unsupported | -- | x86_64-only |
| `install.browser.brave-origin` | Brave Origin | Unsupported | -- | x86_64-only |
| `install.browser.firefox` | Firefox | Bridged | Packages > More software | firefox is in Arch Linux ARM for aarch64, merely not installed |
| `install.browser.zen` | Zen | Unsupported | -- | x86_64-only |
| `install.service.1password` | 1Password | Unsupported | -- | x86_64-only |
| `install.service.dropbox` | Dropbox | Unsupported | -- | x86_64-only |
| `install.service.spotify` | Spotify | Unsupported | -- | x86_64-only |
| `install.service.signal` | Signal | Bridged | Packages > More software | signal-desktop is aarch64-verified; in moarchy-meta's not-installed-by-default list |
| `install.service.tailscale` | Tailscale | Unsupported | -- | x86_64-only |
| `install.service.nordvpn` | NordVPN | Unsupported | -- | x86_64-only |
| `install.service.once` | ONCE | Unsupported | -- | x86_64-only |
| `install.service.bitwarden` | Bitwarden | Unsupported | -- | x86_64-only |
| `install.service.chromium-account` | Chromium Account | Unsupported | -- | x86_64-only |
| `install.editor.vscode` | VSCode | Unsupported | -- | x86_64-only |
| `install.editor.cursor` | Cursor | Unsupported | -- | x86_64-only |
| `install.editor.zed` | Zed | Unsupported | -- | x86_64-only |
| `install.editor.sublime` | Sublime Text | Unsupported | -- | x86_64-only |
| `install.editor.helix` | Helix | Bridged | Packages > More software | helix is Rust, aarch64 in ALARM |
| `install.editor.vim` | Vim | Bridged | Packages > More software | vim is aarch64 in ALARM |
| `install.editor.emacs` | Emacs | Unsupported | -- | x86_64-only |
| `install.terminal.alacritty` | Alacritty | Bridged | Packages > More software | always hidden -- alacritty is installed |
| `install.terminal.foot` | Foot | Bridged | Packages > More software | always hidden -- foot is installed |
| `install.terminal.ghostty` | Ghostty | Unsupported | -- | `pacman -Si ghostty` finds nothing for aarch64 and `omarchy-pkg-add` has no AUR fallback, so the row could only fail |
| `install.terminal.kitty` | Kitty | Bridged | Packages > More software | aarch64-available |
| `install.ai.chatgpt` | ChatGPT Desktop | Unsupported | -- | x86_64-only |
| `install.ai.dictation` | Dictation | Unsupported | -- | x86_64-only |
| `install.ai.grok-bot` | Grok Bot | Unsupported | -- | x86_64-only |
| `install.ai.lm-studio` | LM Studio | Unsupported | -- | x86_64-only |
| `install.ai.ollama` | Ollama | Unsupported | -- | x86_64-only |
| `install.gaming.steam` | Steam | Unsupported | -- | x86_64-only, or needs flatpak/wine/lib32, none of which are installed |
| `install.gaming.retroarch` | RetroArch | Unsupported | -- | x86_64-only, or needs flatpak/wine/lib32, none of which are installed |
| `install.gaming.minecraft` | Minecraft | Unsupported | -- | x86_64-only, or needs flatpak/wine/lib32, none of which are installed |
| `install.gaming.geforce-now` | NVIDIA GeForce NOW | Unsupported | -- | x86_64-only, or needs flatpak/wine/lib32, none of which are installed |
| `install.gaming.xbox-cloud` | Xbox Cloud Gaming | Unsupported | -- | x86_64-only, or needs flatpak/wine/lib32, none of which are installed |
| `install.gaming.xbox-controllers` | Xbox Controllers | Unsupported | -- | x86_64-only, or needs flatpak/wine/lib32, none of which are installed |
| `install.gaming.battlenet` | Battle.net | Unsupported | -- | x86_64-only, or needs flatpak/wine/lib32, none of which are installed |
| `install.gaming.lutris` | Lutris | Unsupported | -- | x86_64-only, or needs flatpak/wine/lib32, none of which are installed |
| `install.gaming.heroic` | Heroic (Epic Games) | Unsupported | -- | x86_64-only, or needs flatpak/wine/lib32, none of which are installed |
| `install.gaming.retro-launcher` | RetroArch Game Launcher | Unsupported | -- | x86_64-only, or needs flatpak/wine/lib32, none of which are installed |
| `install.development.rails` | Ruby on Rails | Unsupported | -- | `omarchy-install-dev-env` drives mise, which is not installed |
| `install.development.docker-dbs` | Docker DB | Unsupported | -- | `omarchy-install-dev-env` drives mise, which is not installed |
| `install.development.javascript` | JavaScript | Unsupported | -- | `omarchy-install-dev-env` drives mise, which is not installed |
| `install.development.go` | Go | Unsupported | -- | `omarchy-install-dev-env` drives mise, which is not installed |
| `install.development.php` | PHP | Unsupported | -- | `omarchy-install-dev-env` drives mise, which is not installed |
| `install.development.python` | Python | Unsupported | -- | `omarchy-install-dev-env` drives mise, which is not installed |
| `install.development.elixir` | Elixir | Unsupported | -- | `omarchy-install-dev-env` drives mise, which is not installed |
| `install.development.zig` | Zig | Unsupported | -- | `omarchy-install-dev-env` drives mise, which is not installed |
| `install.development.rust` | Rust | Unsupported | -- | `omarchy-install-dev-env` drives mise, which is not installed |
| `install.development.java` | Java | Unsupported | -- | `omarchy-install-dev-env` drives mise, which is not installed |
| `install.development.dotnet` | .NET | Unsupported | -- | `omarchy-install-dev-env` drives mise, which is not installed |
| `install.development.ocaml` | OCaml | Unsupported | -- | `omarchy-install-dev-env` drives mise, which is not installed |
| `install.development.clojure` | Clojure | Unsupported | -- | `omarchy-install-dev-env` drives mise, which is not installed |
| `install.development.scala` | Scala | Unsupported | -- | `omarchy-install-dev-env` drives mise, which is not installed |
| `install.development.javascript.node` | Node.js | Unsupported | -- | `omarchy-install-dev-env` drives mise, which is not installed |
| `install.development.javascript.bun` | Bun | Unsupported | -- | `omarchy-install-dev-env` drives mise, which is not installed |
| `install.development.javascript.deno` | Deno | Unsupported | -- | `omarchy-install-dev-env` drives mise, which is not installed |
| `install.development.php.php` | PHP | Unsupported | -- | `omarchy-install-dev-env` drives mise, which is not installed |
| `install.development.php.laravel` | Laravel | Unsupported | -- | `omarchy-install-dev-env` drives mise, which is not installed |
| `install.development.php.symfony` | Symfony | Unsupported | -- | `omarchy-install-dev-env` drives mise, which is not installed |
| `install.development.elixir.elixir` | Elixir | Unsupported | -- | `omarchy-install-dev-env` drives mise, which is not installed |
| `install.development.elixir.phoenix` | Phoenix | Unsupported | -- | `omarchy-install-dev-env` drives mise, which is not installed |

## Remove (55)

Native 3 · Bridged 6 · Unsupported 46

| id | label | class | lands at | note |
| --- | --- | --- | --- | --- |
| `remove` | Remove | Native | Apps & defaults > Packages | merged with `install` |
| `remove.package` | Package | Bridged | Packages > Remove package |  |
| `remove.webapp` | Web App | Bridged | Apps & defaults > Web apps > Remove | upstream `when` kept |
| `remove.tui` | TUI | Bridged | Apps & defaults > Terminal apps > Remove | upstream `when` kept |
| `remove.development` | Development | Unsupported | -- | every child unsupported |
| `remove.theme` | Theme | Bridged | Appearance > Get more > Remove a theme | `omarchy-menu-select` |
| `remove.browser` | Browser | Native | Packages > More software | only Firefox survives |
| `remove.dictation` | Dictation | Unsupported | -- | voxtype is x86_64-only and never installed |
| `remove.gaming` | Gaming | Unsupported | -- | every child unsupported |
| `remove.service` | Services | Unsupported | -- | every child unsupported except Signal |
| `remove.windows` | Windows | Unsupported | -- | no windows-vm to remove |
| `remove.preinstalls` | Preinstalls | Unsupported | -- | the preinstalls were never installed |
| `remove.security` | Security | Native | Security | only SSHD survives |
| `remove.security.fingerprint` | Fingerprint | Unsupported | -- | fprintd is not installed |
| `remove.security.fido2` | Fido2 | Unsupported | -- | pam-u2f is not installed |
| `remove.security.sshd` | SSHD | Bridged | Security > Remote access (off) |  |
| `remove.security.sudoless-docker` | Sudoless Docker | Unsupported | -- | docker is not installed |
| `remove.browser.chrome` | Chrome | Unsupported | -- | never installable here (x86_64-only) |
| `remove.browser.edge` | Edge | Unsupported | -- | never installable here (x86_64-only) |
| `remove.browser.brave` | Brave | Unsupported | -- | never installable here (x86_64-only) |
| `remove.browser.brave-origin` | Brave Origin | Unsupported | -- | never installable here (x86_64-only) |
| `remove.browser.firefox` | Firefox | Bridged | Packages > More software | complement of `install.browser.firefox` |
| `remove.browser.zen` | Zen | Unsupported | -- | never installable here (x86_64-only) |
| `remove.service.dropbox` | Dropbox | Unsupported | -- | dropbox is x86_64-only |
| `remove.service.tailscale` | Tailscale | Unsupported | -- | tailscale is not installed |
| `remove.gaming.steam` | Steam | Unsupported | -- | never installable here |
| `remove.gaming.retroarch` | RetroArch | Unsupported | -- | never installable here |
| `remove.gaming.minecraft` | Minecraft | Unsupported | -- | never installable here |
| `remove.gaming.geforce-now` | NVIDIA GeForce NOW | Unsupported | -- | never installable here |
| `remove.gaming.xbox-cloud` | Xbox Cloud Gaming | Unsupported | -- | never installable here |
| `remove.gaming.xbox-controllers` | Xbox Controllers (󰂯) | Unsupported | -- | never installable here |
| `remove.gaming.battlenet` | Battle.net | Unsupported | -- | never installable here |
| `remove.gaming.lutris` | Lutris | Unsupported | -- | never installable here |
| `remove.gaming.heroic` | Heroic (Epic Games) | Unsupported | -- | never installable here |
| `remove.development.rails` | Ruby on Rails | Unsupported | -- | mise is not installed, so no dev env exists to remove |
| `remove.development.javascript` | JavaScript | Unsupported | -- | mise is not installed, so no dev env exists to remove |
| `remove.development.go` | Go | Unsupported | -- | mise is not installed, so no dev env exists to remove |
| `remove.development.php` | PHP | Unsupported | -- | mise is not installed, so no dev env exists to remove |
| `remove.development.python` | Python | Unsupported | -- | mise is not installed, so no dev env exists to remove |
| `remove.development.elixir` | Elixir | Unsupported | -- | mise is not installed, so no dev env exists to remove |
| `remove.development.zig` | Zig | Unsupported | -- | mise is not installed, so no dev env exists to remove |
| `remove.development.rust` | Rust | Unsupported | -- | mise is not installed, so no dev env exists to remove |
| `remove.development.java` | Java | Unsupported | -- | mise is not installed, so no dev env exists to remove |
| `remove.development.dotnet` | .NET | Unsupported | -- | mise is not installed, so no dev env exists to remove |
| `remove.development.ocaml` | OCaml | Unsupported | -- | mise is not installed, so no dev env exists to remove |
| `remove.development.clojure` | Clojure | Unsupported | -- | mise is not installed, so no dev env exists to remove |
| `remove.development.scala` | Scala | Unsupported | -- | mise is not installed, so no dev env exists to remove |
| `remove.development.javascript.node` | Node.js | Unsupported | -- | mise is not installed, so no dev env exists to remove |
| `remove.development.javascript.bun` | Bun | Unsupported | -- | mise is not installed, so no dev env exists to remove |
| `remove.development.javascript.deno` | Deno | Unsupported | -- | mise is not installed, so no dev env exists to remove |
| `remove.development.php.php` | PHP | Unsupported | -- | mise is not installed, so no dev env exists to remove |
| `remove.development.php.laravel` | Laravel | Unsupported | -- | mise is not installed, so no dev env exists to remove |
| `remove.development.php.symfony` | Symfony | Unsupported | -- | mise is not installed, so no dev env exists to remove |
| `remove.development.elixir.elixir` | Elixir | Unsupported | -- | mise is not installed, so no dev env exists to remove |
| `remove.development.elixir.phoenix` | Phoenix | Unsupported | -- | mise is not installed, so no dev env exists to remove |

## Update (28)

Native 6 · Bridged 8 · Unsupported 14

| id | label | class | lands at | note |
| --- | --- | --- | --- | --- |
| `update` | Update | Native | dissolved: System, Shell & plugins |  |
| `update.omarchy` | Omarchy | Unsupported | -- | `omarchy-update` needs pkgs.omarchy.org's aarch64 tree (404) and Snapper on btrfs |
| `update.channel` | Channel | Unsupported | -- | every child unsupported |
| `update.config` | Config | Native | Shell & plugins | only Tmux survives |
| `update.themes` | Extra Themes | Bridged | Appearance > Get more | upstream `when: omarchy-theme-extras` kept |
| `update.process` | Process | Native | Shell & plugins | only Shell survives |
| `update.hardware` | Hardware | Native | System > Restart hardware |  |
| `update.firmware` | Firmware | Unsupported | -- | fwupd is not installed and the PinePhone has no UEFI capsule path |
| `update.password` | Password | Native | dissolved: Security | only the user password survives |
| `update.timezone` | Timezone | Native | System > Date & time | region then city, two provider pages; the select box was a filter field over ~420 entries |
| `update.time` | Time | Bridged | System > Date & time |  |
| `update.channel.stable` | Stable | Unsupported | -- | a channel switch moves the vendored checkout off the pinned v4.0.2 that `pkgbuilds/omarchy-config/port-4x.patch` applies against |
| `update.channel.rc` | RC | Unsupported | -- | as `update.channel.stable` |
| `update.channel.edge` | Edge | Unsupported | -- | as `update.channel.stable` |
| `update.channel.dev` | Dev | Unsupported | -- | as `update.channel.stable` |
| `update.process.hyprsunset` | Hyprsunset | Unsupported | -- | hyprsunset is Hyprland-only |
| `update.process.shell` | Shell | Native | Shell & plugins > Restart shell | `moarchy-restart-shell` shadows `omarchy-restart-shell` on PATH |
| `update.config.hyprland` | Hyprland | Unsupported | -- | Hyprland cannot run here |
| `update.config.hyprsunset` | Hyprsunset | Unsupported | -- | hyprsunset is Hyprland-only |
| `update.config.plymouth` | Plymouth | Unsupported | -- | plymouth is not installed |
| `update.config.tmux` | Tmux | Bridged | Shell & plugins > Reset tmux config | tmux is installed |
| `update.config.shell` | Shell | Unsupported | -- | `omarchy-refresh-shell` rewrites shell.json from Omarchy's defaults, dropping `bar.id` and every moarchy.* plugin -- it succeeds, then restarts into the desktop bar with no drawer, shade or gestures |
| `update.hardware.audio` | Audio | Bridged | System > Restart hardware |  |
| `update.hardware.wifi` | Wi-Fi | Bridged | System > Restart hardware |  |
| `update.hardware.bluetooth` | Bluetooth | Bridged | System > Restart hardware |  |
| `update.hardware.trackpad` | Trackpad | Unsupported | -- | no touchpad; `omarchy-restart-trackpad` reloads Hyprland input |
| `update.password.drive` | Drive Encryption | Unsupported | -- | the SD/eMMC root is not LUKS, so cryptsetup has no volume to re-key |
| `update.password.user` | User | Bridged | Security > Change password | `sudo passwd "$USER"` in a TUI -- an E2 exception. The account ships with a *locked* password, so upstream's bare `passwd` has nothing to authenticate against and fails on its first question; under sudo it sets one outright |

---

## Keeping it honest

The table drifts the moment a row moves, so it is checked rather than trusted.
`Pages.js` emits its own coverage map over IPC, and the selftest diffs that three
ways: against this file, against the upstream JSONC (every id, exactly once), and
against the rendered rows (nothing classified Unsupported is reachable).

```
omarchy-shell settings coverage | cut -f1 | sort
```

See `docs/settings.md` section G for the acceptance criteria this satisfies.
