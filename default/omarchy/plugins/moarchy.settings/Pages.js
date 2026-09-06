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
//            "menu" a vendored picker that needs Settings out of the way
//            first, "none" straight to execDetached.
//   link     a URL, through the omarchy-launch-webapp shim.
//   info     read-only text.
//
// Any row may carry `when`, copied verbatim from omarchy-menu.jsonc so the
// guard that upstream uses is the guard we use.
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
  // nowhere. TUIs that do ask are fine by touch; see the bluetooth row.
  //
  // returnTo brings Back here rather than dropping you on the home screen.
  { id: "wifi", type: "action", glyph: "󱚾", label: "Wi-Fi networks",
    detailCmd: "omarchy-network-status",
    run: "omarchy-shell shell summon moarchy.wifi '{\"returnTo\":\"moarchy.settings\",\"page\":\"net\"}'",
    launch: "none" },
  // Bluetooth keeps the TUI: pairing is rarer, and the equivalent screen is not
  // written. That is affordable because bluetui is operable here -- it enables
  // mouse reporting, and its own bindings (s scan, Enter connect, j/k) are all
  // keys the on-screen keyboard has, tab and arrows included. Not impala's
  // Bluetooth half -- and for Wi-Fi impala was
  // wrong outright, being an iwd client on a phone running NetworkManager with
  // iwd.service disabled but D-Bus activatable, so it would have started iwd to
  // fight NetworkManager for wlan0.
  { id: "bluetooth", type: "action", glyph: "󰂯", label: "Bluetooth devices",
    run: "bluetui", launch: "tui" },
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
  { id: "mixer", type: "action", glyph: "", label: "Audio devices & volume",
    run: "wiremix", launch: "tui" },
  { id: "crashcapture", type: "switch", glyph: "󱚡", label: "Crash capture",
    detail: "Keep a log when an app dies",
    read: "omarchy-toggle-enabled crash-capture-off && echo true || echo false",
    invert: true,
    on: "omarchy-toggle crash-capture-off off",
    off: "omarchy-toggle crash-capture-off on",
    covers: { "trigger.toggle.crash-capture": "N" } }
]},

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
  { id: "branding", type: "nav", page: "appearance.branding", glyph: "",
    label: "Branding", covers: { "style.about": "N", "style.screensaver": "N" } },
  { id: "more", type: "nav", page: "appearance.more", glyph: "󰉉", label: "Get more",
    covers: { "install.style": "N" } }
]},

// Provider pages build their rows at open from a command, one value per line.
"appearance.background": { title: "Wallpaper",
  reader: "omarchy-theme-bg-current",
  provider: { list: "ls -1 \"$HOME/.local/state/omarchy/current/theme/backgrounds\"/* 2>/dev/null", label: "basename" },
  write: "omarchy-theme-bg-set",
  rows: [] },

"appearance.font": { title: "Font",
  reader: "omarchy-font-current",
  provider: { list: "omarchy-font-list", label: "identity" },
  write: "omarchy-font-set",
  rows: [] },

"appearance.bar": { title: "Status bar", rows: [
  // Negative polarity: the flag existing means the bar is OFF.
  { id: "show", type: "switch", glyph: "󰍜", label: "Show status bar",
    read: "omarchy-toggle-enabled bar-off && echo true || echo false", invert: true,
    on: "moarchy-toggle-bar on", off: "moarchy-toggle-bar off",
    covers: { "trigger.toggle.top-bar": "N" } },
  // Negative polarity again, so the bar looks the same until this is touched.
  { id: "battery", type: "switch", glyph: "󰁹", label: "Battery percentage",
    read: "omarchy-toggle-enabled battery-percentage-off && echo true || echo false",
    invert: true,
    on: "omarchy-toggle battery-percentage-off off && omarchy-shell -q omarchy.bar syncHidden",
    off: "omarchy-toggle battery-percentage-off on && omarchy-shell -q omarchy.bar syncHidden",
    covers: { "trigger.toggle.battery-percentage": "N" } }
  // There is deliberately no transparency row. The flag can only be written
  // through `omarchy-bar transparent`, which ends by asking the shell to reload
  // its config -- and that reload lands on shell.qml's fallback: the phone bar
  // goes away and upstream's omarchy.bar draws in its place until the shell is
  // restarted. Losing the status bar is not a fair price for an appearance
  // switch, so the row is gone rather than fixed. docs/menu-coverage.md records
  // `style.bar.transparency` as Unsupported for the same reason.
]},

"appearance.branding": { title: "Branding", rows: [
  { id: "about-text", type: "action", glyph: "", label: "About: edit text",
    run: "omarchy-branding-about text", launch: "tui",
    covers: { "style.about.text": "B" } },
  { id: "about-image", type: "action", glyph: "", label: "About: set from image",
    run: "omarchy-branding-about image", launch: "tui",
    covers: { "style.about.image": "B" } },
  { id: "about-reset", type: "action", glyph: "", label: "About: restore default",
    run: "omarchy-branding-about reset", launch: "tui",
    covers: { "style.about.default": "B" } },
  { id: "saver-text", type: "action", glyph: "󱄄", label: "Screensaver: edit text",
    run: "omarchy-branding-screensaver text", launch: "tui",
    covers: { "style.screensaver.text": "B" } },
  { id: "saver-image", type: "action", glyph: "󱄄", label: "Screensaver: set from image",
    run: "omarchy-branding-screensaver image", launch: "tui",
    covers: { "style.screensaver.image": "B" } },
  { id: "saver-reset", type: "action", glyph: "󱄄", label: "Screensaver: restore default",
    run: "omarchy-branding-screensaver reset", launch: "tui",
    covers: { "style.screensaver.default": "B" } }
]},

"appearance.more": { title: "Get more", rows: [
  { id: "theme-install", type: "action", glyph: "󰸌", label: "Install a theme",
    run: "omarchy-launch-floating-terminal-with-presentation omarchy-theme-install",
    launch: "none", covers: { "install.style.theme": "B" } },
  { id: "bg-install", type: "action", glyph: "", label: "Install a wallpaper",
    run: "omarchy-theme-bg-install", launch: "menu",
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
  { id: "packages", type: "nav", page: "apps.packages", glyph: "󰣇", label: "Packages" }
]},

"apps.default": { title: "Default apps", rows: [
  { id: "browser", type: "nav", page: "apps.default.browser", glyph: "", label: "Browser",
    detailCmd: "omarchy-default-browser", covers: { "setup.default.browser": "N" } },
  { id: "terminal", type: "nav", page: "apps.default.terminal", glyph: "", label: "Terminal",
    detailCmd: "omarchy-default-terminal", covers: { "setup.default.terminal": "N" } },
  { id: "editor", type: "nav", page: "apps.default.editor", glyph: "", label: "Editor",
    detailCmd: "omarchy-default-editor", covers: { "setup.default.editor": "N" } },
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

"apps.default.agent": { title: "AI agent", reader: "omarchy-default-agent", rows: [
  { id: "claude", type: "choice", label: "Claude", value: "claude",
    when: "omarchy-cmd-present claude", write: "omarchy-default-agent claude",
    covers: { "setup.default.agent.claude": "N" } },
  { id: "codex", type: "choice", label: "Codex", value: "codex",
    when: "omarchy-cmd-present codex", write: "omarchy-default-agent codex",
    covers: { "setup.default.agent.codex": "N" } },
  { id: "copilot", type: "choice", label: "Copilot", value: "copilot",
    when: "omarchy-cmd-present copilot", write: "omarchy-default-agent copilot",
    covers: { "setup.default.agent.copilot": "N" } },
  { id: "crush", type: "choice", label: "Crush", value: "crush",
    when: "omarchy-cmd-present crush", write: "omarchy-default-agent crush",
    covers: { "setup.default.agent.crush": "N" } },
  { id: "gemini", type: "choice", label: "Gemini", value: "gemini",
    when: "omarchy-cmd-present gemini", write: "omarchy-default-agent gemini",
    covers: { "setup.default.agent.gemini": "N" } },
  { id: "grok", type: "choice", label: "Grok", value: "grok",
    when: "omarchy-cmd-present grok", write: "omarchy-default-agent grok",
    covers: { "setup.default.agent.grok": "N" } },
  { id: "omp", type: "choice", label: "omp", value: "omp",
    when: "omarchy-cmd-present omp", write: "omarchy-default-agent omp",
    covers: { "setup.default.agent.omp": "N" } },
  { id: "opencode", type: "choice", label: "OpenCode", value: "opencode",
    when: "omarchy-cmd-present opencode", write: "omarchy-default-agent opencode",
    covers: { "setup.default.agent.opencode": "N" } },
  { id: "pi", type: "choice", label: "Pi", value: "pi",
    when: "omarchy-cmd-present pi", write: "omarchy-default-agent pi",
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
  // Both are installed, so both stay hidden. Kept so the pair is represented
  // and the coverage map has somewhere to point.
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
    covers: { "setup.plugin": "N" } },
  { id: "restart", type: "action", glyph: "󰍜", label: "Restart shell",
    detail: "Bar, drawer, shade and gestures",
    run: "moarchy-restart-shell", launch: "none",
    covers: { "update.process.shell": "N", "update.process": "N" } },
  { id: "tmux", type: "action", glyph: "", label: "Reset tmux config",
    run: "omarchy-launch-floating-terminal-with-presentation omarchy-refresh-tmux",
    launch: "none", covers: { "update.config.tmux": "B", "update.config": "N" } }
]},

"shell.plugins": { title: "Plugins", rows: [
  { id: "enable", type: "action", glyph: "󰄬", label: "Enable a plugin",
    run: "omarchy-menu-plugin enable", launch: "menu",
    covers: { "setup.plugin.enable": "B" } },
  { id: "disable", type: "action", glyph: "󰅖", label: "Disable a plugin",
    run: "omarchy-menu-plugin disable", launch: "menu",
    covers: { "setup.plugin.disable": "B" } },
  { id: "add", type: "action", glyph: "󰖟", label: "Add a plugin",
    run: "omarchy-launch-floating-terminal-with-presentation 'omarchy-plugin-add'",
    launch: "none", covers: { "setup.plugin.add": "B" } },
  { id: "clone", type: "action", glyph: "󰆏", label: "Clone a plugin",
    run: "omarchy-menu-plugin clone", launch: "menu",
    covers: { "setup.plugin.clone": "B" } },
  // Upstream's guard is true here -- six moarchy.* manifests match it --
  // so this row can uninstall the phone UI. Kept, behind a confirm.
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
  { id: "ssh", type: "switch", glyph: "󰣀", label: "Remote access (SSH)",
    read: "systemctl is-enabled --quiet sshd && echo true || echo false",
    on: "omarchy-launch-floating-terminal-with-presentation omarchy-setup-security-sshd",
    off: "omarchy-launch-floating-terminal-with-presentation omarchy-remove-security-sshd",
    launch: "none",
    covers: { "setup.security.sshd": "B", "remove.security.sshd": "B" } },
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
    run: "moarchy-capture-screenshot", launch: "none",
    covers: { "trigger.capture.screenshot": "N", "trigger.capture": "N" } },
  { id: "record", type: "nav", page: "tools.record", glyph: "", label: "Screen record",
    when: "omarchy-cmd-present gpu-screen-recorder",
    covers: { "trigger.capture.screenrecord": "N" } },
  { id: "emoji", type: "action", glyph: "", label: "Emoji",
    run: "omarchy-menu-emoji", launch: "none",
    covers: { "trigger.emoji": "B" } },
  { id: "reminders", type: "nav", page: "tools.reminders", glyph: "󰢌", label: "Reminders",
    covers: { "trigger.reminder": "N" } },
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

"tools.reminders": { title: "Reminders", rows: [
  { id: "set", type: "action", glyph: "󰢌", label: "Set a reminder",
    run: "omarchy-reminder -i", launch: "menu",
    covers: { "trigger.reminder.set": "B" } },
  { id: "show", type: "action", glyph: "󰢌", label: "Show all",
    run: "omarchy-reminder show", launch: "menu",
    covers: { "trigger.reminder.show": "B" } },
  { id: "clear", type: "action", glyph: "󰢌", label: "Clear all",
    run: "omarchy-reminder clear", launch: "none",
    covers: { "trigger.reminder.clear": "B" } }
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
  { id: "power", type: "nav", page: "system.power", glyph: "󰐥", label: "Power" }
]},

"system.time": { title: "Date & time", rows: [
  { id: "timezone", type: "action", glyph: "", label: "Time zone",
    detailCmd: "timedatectl show -p Timezone --value",
    run: "omarchy-menu-timezone", launch: "menu",
    covers: { "update.timezone": "B" } },
  { id: "time", type: "action", glyph: "", label: "Set the time",
    run: "omarchy-launch-floating-terminal-with-presentation omarchy-update-time",
    launch: "none", covers: { "update.time": "B" } }
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
  { id: "aboutomarchy", type: "action", glyph: "", label: "About Omarchy",
    run: "omarchy-launch-about", launch: "tui", covers: { "about": "B" } }
]},

// A text page: one command, its output rendered as rows. Upstream's
// learn.keybindings ends in `less` with no terminal to draw in, so today the
// row shows nothing at all.
"about.keys": { title: "Keybindings", text: "omarchy-menu-keybindings --print", rows: [] },

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
