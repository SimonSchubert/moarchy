// The theme picker: every Omarchy theme as its own colours, one tap to apply.
//
// ---------------------------------------------------------------------------
// Why a dedicated screen and not the Omarchy menu's Style route
// ---------------------------------------------------------------------------
// The menu's theme list is a column of names. Names are the wrong handle for a
// choice that is entirely about colour -- "Ristretto" and "Miasma" tell you
// nothing, and picking by name means applying a theme to find out what it is,
// at seven seconds a go. Every theme already ships a colors.toml, so each row
// can simply be drawn in the theme it names.
//
// ---------------------------------------------------------------------------
// Why not the preview.png each theme ships
// ---------------------------------------------------------------------------
// They are 1800x1012 desktop screenshots, ~440KB each. Twenty-two of them
// decoded at once is more than this phone has to spare, and a 16:9 screenshot
// of a tiled desktop is illegible at 166px wide. The colours are the content;
// the screenshot is a wrapper around them.
//
// ---------------------------------------------------------------------------
// Why the swap is seamless already
// ---------------------------------------------------------------------------
// omarchy-theme-set ends by calling `omarchy-shell shell applyTheme` with the
// new palette, and the shell's Color singleton reloads in place. So the bar,
// the drawer, the shade and this screen all recolour without a restart, and
// without this plugin doing anything about it -- including while this screen is
// the thing on top. What it does have to handle is the seven seconds that
// regenerating every app's template takes on an A53: that is far too long to
// leave a tap looking like it missed.
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs.Commons

Item {
  id: root

  // Injected by the host. Not readonly, not required -- see the drawer.
  property string omarchyPath: Quickshell.env("OMARCHY_PATH")
                               || (Quickshell.env("HOME") + "/.local/share/omarchy")
  property var shell: null
  property var manifest: null
  property var barWidgetRegistry: null
  property var pluginRegistry: null
  property var service: null

  readonly property string pluginId: "mobileomarchy.themes"

  property bool opened: false
  property var themes: []
  property string currentSlug: ""
  property string pendingSlug: ""

  // Where Back goes. Set by whoever summoned this screen, so the chevron
  // returns to the list you came from instead of dropping you on the home
  // screen a level below where you were. Empty when opened on its own, which is
  // when closing outright is the right thing.
  property string returnTo: ""

  // And where in it. Settings is a stack of pages now, so returning to the
  // plugin is not enough -- without this the chevron lands on the Settings root
  // rather than on Appearance, one level below where you actually were.
  property string returnPage: ""

  // Must match mobileomarchy.gestures' own stripHeight. Duplicated rather than
  // read across plugins for the same reason the shade duplicates it: this
  // surface has to know the number even when the gestures plugin failed to
  // load, and a sheet that ran off the bottom of the screen in that case would
  // be worse than one that leaves the band unused.
  //
  // Not 20 pixels. Style.space rounds a *scaled* value and the scale comes from
  // the theme's shell.toml, so this is nearer 23 at the default ~1.15 -- which
  // is why nothing here or in the selftest writes the number down.
  readonly property int gestureStrip: Style.space(20)
  readonly property int radiusCard: Style.space(20)

  readonly property color surface: Color.menu.background
  // NOT `onSurface` / `onAccent`, however much the Material role names want to
  // be spelled that way. QML reserves the `on<Uppercase>` prefix for signal
  // handlers, so a property declared there is never readable: the binding
  // evaluates to undefined, undefined assigned to a `color` is #000000, and
  // nothing is logged. The symptom is every glyph and label painted pure black
  // on a dark tile while the properties either side of them are fine.
  readonly property color textOnSurface: Color.menu.text
  readonly property color container: Util.alpha(Color.menu.text, 0.08)
  // Computed per theme, not fixed. A flat 0.6 reaches 2.72:1 on rose-pine --
  // measured across all 22 colors.toml files -- and no single alpha clears AA
  // everywhere without being loud enough to stop reading as secondary. Walk
  // from quiet toward the foreground and stop the moment it is legible. Same
  // arithmetic as mobileomarchy.settings/Settings.qml; four small pure
  // functions rather than an import, because plugins are separate directories
  // and a relative path across them is the kind of thing that breaks silently.
  readonly property color subdued: root.readableOn(root.surface, Color.menu.text,
                                                   0.55, 4.5)

  function luminance(c) {
    function chan(v) { return v <= 0.03928 ? v / 12.92 : Math.pow((v + 0.055) / 1.055, 2.4) }
    return 0.2126 * chan(c.r) + 0.7152 * chan(c.g) + 0.0722 * chan(c.b)
  }

  function contrastRatio(a, b) {
    var la = root.luminance(a), lb = root.luminance(b)
    return (Math.max(la, lb) + 0.05) / (Math.min(la, lb) + 0.05)
  }

  function mix(bg, fg, a) {
    return Qt.rgba(bg.r + a * (fg.r - bg.r),
                   bg.g + a * (fg.g - bg.g),
                   bg.b + a * (fg.b - bg.b), 1)
  }

  function readableOn(bg, fg, from, minRatio) {
    for (var a = from; a < 1.0; a += 0.01) {
      var c = root.mix(bg, fg, a)
      if (root.contrastRatio(c, bg) >= minRatio) return c
    }
    return fg
  }

  function open(payloadJson) {
    if (root.shell && typeof root.shell.isPluginOpen === "function") {
      if (root.shell.isPluginOpen("mobileomarchy.shade")) root.shell.hide("mobileomarchy.shade")
      if (root.shell.isPluginOpen("mobileomarchy.drawer")) root.shell.hide("mobileomarchy.drawer")
    }
    root.opened = true
    root.returnTo = ""
    root.returnPage = ""
    try {
      var payload = JSON.parse(String(payloadJson || "{}"))
      if (payload && payload.returnTo) root.returnTo = String(payload.returnTo)
      if (payload && payload.page) root.returnPage = String(payload.page)
    } catch (e) {
      // A malformed payload is not worth refusing to open over.
    }
    root.scan()
  }

  function close() {
    root.opened = false
  }

  function dismiss() {
    var back = root.returnTo
    var page = root.returnPage
    if (root.shell && typeof root.shell.hide === "function") root.shell.hide(root.pluginId)
    else root.close()
    if (back && root.shell && typeof root.shell.summon === "function")
      root.shell.summon(back, page ? JSON.stringify({ page: page }) : "{}")
  }

  function scan(): void {
    if (!themeScan.running) themeScan.running = true
  }

  // One subprocess for the whole catalogue rather than a FileView per theme.
  // Twenty-two file watchers for data that only changes when a theme is
  // installed is a lot of inotify for nothing, and the parse is trivial.
  //
  // The display name has to be derived exactly the way omarchy-theme-list
  // derives it -- title-case each hyphen-separated word, then swap hyphens for
  // spaces -- because omarchy-theme-set is given that name and looks the
  // directory back up from it. "rose-pine" must come back as "Rose Pine" and
  // nothing else.
  Process {
    id: themeScan
    command: ["python3", "-c",
      "import glob, json, os, re\n" +
      "home = os.path.expanduser('~')\n" +
      "bases = [home + '/.config/omarchy/themes', os.environ.get('OMARCHY_PATH', home + '/.local/share/omarchy') + '/themes']\n" +
      "seen = set()\n" +
      "rows = []\n" +
      "for base in bases:\n" +
      "    for d in sorted(glob.glob(base + '/*')):\n" +
      "        slug = os.path.basename(d)\n" +
      "        if slug in seen or not os.path.isdir(d):\n" +
      "            continue\n" +
      "        c = {}\n" +
      "        try:\n" +
      "            for line in open(os.path.join(d, 'colors.toml')):\n" +
      "                m = re.match(r'\\s*([a-z_]+)\\s*=\\s*\"([^\"]+)\"', line)\n" +
      "                if m:\n" +
      "                    c[m.group(1)] = m.group(2)\n" +
      "        except OSError:\n" +
      "            continue\n" +
      "        if 'background' not in c:\n" +
      "            continue\n" +
      "        seen.add(slug)\n" +
      "        name = re.sub(r'(^|-)([a-z])', lambda m: m.group(1) + m.group(2).upper(), slug).replace('-', ' ')\n" +
      "        rows.append({'slug': slug, 'name': name, 'mode': c.get('mode', 'dark'),\n" +
      "                     'background': c['background'], 'foreground': c.get('foreground', '#ffffff'),\n" +
      "                     'accent': c.get('accent', c.get('blue', '#888888')),\n" +
      "                     'chips': [c.get(k, '#888888') for k in ('accent', 'red', 'green', 'yellow', 'blue', 'magenta')]})\n" +
      // current/theme is a staged *copy* of the theme, not a symlink to it, so
      // its basename is always the literal string "theme". The slug lives in
      // current/theme.name, which is what omarchy-theme-current reads.
      "cur = ''\n" +
      "try:\n" +
      "    cur = open(home + '/.local/state/omarchy/current/theme.name').read().strip()\n" +
      "except OSError:\n" +
      "    pass\n" +
      "print(json.dumps({'current': cur, 'themes': rows}))\n"]
    stdout: StdioCollector {
      onStreamFinished: {
        try {
          var parsed = JSON.parse(String(text || "{}"))
          root.themes = parsed.themes || []
          root.currentSlug = String(parsed.current || "")
        } catch (e) {
          console.warn("theme scan failed to parse:", e)
        }
      }
    }
  }

  // Run, not execDetached, so the exit tells us when to re-read which theme is
  // current. Detached would leave the tick sitting on the old card until the
  // user reopened the screen.
  Process {
    id: applyTheme
    property string slug: ""
    onExited: {
      root.pendingSlug = ""
      root.scan()
    }
  }

  function apply(row) {
    if (!row || root.pendingSlug !== "" || row.slug === root.currentSlug) return
    root.pendingSlug = row.slug
    applyTheme.slug = row.slug
    // By display name, because that is omarchy-theme-set's argument. Absolute
    // path for the same reason the gestures plugin uses one: a shell started
    // without the session environment has only /usr/bin on PATH, and the call
    // would report success while nothing happened.
    applyTheme.command = [root.omarchyPath + "/bin/omarchy-theme-set", String(row.name)]
    applyTheme.running = true
  }

  IpcHandler {
    target: "themes"

    function state(): string { return root.opened ? "open" : "closed" }
    function open(): string {
      if (root.shell) root.shell.summon(root.pluginId, "{}")
      return "ok"
    }
    function close(): string { root.dismiss(); return "ok" }

    // What the compositor actually granted this surface. Nothing else can
    // answer it: sway's IPC does not list layer surfaces, so `swaymsg -t
    // get_tree` is silent about every one of them.
    //
    // `h` is the configure this window received, so it is the compositor's
    // number rather than ours -- which is what makes it evidence. `margin` is
    // only our own property read back: it proves the assignment was accepted,
    // never that it was honoured. When the two disagree, `h` is the one that
    // is telling the truth (docs/gestures.md I2).
    //
    // `gap` is how far the last content pixel comes to rest above the bottom of
    // the surface. It must never fall below `strip`, or a row settles under the
    // home pill where it cannot be tapped (I4, I5).
    //
    // Meaningless while the surface is closed or mid-slide: open it first.
    function geometry(): string {
      var gap = Math.round(themeWindow.height - grid.mapToItem(null, 0, grid.height).y + grid.bottomMargin)
      return "w=" + themeWindow.width
           + " h=" + themeWindow.height
           + " margin=" + themeWindow.margins.bottom
           + " strip=" + root.gestureStrip
           + " gap=" + gap
           + " screen=" + (themeWindow.screen
               ? themeWindow.screen.width + "x" + themeWindow.screen.height : "?")
    }

    function toggle(): string {
      if (root.shell) root.shell.toggle(root.pluginId, "{}")
      return root.opened ? "open" : "closed"
    }
    function current(): string { return root.currentSlug }
    // Lets the picker be exercised without a finger, and without waiting seven
    // seconds inside a tap handler to find out whether it worked.
    function set(slug: string): string {
      for (var i = 0; i < root.themes.length; i++) {
        if (root.themes[i].slug === slug) { root.apply(root.themes[i]); return "applying " + slug }
      }
      return "unknown theme: " + slug
    }
  }

  PanelWindow {
    id: themeWindow

    visible: root.opened
    anchors { top: true; bottom: true; left: true; right: true }
    color: "transparent"

    WlrLayershell.namespace: "mobileomarchy-themes"
    WlrLayershell.layer: WlrLayer.Top

    // Reserve nothing, but be arranged into what the exclusive surfaces left,
    // so the status bar stays visible and the home pill keeps working. Same
    // arrangement as the drawer, and for the same reason.
    exclusionMode: ExclusionMode.Normal
    exclusiveZone: 0

    // Extend past the bottom of the usable area, under the gesture strip. A
    // zero exclusive zone means sway arranges this *into* what the exclusive
    // surfaces left, so without this the sheet stops at the top of the strip
    // and a band of wallpaper -- or of the app behind -- shows under it with
    // the pill drawn on it (docs/gestures.md I1).
    //
    // The exclusion mode is deliberately untouched: the strip still reserves
    // its band off every window, because a margin moves only this surface's own
    // bottom edge. Reserving and drawing-under are separate questions.
    //
    // Negative is legal, not a trick: wlroots stores layer-shell margins as
    // int32_t and computes `box.height = bounds.height - (margin.top +
    // margin.bottom)` with no clamping, and sway delegates to it and adds no
    // validation of its own.
    margins.bottom: -root.gestureStrip
    WlrLayershell.keyboardFocus: root.opened ? WlrKeyboardFocus.Exclusive
                                             : WlrKeyboardFocus.None

    Rectangle {
      anchors.fill: parent
      color: root.surface
      opacity: root.opened ? 1 : 0
      Behavior on opacity { NumberAnimation { duration: 140 } }

      Keys.onEscapePressed: root.dismiss()

      Column {
        anchors.fill: parent
        anchors.leftMargin: Style.space(12)
        anchors.rightMargin: Style.space(12)
        anchors.topMargin: Style.space(8)
        anchors.bottomMargin: Style.space(8)
        spacing: Style.space(10)

        // ------------------------------------------------------- header
        Item {
          width: parent.width
          height: Style.space(44)

          Rectangle {
            id: backButton
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            width: Style.space(38)
            height: width
            radius: width / 2
            color: root.container

            Text {
              anchors.centerIn: parent
              text: "󰅁"
              font.family: Style.font.family
              font.pixelSize: Style.font.icon
              color: root.textOnSurface
            }
            MouseArea { anchors.fill: parent; onClicked: root.dismiss() }
          }

          Text {
            anchors.left: backButton.right
            anchors.leftMargin: Style.space(12)
            anchors.verticalCenter: parent.verticalCenter
            text: "Themes"
            font.family: Style.font.family
            font.pixelSize: Style.font.heading
            color: root.textOnSurface
          }

          Text {
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            text: root.pendingSlug !== "" ? "Applying\u2026" : root.themes.length + " themes"
            font.family: Style.font.family
            font.pixelSize: Style.font.caption
            color: root.subdued
          }
        }

        // --------------------------------------------------------- grid
        GridView {
          id: grid
          width: parent.width
          height: Math.max(0, parent.height - y)
          clip: true
          cellWidth: Math.floor(width / 2)
          cellHeight: Style.space(96)
          // Scroll padding, so the last card rests a strip clear of the home
          // pill now that the sheet runs under it (docs/gestures.md I4).
          bottomMargin: root.gestureStrip
          model: root.themes
          cacheBuffer: cellHeight * 2

          delegate: Item {
            id: cell
            required property var modelData
            readonly property bool isCurrent: modelData.slug === root.currentSlug
            readonly property bool isPending: modelData.slug === root.pendingSlug

            width: grid.cellWidth
            height: grid.cellHeight

            Rectangle {
              anchors.fill: parent
              anchors.margins: Style.space(5)
              radius: root.radiusCard
              // Painted in the theme it names. That is the whole point of the
              // screen: the card is the preview.
              color: cell.modelData.background

              // The current theme gets a ring in its own accent rather than a
              // tick in a corner -- at this size a tick is four pixels of
              // nothing, and the ring reads at a glance across the grid.
              border.width: cell.isCurrent ? Math.max(2, Style.space(2)) : Math.max(1, Style.space(1))
              border.color: cell.isCurrent
                ? cell.modelData.accent
                : Util.alpha(cell.modelData.foreground, 0.18)

              opacity: root.pendingSlug !== "" && !cell.isPending ? 0.45 : 1
              Behavior on opacity { NumberAnimation { duration: 140 } }

              Column {
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                anchors.leftMargin: Style.space(12)
                anchors.rightMargin: Style.space(12)
                spacing: Style.space(10)

                Row {
                  spacing: Style.space(5)
                  Repeater {
                    model: cell.modelData.chips
                    delegate: Rectangle {
                      required property var modelData
                      width: Style.space(12)
                      height: width
                      radius: width / 2
                      color: modelData
                    }
                  }
                }

                Row {
                  width: parent.width
                  spacing: Style.space(6)

                  Text {
                    width: parent.width - (cell.isPending || cell.isCurrent ? Style.space(20) : 0)
                    text: cell.modelData.name
                    font.family: Style.font.family
                    font.pixelSize: Style.font.bodySmall
                    color: cell.modelData.foreground
                    elide: Text.ElideRight
                  }

                  Text {
                    anchors.verticalCenter: parent.verticalCenter
                    visible: cell.isPending || cell.isCurrent
                    text: cell.isPending ? "\u2026" : "󰄬"
                    font.family: Style.font.family
                    font.pixelSize: Style.font.bodySmall
                    color: cell.modelData.accent
                  }
                }
              }

              MouseArea {
                anchors.fill: parent
                // Nothing is queued while one is applying: omarchy-theme-set
                // takes a lock and a second call would sit behind it for
                // another seven seconds with no way to say so.
                enabled: root.pendingSlug === ""
                onClicked: root.apply(cell.modelData)
              }
            }
          }
        }
      }
    }
  }
}
