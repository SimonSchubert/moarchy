// Every screen in Settings, as data.
//
// ---------------------------------------------------------------------------
// Why a model rather than a plugin per screen
// ---------------------------------------------------------------------------
// A new plugin costs a manifest, an id in the hardcoded tuple in
// install/config.sh, two more lists in bin/moarchy-selftest, and ~350
// lines of PanelWindow/header/ListView that is byte-identical to the last one.
// Fifteen screens that way is four thousand lines, ninety percent of it copied.
// Here a screen is an entry in PAGES and a row is an object.
//
// ---------------------------------------------------------------------------
// Why the tree is not upstream's
// ---------------------------------------------------------------------------
// Upstream's root is verb-shaped -- Trigger, Install, Remove, Update, Setup,
// Style -- because it is a dmenu you type into, where "install" then "fir" is
// two words. A phone has no type-ahead at the root, it has a thumb. So the root
// is noun-shaped, the way every phone settings app is: you go to the thing, not
// to the verb. docs/settings.md records the four departures and why.
//
// ---------------------------------------------------------------------------
// Row types
// ---------------------------------------------------------------------------
//   nav      pushes `page`. A second line comes from `detail` (prose) or
//            `detailCmd` (a shell expression the guard batch answers).
//   plugin   hands off to another shell plugin, with returnTo set.
//   switch   `read` prints the state; `on`/`off` set it. `invert` for the
//            negative-polarity flags, where the file existing means OFF.
//   choice   a radio row. The page's `reader` says which is current; the row's
//            `readValue` is what to compare (defaults to `value`), and `write`
//            is what to run. Those are separate fields because upstream has a
//            case where they differ -- setup.default.editor.zed reads
//            "zeditor" and writes "zed".
//   action   runs `run`. `launch` picks how: "tui" a terminal at TUI size,
//            "menu" a vendored picker, "none" straight to execDetached,
//            "inline" in place with the page re-read afterwards. Only "inline"
//            is a distinction the screen makes now -- nothing takes Settings
//            off screen any more (docs/gestures.md K8). `back: true`
//            pops one page when it is done. `argsFrom` names `input` rows
//            whose text is appended, shell-quoted, in order; `requires` names
//            one that must be non-empty or the row is dimmed and inert.
//   link     a URL, through the omarchy-launch-webapp shim.
//   info     read-only text.
//   input    a text field. `placeholder` is the empty state, `numeric` asks
//            for the digits-only keyboard. Its text is not persisted and does
//            not outlive the page.
//
// A page may build rows at open instead of declaring them: `provider.list`
// turns one value per line into `choice` rows, `provider.json` takes a JSON
// array of whole rows, and `before: true` puts those above the declared ones
// rather than replacing them.
//
// Any row may carry `when`, copied verbatim from omarchy-menu.jsonc so the
// guard that upstream uses is the guard we use.
//
// Any row may also carry `keywords`: extra words the drawer's search matches on
// (docs/settings.md section O), for the cases where the word a person types is
// not in the label -- "timer" for Reminders, "capture" for Screenshot. It is a
// handful of rows and not a discipline; a label that says what it is needs none.
//
// `covers` maps an upstream menu id to its class, N(ative) or B(ridged). It is
// what `omarchy-shell settings coverage` emits, which is what makes the table
// in docs/menu-coverage.md checkable rather than aspirational.
//
// ---------------------------------------------------------------------------
// Icons are literal characters, never \uXXXX
// ---------------------------------------------------------------------------
// Every icon in omarchy-menu.jsonc is a Nerd Font codepoint above U+FFFF, and
// a QML \u escape takes exactly four hex digits -- so "1" is U+F043
// followed by a literal "1", which still resolves to a real glyph and still
// draws the wrong picture. The selftest asserts every icon literal here is one
// character.
.pragma library

// Ids satisfied outside this stack. `apps` is the app drawer, which already is
// upstream's apps provider; repeating it inside Settings would be the mistake
// the drawer's own comment warns about.
var EXTERNAL = {
    "apps": { cls: "N", where: "moarchy.drawer" }
};

// Already a shade control. Recorded so coverage is complete, never rendered.
var SHADE = {
    "trigger.toggle.notifications": "shade > Silent tile"
};

var PAGES = {

// --------------------------------------------------------------------- root
"root": { title: "Settings", rows: [
  { id: "net", type: "nav", page: "net", glyph: "󰛳", label: "Network & internet",
    detailCmd: "omarchy-dns", covers: { "setup": "N", "setup.network": "N" } },
  { id: "display", type: "nav", page: "display", glyph: "󰍹", label: "Display",
    covers: { "trigger.toggle": "N" } },
  { id: "sound", type: "nav", page: "sound", glyph: "", label: "Sound & notifications" },
  { id: "appearance", type: "nav", page: "appearance", glyph: "", label: "Appearance",
    detailCmd: "omarchy-theme-current", covers: { "style": "N" } },
  { id: "apps", type: "nav", page: "apps", glyph: "󰀻", label: "Apps & defaults",
    covers: { "install": "N", "remove": "N" } },
  { id: "shell", type: "nav", page: "shell", glyph: "󰍜", label: "Shell & plugins" },
  { id: "security", type: "nav", page: "security", glyph: "", label: "Security",
    covers: { "setup.security": "N", "remove.security": "N" } },
  { id: "tools", type: "nav", page: "tools", glyph: "󱓞", label: "Tools",
    covers: { "trigger": "N" } },
  { id: "system", type: "nav", page: "system", glyph: "", label: "System",
    covers: { "system": "N", "update": "N" } },
  { id: "about", type: "nav", page: "about", glyph: "", label: "About phone",
    detailCmd: "omarchy-version", covers: { "learn": "N" } }
]},

// ------------------------------------------------------------------ network
"net": { title: "Network & internet", rows: [
  { id: "dns", type: "nav", page: "net.dns", glyph: "󰇖", label: "Private DNS",
    detailCmd: "omarchy-dns", covers: { "setup.network.dns": "N" } },
  // The shade toggles the radios. Neither of these has an upstream id because
  // upstream has no equivalent: a desktop joins a network from a bar applet.
  //
  // Wi-Fi opens moarchy.wifi, the same screen the shade's tile opens on a long
  // press (docs/shade.md S6b). It used to run nmtui-connect in a TUI terminal,
  // which fits the screen and could not be operated -- but for a narrower
  // reason than "a TUI cannot be touched". foot turns a tap into a left click,
  // and nmtui simply never asks for mouse reporting, so the click went
  // nowhere. TUIs that do ask are fine by touch, which is not the same as
  // fine on a phone; see the bluetooth row.
  //
  // returnTo brings Back here rather than dropping you on the home screen.
  { id: "wifi", type: "action", glyph: "󱚾", label: "Wi-Fi networks",
    keywords: "wlan wireless internet connect",
    // One field of omarchy-network-status, which answers a whole record (I6).
    // A script and not an inline pipeline: E3 resolves the first word of every
    // row's command on PATH, and an awk one-liner puts `else` there.
    detailCmd: "moarchy-network-name",
    run: "omarchy-shell shell summon moarchy.wifi '{\"returnTo\":\"moarchy.settings\",\"page\":\"net\"}'",
    launch: "none" },
  // Bluetooth is a screen too now, the same pairing as Wi-Fi: this row and the
  // shade's long press open moarchy.bluetooth (docs/shade.md S6c, S6d).
  //
  // It was `bluetui`, and bluetui was never the failure nmtui was -- it enables
  // mouse reporting, so foot's tap-to-click reaches it, and its own bindings
  // (s scan, Enter connect, j/k) are all keys the on-screen keyboard has, tab
  // and arrows included. It was still a list whose rows are one terminal line,
  // ~17 logical px against style.md E1's 44, in a window with its own
  // workspace and its own palette. Not impala's Bluetooth half either -- and
  // for Wi-Fi impala was wrong outright, being an iwd client on a phone
  // running NetworkManager with iwd.service disabled but D-Bus activatable, so
  // it would have started iwd to fight NetworkManager for wlan0.
  { id: "bluetooth", type: "action", glyph: "󰂯", label: "Bluetooth devices",
    keywords: "pair headset",
    run: "omarchy-shell shell summon moarchy.bluetooth '{\"returnTo\":\"moarchy.settings\",\"page\":\"net\"}'",
    launch: "none" },
  { id: "qr", type: "action", glyph: "󰐲", label: "Wi-Fi QR code",
    when: "[[ $(omarchy-network-status) == wifi* ]]",
    run: "omarchy-shell shell summon omarchy.wifiqr", launch: "none",
    covers: { "setup.network.qr": "B" } }
]},

"net.dns": { title: "Private DNS", reader: "omarchy-dns", rows: [
  { id: "dhcp", type: "choice", label: "Automatic (DHCP)", value: "DHCP",
    write: "omarchy-dns DHCP", covers: { "setup.network.dns.dhcp": "N" } },
  { id: "cloudflare", type: "choice", label: "Cloudflare", value: "Cloudflare",
    write: "omarchy-dns Cloudflare", covers: { "setup.network.dns.cloudflare": "N" } },
  { id: "google", type: "choice", label: "Google", value: "Google",
    write: "omarchy-dns Google", covers: { "setup.network.dns.google": "N" } },
  // A bridged write inside a native radio: the tick still comes from
  // omarchy-dns, only the prompt for the address leaves the UI.
  { id: "custom", type: "choice", label: "Custom...", value: "Custom",
    write: "omarchy-launch-floating-terminal-with-presentation 'omarchy-dns Custom'",
    launch: "tui", covers: { "setup.network.dns.custom": "B" } }
]},

// ------------------------------------------------------------------ display
"display": { title: "Display", rows: [
  { id: "nightlight", type: "switch", glyph: "󰔎", label: "Night light",
    read: "moarchy-toggle-nightlight --status | jq -r .enabled",
    on: "moarchy-toggle-nightlight on",
    off: "moarchy-toggle-nightlight off",
    covers: { "trigger.toggle.nightlight": "N" } },
  { id: "stayawake", type: "switch", glyph: "󰅶", label: "Stay awake",
    detail: "Keep the screen on",
    read: "omarchy-toggle-idle status | jq -r .enabled",
    on: "omarchy-toggle-idle stay-awake",
    off: "omarchy-toggle-idle allow-idle",
    covers: { "trigger.toggle.idle-lock": "N" } }
]},

// -------------------------------------------------------------------- sound
"sound": { title: "Sound & notifications", rows: [
  // Two screens, not a mixer. This was `wiremix` in a terminal, which on this
  // panel mapped its window and drew nothing but a truncated tab strip -- no
  // device list, no sliders -- and it was the only audio UI the phone had.
  //
  // Routing only. Volume, like brightness and the radios, belongs to the shade
  // (H1), and a slider here would be the repetition that section exists to stop.
  // What the shade has no room for is *which* device, and on a phone that is the
  // earpiece against the speaker against a headset against a paired sink.
  { id: "output", type: "nav", page: "sound.output", glyph: "󰓃",
    label: "Output device", detailCmd: "moarchy-audio output-name" },
  { id: "input", type: "nav", page: "sound.input", glyph: "󰍬",
    label: "Input device", detailCmd: "moarchy-audio input-name" },
  { id: "crashcapture", type: "switch", glyph: "󱚡", label: "Crash capture",
    detail: "Keep a log when an app dies",
    read: "omarchy-toggle-enabled crash-capture-off && echo true || echo false",
    invert: true,
    on: "omarchy-toggle crash-capture-off off",
    off: "omarchy-toggle crash-capture-off on",
    covers: { "trigger.toggle.crash-capture": "N" } }
]},

// provider.json rather than provider.list: a row carries the command that
// selects it, because the label a person reads (PipeWire's Description, "Built-in
// Audio Internal speaker") and the handle pactl takes back are different strings.
// One value per line cannot hold both, which is the same reason the reminders
// list is json.
"sound.output": { title: "Output device",
  reader: "moarchy-audio current-output",
  provider: { json: "moarchy-audio outputs" },
  rows: [] },

"sound.input": { title: "Input device",
  reader: "moarchy-audio current-input",
  provider: { json: "moarchy-audio inputs" },
  rows: [] },

// --------------------------------------------------------------- appearance
"appearance": { title: "Appearance", rows: [
  { id: "theme", type: "plugin", plugin: "moarchy.themes", glyph: "󰸌",
    label: "Theme", detailCmd: "omarchy-theme-current",
    covers: { "style.theme": "N" } },
  { id: "background", type: "nav", page: "appearance.background", glyph: "",
    label: "Wallpaper", detailCmd: "basename \"$(omarchy-theme-bg-current)\"",
    covers: { "style.background": "N" } },
  { id: "font", type: "nav", page: "appearance.font", glyph: "", label: "Font",
    detailCmd: "omarchy-font-current", covers: { "style.font": "N" } },
  { id: "bar", type: "nav", page: "appearance.bar", glyph: "󰍜", label: "Status bar",
    covers: { "style.bar": "N" } },
  { id: "more", type: "nav", page: "appearance.more", glyph: "󰉉", label: "Get more",
    covers: { "install.style": "N" } }
]},

// Provider pages build their rows at open from a command, one value per line.
// The reader answers a path, not a name, because the rows are paths: the
// provider lists the directory and a choice row ticks when its value equals the
// page's reader (D1). omarchy-theme-bg-current prettifies -- "1-quattro.jpg"
// comes back as "Quattro" -- so against a list of paths it matched nothing and
// the page showed eight wallpapers with none of them current. That name is
// still what the Appearance row shows as its detail; `label: "background"`
// applies the same transform here, so the two agree.
"appearance.background": { title: "Wallpaper",
  reader: "readlink -f \"$HOME/.local/state/omarchy/current/background\"",
  provider: { list: "ls -1 \"$HOME/.local/state/omarchy/current/theme/backgrounds\"/* 2>/dev/null", label: "background" },
  write: "omarchy-theme-bg-set",
  rows: [] },

// omarchy-font-list enumerates `fc-list :spacing=100`, and the font actually in
// use need not be in it: with nothing configured, fc-match falls back to Noto
// Sans Mono, whose family fontconfig here does not tag spacing=100. Ticking
// nothing was correct (D2) and still told the user nothing about what they were
// reading, so the current font joins the list when the list omits it.
"appearance.font": { title: "Font",
  reader: "omarchy-font-current",
  provider: { list: "{ omarchy-font-list; omarchy-font-current; } | awk 'NF' | sort -u", label: "identity" },
  write: "omarchy-font-set",
  rows: [] },

"appearance.bar": { title: "Status bar", rows: [
  // Negative polarity: the flag existing means the percentage is OFF, so the
  // bar looks the same until this is touched.
  //
  // `bar` is the IpcHandler target moarchy.bar declares, and `syncFlags` is a
  // function that handler exports. Both words matter, and both were wrong here
  // until 2026-09-08: this row wrote `omarchy-shell -q omarchy.bar syncHidden`,
  // copied from upstream's own omarchy-toggle-bar, where `omarchy.bar` is the
  // plugin *this phone replaces*. That call answered "Target not found", and
  // `-q` turned it into exit 0 -- so the flag flipped, the switch moved, and
  // the bar went on drawing the percentage it read at startup. docs/settings.md
  // C4.
  { id: "battery", type: "switch", glyph: "󰁹", label: "Battery percentage",
    read: "omarchy-toggle-enabled battery-percentage-off && echo true || echo false",
    invert: true,
    on: "omarchy-toggle battery-percentage-off off && omarchy-shell -q bar syncFlags",
    off: "omarchy-toggle battery-percentage-off on && omarchy-shell -q bar syncFlags",
    covers: { "trigger.toggle.battery-percentage": "N" } }
  // There is deliberately no "Show status bar" row. It had the same dead IPC
  // call as the row above, and unlike that one it was not worth the repair: the
  // shade's grab strip owns the top 26px whether or not the bar draws, so a
  // hidden bar leaves the edge still swallowing drags with nothing on screen to
  // explain it -- and the switch that undid it lived inside the screen it had
  // just made harder to reach. Removed on 2026-09-08 along with the flag read,
  // the keybinding and moarchy-toggle-bar; docs/settings.md C4a, and
  // docs/menu-coverage.md carries `trigger.toggle.top-bar` as Unsupported.
  //
  // There is deliberately no transparency row. The flag can only be written
  // through `omarchy-bar transparent`, which ends by asking the shell to reload
  // its config -- and that reload lands on shell.qml's fallback: the phone bar
  // goes away and upstream's omarchy.bar draws in its place until the shell is
  // restarted. Losing the status bar is not a fair price for an appearance
  // switch, so the row is gone rather than fixed. docs/menu-coverage.md records
  // `style.bar.transparency` as Unsupported for the same reason.
]},

// There is deliberately no Branding page. Its six rows edited two files of ASCII
// art -- ~/.config/omarchy/branding/{about,screensaver}.txt -- and on this phone
// nothing renders either of them. omarchy-launch-about is not what About Omarchy
// opens any more (section N), and omarchy-screensaver begins with a check for
// ttfx, which has no aarch64 build in any repo this image uses, which is why
// system.screensaver was already Unsupported.
//
// Not a rendering problem to solve, either: the art is 54 columns, and 54
// columns across 360 logical pixels is about six pixels a character. A setting
// whose effect cannot appear anywhere is worse than a missing one, because it
// looks like it worked. docs/menu-coverage.md carries the eight ids as
// Unsupported with that reason.

"appearance.more": { title: "Get more", rows: [
  { id: "theme-install", type: "action", glyph: "󰸌", label: "Install a theme",
    run: "omarchy-launch-floating-terminal-with-presentation omarchy-theme-install",
    launch: "none", covers: { "install.style.theme": "B" } },
  { id: "bg-install", type: "action", glyph: "", label: "Install a wallpaper",
    // `launch: "none"`, not "menu": this opens a file manager, not a vendored
    // picker, so there is nothing for Settings to get out of the way of.
    run: "omarchy-theme-bg-install", launch: "none",
    covers: { "install.style.background": "B" } },
  { id: "font-install", type: "nav", page: "appearance.more.font", glyph: "",
    label: "Install a font", covers: { "install.style.font": "N" } },
  { id: "theme-remove", type: "action", glyph: "󰭌", label: "Remove a theme",
    run: "omarchy-theme-remove", launch: "menu", covers: { "remove.theme": "B" } },
  { id: "theme-update", type: "action", glyph: "󰸌", label: "Update extra themes",
    when: "omarchy-theme-extras",
    run: "omarchy-launch-floating-terminal-with-presentation omarchy-theme-update",
    launch: "none", covers: { "update.themes": "B" } }
]},

"appearance.more.font": { title: "Install a font", rows: [
  { id: "cascadia", type: "action", glyph: "", label: "Cascadia Mono",
    run: "omarchy-install-font 'Cascadia Mono' ttf-cascadia-mono-nerd 'CaskaydiaMono Nerd Font'",
    launch: "tui", covers: { "install.style.font.cascadia": "B" } },
  { id: "meslo", type: "action", glyph: "", label: "Meslo LG Mono",
    run: "omarchy-install-font 'Meslo LG Mono' ttf-meslo-nerd 'MesloLGL Nerd Font'",
    launch: "tui", covers: { "install.style.font.meslo": "B" } },
  { id: "fira", type: "action", glyph: "", label: "Fira Code",
    run: "omarchy-install-font 'Fira Code' ttf-firacode-nerd 'FiraCode Nerd Font'",
    launch: "tui", covers: { "install.style.font.fira": "B" } },
  { id: "victor", type: "action", glyph: "", label: "Victor Code",
    run: "omarchy-install-font 'Victor Code' ttf-victor-mono-nerd 'VictorMono Nerd Font'",
    launch: "tui", covers: { "install.style.font.victor": "B" } },
  { id: "bitstream", type: "action", glyph: "", label: "Bitstream Vera Mono",
    run: "omarchy-install-font 'Bitstream Vera Code' ttf-bitstream-vera-mono-nerd 'BitstromWera Nerd Font'",
    launch: "tui", covers: { "install.style.font.bitstream": "B" } },
  { id: "iosevka", type: "action", glyph: "", label: "Iosevka",
    run: "omarchy-install-font Iosevka ttf-iosevka-nerd 'Iosevka Nerd Font Mono'",
    launch: "tui", covers: { "install.style.font.iosevka": "B" } }
]},

// ----------------------------------------------------------------- apps
"apps": { title: "Apps & defaults", rows: [
  { id: "defaults", type: "nav", page: "apps.default", glyph: "", label: "Default apps",
    covers: { "setup.default": "N" } },
  { id: "webapps", type: "nav", page: "apps.webapps", glyph: "", label: "Web apps" },
  { id: "tuis", type: "nav", page: "apps.tuis", glyph: "", label: "Terminal apps" },
  { id: "packages", type: "nav", page: "apps.packages", glyph: "󰣇",
    keywords: "install remove software pacman", label: "Packages" }
]},

"apps.default": { title: "Default apps", rows: [
  { id: "browser", type: "nav", page: "apps.default.browser", glyph: "", label: "Browser",
    detailCmd: "omarchy-default-browser", covers: { "setup.default.browser": "N" } },
  { id: "terminal", type: "nav", page: "apps.default.terminal", glyph: "", label: "Terminal",
    detailCmd: "omarchy-default-terminal", covers: { "setup.default.terminal": "N" } },
  { id: "editor", type: "nav", page: "apps.default.editor", glyph: "", label: "Editor",
    detailCmd: "omarchy-default-editor", covers: { "setup.default.editor": "N" } },
  // Unguarded, deliberately, and it was guarded until mise arrived.
  //
  // The old `when:` was the disjunction of the page's own nine guards, because
  // none of those agents ships in the base set and the row opened an empty
  // screen (F2, B8). What that made was a picker of agents already installed --
  // and with nothing on the phone to install one, a page that could never be
  // reached at all. Upstream ships these rows unguarded because the page IS the
  // installer: `omarchy-default-agent <name>` installs through mise and then
  // launches, so a row for an absent agent is the only row worth having.
  { id: "agent", type: "nav", page: "apps.default.agent", glyph: "󰚩", label: "AI agent",
    detailCmd: "omarchy-default-agent", covers: { "setup.default.agent": "N" } }
]},

"apps.default.browser": { title: "Browser", reader: "omarchy-default-browser", rows: [
  { id: "chromium", type: "choice", label: "Chromium", value: "chromium",
    when: "omarchy-cmd-present chromium", write: "omarchy-default-browser chromium",
    covers: { "setup.default.browser.chromium": "B" } },
  { id: "firefox", type: "choice", label: "Firefox", value: "firefox",
    when: "omarchy-cmd-present firefox", write: "omarchy-default-browser firefox",
    covers: { "setup.default.browser.firefox": "B" } },
  // No upstream id: epiphany is the only browser in the base set, and
  // omarchy-default-browser has no name for it -- so its reader falls through
  // and prints the raw desktop id. That is what readValue is for.
  { id: "epiphany", type: "choice", label: "Epiphany", value: "epiphany",
    readValue: "org.gnome.Epiphany.desktop",
    when: "omarchy-cmd-present epiphany",
    write: "env -u BROWSER xdg-settings set default-web-browser org.gnome.Epiphany.desktop" }
]},

// foot is the only terminal installed (docs/apps.md T1, T4), so this page has
// one row on a stock phone and every other row is an offer that appears with
// the package. That is the guards working rather than the page being empty:
// each row is `when: omarchy-cmd-present <term>`, so installing alacritty or
// kitty brings its row back with no change here.
//
// The reader is worth knowing about. It resolves through
// `xdg-terminal-exec --print-id` and prints the raw desktop id for anything it
// has no name for -- which is how this page used to read "org.kde.qmlkonsole
// .desktop", a value none of its rows could match, against a default nobody
// chose. bin/moarchy-user-setup names foot now.
"apps.default.terminal": { title: "Terminal", reader: "omarchy-default-terminal", rows: [
  { id: "alacritty", type: "choice", label: "Alacritty", value: "alacritty",
    when: "omarchy-cmd-present alacritty", write: "omarchy-default-terminal alacritty",
    covers: { "setup.default.terminal.alacritty": "N" } },
  { id: "foot", type: "choice", label: "Foot", value: "foot",
    when: "omarchy-cmd-present foot", write: "omarchy-default-terminal foot",
    covers: { "setup.default.terminal.foot": "N" } },
  // No Ghostty here either: its guard (`omarchy-cmd-present ghostty`) can never
  // pass, because the package has no aarch64 build to install. See
  // apps.packages.more.
  { id: "kitty", type: "choice", label: "Kitty", value: "kitty",
    when: "omarchy-cmd-present kitty", write: "omarchy-default-terminal kitty",
    covers: { "setup.default.terminal.kitty": "B" } }
]},

"apps.default.editor": { title: "Editor", reader: "omarchy-default-editor", rows: [
  { id: "neovim", type: "choice", label: "Neovim", value: "nvim",
    when: "omarchy-cmd-present nvim", write: "omarchy-default-editor nvim",
    covers: { "setup.default.editor.neovim": "N" } },
  { id: "helix", type: "choice", label: "Helix", value: "helix",
    when: "omarchy-cmd-present helix", write: "omarchy-default-editor helix",
    covers: { "setup.default.editor.helix": "B" } },
  { id: "vim", type: "choice", label: "Vim", value: "vim",
    when: "omarchy-cmd-present vim", write: "omarchy-default-editor vim",
    covers: { "setup.default.editor.vim": "B" } }
]},

// The page that installs an agent, not the page that lists the installed ones.
//
// Every row here carried `when: omarchy-cmd-present <bin>` until mise arrived,
// and with no agent on the phone that hid all nine -- and, through the guard on
// the row above, the page itself. Upstream ships the identical rows unguarded, and
// the loop is why: the write asks mise where the agent is, installs it in a
// terminal that shows the download when it is not there, writes
// ~/.config/omarchy/defaults/agent, and execs it. A row for an agent that is
// absent is the one row that does something.
//
// The write is `moarchy-agent open <name>` rather than `omarchy-default-agent
// <name>` for one reason: it writes the drawer tile first. An agent reachable
// only from here is four taps deep and invisible in the app grid; after this it
// is an icon like any other app, and the icon runs this same command.
//
// One tile, not one per agent. moarchy-agent.desktop is REWRITTEN by every tap
// on this page -- name, icon and Exec -- so picking a second agent moves the
// tile rather than adding a tenth icon to a 64-entry grid. Which means this
// page is also the only thing that keeps the tile honest: `omarchy-default-agent
// <name>` typed into a terminal changes the default without passing through
// here, and leaves the tile naming the agent before it. `moarchy-agent entry`
// with no argument re-reads the default and repairs it.
//
// And before anything is picked, that tile is a setup tile pointing back HERE
// (`omarchy-shell settings openAt apps.default.agent`, docs/settings.md P10).
// So this page is both ends of the loop: the only screen that installs an
// agent, and the only screen the grid can reach before one exists.
//
// Every tap ends in a terminal either way -- the presentation terminal on the
// way in, omarchy-agent's own on the way out -- and all nine used to carry
// `hides: true` to take Settings off screen so that terminal could be seen.
// Settings is a window now (docs/gestures.md K8): the terminal maps above it or
// beside it, and the flag is gone from the model entirely.
//
// All nine are listed, as upstream lists them, rather than the subset proven to
// run here. Verified as having a linux-arm64 artifact on npm: claude, codex,
// gemini, copilot, opencode and grok. Not verified: crush, omp and pi -- and
// none of the six through mise's own backend, which resolves most of these
// names through aqua rather than npm. A row that cannot install says so in a
// terminal with the reason on screen, which is a better answer than a page that
// hides the question.
//
// The same nine, in the same order, are moarchy-agent's `agents()` and the nine
// files in default/agents/. Three lists, and moarchy-selftest asserts all three
// against upstream's own `omarchy:args=` line rather than against each other,
// so a name upstream adds fails here loudly instead of quietly missing an icon.
"apps.default.agent": { title: "AI agent", reader: "omarchy-default-agent", rows: [
  { id: "how", type: "info", glyph: "󰚩", label: "Tap one to install it",
    detail: "The first run downloads the agent, then opens it" },
  { id: "claude", type: "choice", label: "Claude", value: "claude",
    write: "moarchy-agent open claude",
    covers: { "setup.default.agent.claude": "N" } },
  { id: "codex", type: "choice", label: "Codex", value: "codex",
    write: "moarchy-agent open codex",
    covers: { "setup.default.agent.codex": "N" } },
  { id: "copilot", type: "choice", label: "Copilot", value: "copilot",
    write: "moarchy-agent open copilot",
    covers: { "setup.default.agent.copilot": "N" } },
  { id: "crush", type: "choice", label: "Crush", value: "crush",
    write: "moarchy-agent open crush",
    covers: { "setup.default.agent.crush": "N" } },
  { id: "gemini", type: "choice", label: "Gemini", value: "gemini",
    write: "moarchy-agent open gemini",
    covers: { "setup.default.agent.gemini": "N" } },
  { id: "grok", type: "choice", label: "Grok", value: "grok",
    write: "moarchy-agent open grok",
    covers: { "setup.default.agent.grok": "N" } },
  { id: "omp", type: "choice", label: "omp", value: "omp",
    write: "moarchy-agent open omp",
    covers: { "setup.default.agent.omp": "N" } },
  { id: "opencode", type: "choice", label: "OpenCode", value: "opencode",
    write: "moarchy-agent open opencode",
    covers: { "setup.default.agent.opencode": "N" } },
  { id: "pi", type: "choice", label: "Pi", value: "pi",
    write: "moarchy-agent open pi",
    covers: { "setup.default.agent.pi": "N" } }
]},

"apps.webapps": { title: "Web apps", rows: [
  { id: "add", type: "action", glyph: "", label: "Add a web app",
    run: "omarchy-launch-floating-terminal-with-presentation omarchy-webapp-install",
    launch: "none", covers: { "install.webapp": "B" } },
  { id: "remove", type: "action", glyph: "󰭌", label: "Remove a web app",
    when: "grep -qE '^Exec=.*(omarchy-launch-webapp|omarchy-webapp-handler)' $HOME/.local/share/applications/*.desktop",
    run: "omarchy-webapp-remove", launch: "menu", covers: { "remove.webapp": "B" } }
]},

"apps.tuis": { title: "Terminal apps", rows: [
  { id: "add", type: "action", glyph: "", label: "Add a terminal app",
    run: "omarchy-launch-floating-terminal-with-presentation omarchy-tui-install",
    launch: "none", covers: { "install.tui": "B" } },
  { id: "remove", type: "action", glyph: "󰭌", label: "Remove a terminal app",
    when: "grep -qE '^Exec=.*(\\$TERMINAL|xdg-terminal-exec).*-e' $HOME/.local/share/applications/*.desktop",
    run: "omarchy-tui-remove", launch: "menu", covers: { "remove.tui": "B" } }
]},

"apps.packages": { title: "Packages", rows: [
  { id: "install", type: "action", glyph: "󰣇", label: "Install a package",
    run: "omarchy-pkg-install", launch: "tui", covers: { "install.package": "B" } },
  { id: "aur", type: "action", glyph: "󰣇", label: "Install from the AUR",
    run: "omarchy-pkg-aur-install", launch: "tui", covers: { "install.aur": "B" } },
  { id: "remove", type: "action", glyph: "󰭌", label: "Remove a package",
    run: "omarchy-pkg-remove", launch: "tui", covers: { "remove.package": "B" } },
  { id: "more", type: "nav", page: "apps.packages.more", glyph: "󰏓", label: "More software" }
]},

// One row per install/remove pair. Upstream keeps two mirror trees only because
// each row is guarded on the complement of its twin, so at most one of a pair
// is ever visible -- which makes two trees a dmenu artifact, not a structure.
"apps.packages.more": { title: "More software",
  covers: { "install.browser": "N", "install.editor": "N", "install.terminal": "N",
            "remove.browser": "N" },
  rows: [
  { id: "firefox-install", type: "action", glyph: "", label: "Install Firefox",
    when: "! omarchy-pkg-present firefox",
    run: "omarchy-launch-floating-terminal-with-presentation 'omarchy-install-browser firefox'",
    launch: "none", covers: { "install.browser.firefox": "B" } },
  { id: "firefox-remove", type: "action", glyph: "", label: "Remove Firefox",
    when: "omarchy-pkg-present firefox",
    run: "omarchy-launch-floating-terminal-with-presentation 'omarchy-remove-browser firefox'",
    launch: "none", covers: { "remove.browser.firefox": "B" } },
  { id: "signal", type: "action", glyph: "󰭹", label: "Install Signal",
    when: "! omarchy-pkg-present signal-desktop",
    run: "omarchy-launch-floating-terminal-with-presentation omarchy-install-service-signal",
    launch: "none", covers: { "install.service.signal": "B" } },
  { id: "vim", type: "action", glyph: "", label: "Install Vim",
    when: "! omarchy-pkg-present vim", run: "omarchy-install-app Vim vim",
    launch: "tui", covers: { "install.editor.vim": "B" } },
  { id: "helix", type: "action", glyph: "", label: "Install Helix",
    when: "! omarchy-pkg-present helix",
    run: "omarchy-launch-floating-terminal-with-presentation omarchy-install-editor-helix",
    launch: "none", covers: { "install.editor.helix": "B" } },
  // No Ghostty row: it is the one entry on this page whose package does not
  // exist for aarch64 -- `pacman -Si ghostty` finds nothing, and
  // omarchy-pkg-add is a plain `pacman -S` with no AUR fallback. The guard
  // (`! omarchy-pkg-present ghostty`) is therefore permanently true, so unlike
  // Alacritty and Foot below -- hidden because they are already installed --
  // this row showed itself and could only fail. install.terminal.ghostty and
  // setup.default.terminal.ghostty are Unsupported in menu-coverage.md.
  { id: "kitty", type: "action", glyph: "", label: "Install Kitty",
    when: "! omarchy-pkg-present kitty",
    run: "omarchy-launch-floating-terminal-with-presentation 'omarchy-install-terminal kitty'",
    launch: "none", covers: { "install.terminal.kitty": "B" } },
  // Alacritty is a live offer since 2026-09-08 and Foot is the permanently
  // hidden one -- they used to be hidden together, on the reading that the
  // phone came with both. Neither row changed; the package set did
  // (docs/apps.md T4). Foot stays listed because it is exactly the row that
  // should reappear if someone ever removes the terminal, which the drawer
  // refuses (T5) but pacman does not.
  { id: "alacritty", type: "action", glyph: "", label: "Install Alacritty",
    when: "! omarchy-pkg-present alacritty",
    run: "omarchy-launch-floating-terminal-with-presentation 'omarchy-install-terminal alacritty'",
    launch: "none", covers: { "install.terminal.alacritty": "B" } },
  { id: "foot", type: "action", glyph: "", label: "Install Foot",
    when: "! omarchy-pkg-present foot",
    run: "omarchy-launch-floating-terminal-with-presentation 'omarchy-install-terminal foot'",
    launch: "none", covers: { "install.terminal.foot": "B" } }
]},

// -------------------------------------------------------------------- shell
"shell": { title: "Shell & plugins", rows: [
  { id: "plugins", type: "nav", page: "shell.plugins", glyph: "󰐱", label: "Plugins",
    detailCmd: "moarchy-plugins summary",
    covers: { "setup.plugin": "N" } },
  { id: "restart", type: "action", glyph: "󰍜", label: "Restart shell",
    detail: "Bar, drawer, shade and gestures",
    run: "moarchy-restart-shell", launch: "none",
    covers: { "update.process.shell": "N", "update.process": "N" } },
  { id: "tmux", type: "action", glyph: "", label: "Reset tmux config",
    run: "omarchy-launch-floating-terminal-with-presentation omarchy-refresh-tmux",
    launch: "none", covers: { "update.config.tmux": "B", "update.config": "N" } }
]},

"shell.plugins": { title: "Plugins",
  // A list of switches instead of two launches of the vendored select box.
  // Enable was: tap Enable, find the plugin in a clipped card, tap it.
  // Disable was the same walk again to undo it, and neither screen ever
  // showed which plugins were already on.
  //
  // Add, clone and remove stay where they are, and stay bridged: adding
  // takes a repo URL typed in and cloning opens the copy in an editor.
  // Those are terminal work rather than a row that could replace them.
  provider: { json: "moarchy-plugins rows", before: true },
  // The two ids the switches took over. They hang off the page rather than off a
  // row because the rows that satisfy them are built at open, one per plugin,
  // and a coverage map keyed by row id has nowhere to put forty of them.
  covers: { "setup.plugin.enable": "N", "setup.plugin.disable": "N" },
  rows: [
  { id: "add", type: "action", glyph: "󰖟", label: "Add a plugin",
    run: "omarchy-launch-floating-terminal-with-presentation 'omarchy-plugin-add'",
    launch: "none", covers: { "setup.plugin.add": "B" } },
  { id: "clone", type: "action", glyph: "󰆏", label: "Clone a plugin",
    run: "omarchy-menu-plugin clone", launch: "menu",
    covers: { "setup.plugin.clone": "B" } },
  // This used to be able to uninstall the phone UI, back when the moarchy.*
  // plugins were copied into ~/.config/omarchy/plugins and upstream's guard
  // matched their six manifests. They are packaged now, under
  // /usr/share/moarchy/plugins, and omarchy-plugin-remove only ever rm -rf's
  // inside $HOME/.config/omarchy/plugins -- so it cannot reach them, and with
  // that directory empty the guard is false and the row does not render at all.
  // The confirm stays: a user who clones a plugin there puts the row back.
  { id: "remove", type: "action", glyph: "󰭌", label: "Remove a plugin",
    when: "compgen -G \"$HOME/.config/omarchy/plugins/*/manifest.json\"",
    confirm: "Removing a moarchy plugin takes away part of the phone UI.",
    run: "omarchy-menu-plugin remove", launch: "menu",
    covers: { "setup.plugin.remove": "B" } }
]},

// ----------------------------------------------------------------- security
"security": { title: "Security", rows: [
  // Read natively, written through a bridged launch: the state is a systemctl
  // question, but the write needs a sudo prompt a QML surface cannot host.
  //
  // Both commands end in a terminal that asks something. The setup script runs
  // `setup_sshd` unattended and only then asks, twice, with gum: a `gum choose`
  // between GitHub and pasting, then a `gum input` for the username. Under the
  // old layer surface that foot window was invisible, so the daemon came up and
  // the keys never did -- port 22 open on a phone nobody could reach, observed
  // 2026-09-08. The terminal is a window above a window now (K8); nothing on
  // this row has to arrange for it.
  { id: "ssh", type: "switch", glyph: "󰣀", label: "Remote access (SSH)",
    read: "systemctl is-enabled --quiet sshd && echo true || echo false",
    on: "omarchy-launch-floating-terminal-with-presentation omarchy-setup-security-sshd",
    off: "omarchy-launch-floating-terminal-with-presentation omarchy-remove-security-sshd",
    launch: "none",
    covers: { "setup.security.sshd": "B", "remove.security.sshd": "B" } },
  // The same script, on demand. Two rows because the switch reads
  // `systemctl is-enabled sshd`: once the daemon is on the switch shows ON and
  // there is nothing left to tap, and that is exactly the state a phone is in
  // when sshd came up but no key was ever authorized. It happened on
  // 2026-09-08 -- port 22 open, `Permission denied (publickey)` from the Mac,
  // and the only way back to the prompt was typing the script's name by hand.
  //
  // The detail is the whole point of the row. "Remote access: on" is not the
  // question anyone has; "0 authorized" is, and it says at a glance whether
  // ssh can work. A missing file counts 0 rather than reading blank, so the
  // row that cannot answer says so instead of looking fine. No `covers`: the
  // switch above already claims setup.security.sshd, and coverage totals are
  // asserted at 129 lines.
  { id: "sshkeys", type: "action", glyph: "󰌆", label: "Authorize SSH keys",
    keywords: "github remote login publickey",
    detailCmd: "echo \"$(grep -c '^[a-z]' $HOME/.ssh/authorized_keys 2>/dev/null || echo 0) authorized\"",
    run: "omarchy-launch-floating-terminal-with-presentation omarchy-setup-security-sshd",
    launch: "none" },
  // The image already grants this permanently in /etc/sudoers.d/10-moarchy, so
  // upstream's row -- which writes a 15-minute 99-omarchy-nopasswd-$USER and
  // times it out -- changes nothing observable either way. Kept because it is
  // harmless and covers the id, with the detail saying why it looks inert.
  { id: "sudo", type: "action", glyph: "󰟵", label: "Passwordless sudo",
    detail: "Already on for this image",
    run: "omarchy-launch-floating-terminal-with-presentation omarchy-sudo-passwordless",
    launch: "none", covers: { "setup.security.passwordless-sudo": "B" } },
  // `sudo passwd`, not upstream's bare `passwd` -- the fourth E2 exception.
  // The image locks the account password, so `passwd` has no current password
  // to authenticate against and fails on its first question ("Authentication
  // failure", verified on the device). Under sudo it sets one outright, and
  // /etc/sudoers.d/10-moarchy means that costs no prompt. This row is the only
  // way to give the account a password, so it has to be the working form.
  { id: "passwd", type: "action", glyph: "", label: "Change password",
    run: "omarchy-launch-floating-terminal-with-presentation 'sudo passwd \"$USER\"'",
    launch: "none", covers: { "update.password.user": "B", "update.password": "N" } }
]},

// -------------------------------------------------------------------- tools
"tools": { title: "Tools", rows: [
  { id: "screenshot", type: "action", glyph: "", label: "Screenshot",
    keywords: "capture grab screen",
    run: "moarchy-capture-screenshot", launch: "none",
    covers: { "trigger.capture.screenshot": "N", "trigger.capture": "N" } },
  { id: "record", type: "nav", page: "tools.record", glyph: "", label: "Screen record",
    when: "omarchy-cmd-present gpu-screen-recorder",
    covers: { "trigger.capture.screenrecord": "N" } },
  { id: "emoji", type: "action", glyph: "", label: "Emoji",
    run: "omarchy-menu-emoji", launch: "none",
    covers: { "trigger.emoji": "B" } },
  // `trigger.reminder.show` is this row, not a row on the page it opens: the
  // page IS the list, so opening it is the whole of showing them (J1).
  { id: "reminders", type: "nav", page: "tools.reminders", glyph: "󰢌", label: "Reminders",
    keywords: "timer alarm",
    detailCmd: "moarchy-reminders summary",
    covers: { "trigger.reminder": "N", "trigger.reminder.show": "N" } },
  // Dropped, not guarded: omarchy-launch-screensaver opens with
  // `omarchy-cmd-missing ttfx && exit 1`, and ttfx has no aarch64 build in any
  // repo this phone uses -- so unlike gpu-screen-recorder (an optdepend that
  // could be installed) there is no state in which this row could work. It
  // exited 1 silently, which reads exactly like a screensaver that ran and was
  // dismissed. system.screensaver is Unsupported in menu-coverage.md.
  { id: "tests", type: "nav", page: "tools.tests", glyph: "󰓅", label: "Speed tests",
    covers: { "trigger.tests": "N" } }
]},

"tools.record": { title: "Screen record", rows: [
  { id: "stop", type: "action", glyph: "", label: "Stop recording",
    when: "pgrep -f '^gpu-screen-recorder'",
    run: "omarchy-capture-screenrecording --stop-recording", launch: "none",
    covers: { "trigger.capture.screenrecord.stop": "B" } },
  { id: "silent", type: "action", glyph: "", label: "Record with no audio",
    run: "omarchy-capture-screenrecording", launch: "none",
    covers: { "trigger.capture.screenrecord.no-audio": "B" } },
  { id: "desktop-audio", type: "action", glyph: "", label: "Record with desktop audio",
    run: "omarchy-capture-screenrecording --with-desktop-audio", launch: "none",
    covers: { "trigger.capture.screenrecord.desktop-audio": "B" } }
]},

// The three reminder rows were bridged until 2026-09-07, and all three were
// unusable on a phone: `-i` opens a keyboard-only prompt with no field, and
// `show` and `clear` answer in a notification after `activate` has already put
// Settings away. docs/settings.md J is the contract they are Native to now.
//
// The list comes back as rows rather than as values, because each one carries
// its own command -- `provider.json` (Settings.qml) is that shape. `before`
// puts them above the two static rows, so opening the page is seeing them.
"tools.reminders": { title: "Reminders",
  provider: { json: "moarchy-reminders rows", before: true },
  rows: [
  { id: "new", type: "nav", page: "tools.reminders.new", glyph: "󰐕",
    label: "Set a reminder", covers: { "trigger.reminder.set": "N" } },
  // Guarded on there being something to clear, so the row is not offered as a
  // no-op (J5). `inline` because this one has no terminal and no picker to get
  // out of the way of: it runs where it stands and the list re-reads (J6).
  { id: "clear", type: "action", glyph: "󰅖", label: "Clear all",
    when: "[ \"$(moarchy-reminders count)\" -gt 0 ]",
    confirm: "Clear every reminder?",
    run: "omarchy-reminder clear", launch: "inline",
    covers: { "trigger.reminder.clear": "N" } }
]},

// Presets first because a thumb wants one tap, then the pair that takes any
// duration at all. `argsFrom` appends the named inputs, shell-quoted, in that
// order -- so every row here runs `moarchy-reminders set <minutes> <message>`
// and the empty message arrives as an empty argument rather than not at all.
"tools.reminders.new": { title: "Set a reminder", rows: [
  { id: "message", type: "input", glyph: "󰭹", label: "Message",
    placeholder: "Message (optional)" },
  { id: "m5",   type: "action", glyph: "󰢌", label: "In 5 minutes",
    run: "moarchy-reminders set 5",   argsFrom: ["message"], launch: "inline", back: true },
  { id: "m10",  type: "action", glyph: "󰢌", label: "In 10 minutes",
    run: "moarchy-reminders set 10",  argsFrom: ["message"], launch: "inline", back: true },
  { id: "m15",  type: "action", glyph: "󰢌", label: "In 15 minutes",
    run: "moarchy-reminders set 15",  argsFrom: ["message"], launch: "inline", back: true },
  { id: "m30",  type: "action", glyph: "󰢌", label: "In 30 minutes",
    run: "moarchy-reminders set 30",  argsFrom: ["message"], launch: "inline", back: true },
  { id: "m45",  type: "action", glyph: "󰢌", label: "In 45 minutes",
    run: "moarchy-reminders set 45",  argsFrom: ["message"], launch: "inline", back: true },
  { id: "m60",  type: "action", glyph: "󰢌", label: "In 1 hour",
    run: "moarchy-reminders set 60",  argsFrom: ["message"], launch: "inline", back: true },
  { id: "m120", type: "action", glyph: "󰢌", label: "In 2 hours",
    run: "moarchy-reminders set 120", argsFrom: ["message"], launch: "inline", back: true },
  { id: "minutes", type: "input", glyph: "󰅐", label: "Minutes",
    placeholder: "Minutes", numeric: true },
  // Dimmed and inert until the field above holds something (J8). The script
  // validates the number too -- this is the affordance, not the check.
  { id: "custom", type: "action", glyph: "󰄬", label: "Set reminder",
    run: "moarchy-reminders set", argsFrom: ["minutes", "message"],
    requires: "minutes", launch: "inline", back: true }
]},

"tools.tests": { title: "Speed tests", rows: [
  { id: "network", type: "action", glyph: "󰓅", label: "Network speed test",
    run: "omarchy-shell shell summon omarchy.speedtest", launch: "none",
    covers: { "trigger.tests.network-speedtest": "B" } },
  { id: "disk", type: "action", glyph: "󰋊", label: "Disk speed test",
    run: "omarchy-shell shell summon omarchy.disk-speedtest", launch: "none",
    covers: { "trigger.tests.disk-speedtest": "B" } }
]},

// ------------------------------------------------------------------- system
"system": { title: "System", rows: [
  { id: "time", type: "nav", page: "system.time", glyph: "", label: "Date & time" },
  { id: "hardware", type: "nav", page: "system.hardware", glyph: "󰇅",
    label: "Restart hardware", covers: { "update.hardware": "N" } },
  // No `covers`. This is not upstream's `update.omarchy` under another label --
  // that one wants pkgs.omarchy.org's aarch64 tree, which 404s, and Snapper on
  // btrfs, and it stays Unsupported. This is the plain upgrade, which
  // structure.md R8a says works on this image and cannot move the device stack:
  // linux-megi, uboot-pinephone and the rest are foreign packages from a repo
  // the phone is not configured for, frozen at flash time. A row claiming the id
  // would be promising the snapshots and migrations upstream's script does and
  // delivering an upgrade. docs/settings.md says the same from the other side.
  { id: "update", type: "action", glyph: "󰚰", label: "Update system",
    detail: "pacman -Syu in a terminal", keywords: "upgrade pacman packages",
    run: "sudo pacman -Syu", launch: "tui" },
  { id: "power", type: "nav", page: "system.power", glyph: "󰐥", label: "Power" }
]},

"system.time": { title: "Date & time", rows: [
  // A screen, not omarchy-menu-timezone. That piped all ~420 zones into the
  // vendored select box: a fixed card with the list clipped and a filter field
  // that wants a keyboard, to find one entry out of four hundred.
  { id: "zone", type: "nav", page: "system.time.zone", glyph: "󰗰",
    label: "Time zone", detailCmd: "moarchy-timezone current",
    covers: { "update.timezone": "N" } },
  { id: "time", type: "action", glyph: "", label: "Set the time",
    run: "omarchy-launch-floating-terminal-with-presentation omarchy-update-time",
    launch: "none", covers: { "update.time": "B" } }
]},

// Region, then city -- two taps down a list you can read, instead of a filter
// field over four hundred entries. The region pages are generated below rather
// than written out eleven times.
//
// UTC is a choice row and not a region: `timedatectl list-timezones` lists it
// flat, with no "/" to walk into, and it is the one a phone with no fixed home
// actually wants.
"system.time.zone": { title: "Time zone",
  reader: "moarchy-timezone current",
  rows: [
  { id: "utc", type: "choice", glyph: "󰥔", label: "UTC", value: "UTC",
    write: "moarchy-timezone set UTC" }
]},

"system.hardware": { title: "Restart hardware", rows: [
  { id: "audio", type: "action", glyph: "", label: "Audio",
    run: "omarchy-launch-floating-terminal-with-presentation omarchy-restart-audio",
    launch: "none", covers: { "update.hardware.audio": "B" } },
  { id: "wifi", type: "action", glyph: "󱚾", label: "Wi-Fi",
    run: "omarchy-launch-floating-terminal-with-presentation omarchy-restart-wifi",
    launch: "none", covers: { "update.hardware.wifi": "B" } },
  { id: "bluetooth", type: "action", glyph: "󰂯", label: "Bluetooth",
    run: "omarchy-launch-floating-terminal-with-presentation omarchy-restart-bluetooth",
    launch: "none", covers: { "update.hardware.bluetooth": "B" } }
]},

"system.power": { title: "Power", rows: [
  { id: "lock", type: "action", glyph: "", label: "Lock",
    run: "moarchy-system-lock", launch: "none",
    covers: { "system.lock": "N" } },
  { id: "logout", type: "action", glyph: "󰍃", label: "Log out",
    confirm: "Log out of the session?",
    run: "moarchy-system-logout", launch: "none",
    covers: { "system.logout": "N" } },
  { id: "reboot", type: "action", glyph: "󰜉", label: "Restart",
    confirm: "Restart the phone?",
    run: "omarchy-system-reboot", launch: "none", covers: { "system.reboot": "B" } },
  { id: "shutdown", type: "action", glyph: "󰐥", label: "Power off",
    confirm: "Power off the phone?",
    run: "omarchy-system-shutdown", launch: "none", covers: { "system.shutdown": "B" } }
]},

// -------------------------------------------------------------------- about
"about": { title: "About phone", rows: [
  { id: "version", type: "info", glyph: "", label: "Omarchy", read: "omarchy-version" },
  { id: "kernel", type: "info", glyph: "󰌢", label: "Kernel", read: "uname -r" },
  { id: "device", type: "info", glyph: "󰄤", label: "Device",
    read: "tr -d '\\0' < /proc/device-tree/model 2>/dev/null || echo unknown" },
  { id: "keys", type: "nav", page: "about.keys", glyph: "", label: "Keybindings",
    covers: { "learn.keybindings": "N" } },
  { id: "help", type: "nav", page: "about.help", glyph: "󰧑", label: "Help & docs" },
  // A page of rows, not fastfetch in a terminal. omarchy-launch-about sizes
  // itself by measuring its own output from inside the terminal and re-renders
  // on every resize; here it re-execs through the default terminal with
  // --render, and the default terminal WAS qmlkonsole, which answers "Unknown
  // option 'render'" under a logo clipped to its first two letters. The fields
  // were never the problem.
  //
  // qmlkonsole is gone and foot is the default now (docs/apps.md T1, T2), so
  // that particular error is not what would happen today. This stays a page of
  // rows regardless: the terminal was the trigger, but re-rendering fastfetch
  // on every resize inside a 47-column window is not a thing this screen wants
  // whichever terminal draws it.
  { id: "aboutomarchy", type: "nav", page: "about.omarchy", glyph: "󰋽",
    label: "About Omarchy", covers: { "about": "N" } }
]},

// A text page: one command, its output rendered as rows. Upstream's
// learn.keybindings ends in `less` with no terminal to draw in, so today the
// row shows nothing at all.
"about.keys": { title: "Keybindings", text: "omarchy-menu-keybindings --print", rows: [] },

"about.omarchy": { title: "About Omarchy",
  provider: { json: "moarchy-about rows" },
  rows: [] },

"about.help": { title: "Help & docs", rows: [
  { id: "manual", type: "link", glyph: "", label: "Omarchy manual",
    url: "https://omarchy.org/manual/", covers: { "learn.omarchy": "B" } },
  { id: "arch", type: "link", glyph: "󰣇", label: "Arch wiki",
    url: "https://wiki.archlinux.org/title/Main_page", covers: { "learn.arch": "B" } },
  { id: "bash", type: "link", glyph: "󱆃", label: "Bash",
    url: "https://devhints.io/bash", covers: { "learn.bash": "B" } },
  { id: "neovim", type: "link", glyph: "", label: "Neovim",
    url: "https://www.lazyvim.org/keymaps", covers: { "learn.neovim": "B" } },
  { id: "tmux", type: "action", glyph: "", label: "Tmux keybindings",
    run: "omarchy-menu-tmux-keybindings", launch: "menu",
    covers: { "learn.tmux-keybindings": "B" } },
  { id: "community", type: "action", glyph: "󰙯", label: "Community",
    run: "omarchy-launch-discord-community", launch: "none",
    covers: { "learn.community": "B" } }
]}

};

// The tzdata areas. Static, because a page id has to exist in PAGES before
// anything can navigate to it -- a provider cannot invent a destination -- and
// these eleven have been the top level of the database since Antarctica was
// added to it.
var TZ_REGIONS = ["Africa", "America", "Antarctica", "Arctic", "Asia", "Atlantic",
                  "Australia", "Europe", "Indian", "Pacific", "Etc"];

for (var _t = 0; _t < TZ_REGIONS.length; _t++) {
    var _region = TZ_REGIONS[_t];
    PAGES["system.time.zone"].rows.push(
        // `unlisted`, so the drawer's search does not answer "a" with Asia,
        // Africa, Arctic and America. The page each of these opens is built by
        // the provider below, and provider rows are not in the search index by
        // design (Search.js, O10) -- so these lead only where search cannot
        // follow. Findable by walking Settings, which is how a region was ever
        // meant to be reached.
        { id: "r" + _t, type: "nav", page: "system.time.zone." + _region,
          glyph: "󰗰", label: _region, unlisted: true });
    // `label: "city"` keeps the whole zone as the row's value -- what
    // timedatectl takes and what the reader answers -- while showing the half
    // a person is looking for.
    PAGES["system.time.zone." + _region] = {
        title: _region,
        reader: "moarchy-timezone current",
        provider: { list: "timedatectl list-timezones | grep '^" + _region + "/'",
                    label: "city" },
        write: "moarchy-timezone set",
        rows: []
    };
}

function page(id) { return PAGES[id] || null; }
function exists(id) { return !!PAGES[id]; }

// The coverage map, emitted over IPC. Rows first, then the page-level `covers`
// some container ids hang off, then the ids satisfied outside this stack.
function coverage() {
    var out = [];
    for (var pid in PAGES) {
        var p = PAGES[pid];
        if (p.covers)
            for (var c in p.covers) out.push([c, p.covers[c], pid, ""]);
        for (var i = 0; i < p.rows.length; i++) {
            var r = p.rows[i];
            if (!r.covers) continue;
            for (var id in r.covers) out.push([id, r.covers[id], pid, r.id]);
        }
    }
    for (var e in EXTERNAL) out.push([e, EXTERNAL[e].cls, EXTERNAL[e].where, ""]);
    for (var s in SHADE) out.push([s, "S", SHADE[s], ""]);
    return out;
}
