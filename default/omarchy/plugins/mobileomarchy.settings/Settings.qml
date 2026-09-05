// Settings: the one place the Omarchy launcher's non-app routes live.
//
// ---------------------------------------------------------------------------
// Why these moved out of the app drawer
// ---------------------------------------------------------------------------
// The drawer had a row of four of them across the top. That was the wrong
// place twice over: it cost a row of app slots on a screen that only fits
// four across, and it put system administration one mis-tap away from
// launching an app. A phone's launcher is for launching; everything else
// belongs behind a gear. So the drawer is now nothing but apps and a search
// field, and this screen is reached from the shade's gear -- which is exactly
// where Android puts it, and it is already the surface you pull down when you
// want to change something.
//
// ---------------------------------------------------------------------------
// Rows that are screens, and rows that are still the menu
// ---------------------------------------------------------------------------
// `plugin` wins over `route`. Themes is the first route to get a phone screen
// of its own, because picking a theme by name from a list is the one place the
// desktop menu is actively bad on a phone. The rest still summon
// `omarchy.menu` at their route: those are lists of labelled commands, which a
// list of labelled commands renders perfectly well, and reimplementing them
// would mean re-encoding what each one does. They become screens the same way
// Themes did, one at a time, when there is something to gain by it.
//
// Icons are the menu's own, read out of default/omarchy/omarchy-menu.jsonc, so
// a row and the screen it opens are marked with the same glyph. Written as
// escapes because they live in a private use area where a stray editor or a
// terminal round-trip can eat them.
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

  readonly property string pluginId: "mobileomarchy.settings"

  property bool opened: false
  property string currentTheme: ""

  readonly property int radiusCard: Style.space(18)

  // NOT `onSurface` / `onAccent`: QML reserves the `on<Uppercase>` prefix for
  // signal handlers, so a property declared there reads back as undefined,
  // which a `color` renders as pure black with nothing logged.
  readonly property color surface: Color.menu.background
  readonly property color textOnSurface: Color.menu.text
  readonly property color container: Util.alpha(Color.menu.text, 0.08)
  readonly property color subdued: Util.alpha(Color.menu.text, 0.6)

  // `detail` is a binding evaluated per row, so a row can show its own current
  // value without this screen knowing what any particular row means.
  readonly property var rows: [
    { plugin: "mobileomarchy.themes", route: "style",  glyph: "", label: "Themes",
      detail: root.currentTheme },
    { plugin: "", route: "setup",             glyph: "", label: "Setup",       detail: "" },
    { plugin: "", route: "install",           glyph: "󰉉", label: "Install",    detail: "" },
    { plugin: "", route: "remove",            glyph: "󰭌", label: "Remove",     detail: "" },
    { plugin: "", route: "update",            glyph: "",  label: "Update",     detail: "" },
    { plugin: "", route: "learn.keybindings", glyph: "",  label: "Keybindings", detail: "" },
    { plugin: "", route: "about",             glyph: "",  label: "About",      detail: "" },
    { plugin: "", route: "system",            glyph: "",  label: "System",     detail: "" }
  ]

  function open(payloadJson) {
    if (root.shell && typeof root.shell.isPluginOpen === "function") {
      var others = ["mobileomarchy.shade", "mobileomarchy.drawer", "mobileomarchy.themes"]
      for (var i = 0; i < others.length; i++)
        if (root.shell.isPluginOpen(others[i])) root.shell.hide(others[i])
    }
    root.opened = true
    themeProbe.running = true
  }

  function close() { root.opened = false }

  function dismiss() {
    if (root.shell && typeof root.shell.hide === "function") root.shell.hide(root.pluginId)
    else root.close()
  }

  // The Themes row shows which theme is on, so the screen answers the question
  // before you open the one below it. omarchy-theme-current is the same reader
  // the rest of Omarchy uses -- current/theme is a staged copy, not a symlink,
  // so its basename is always the literal string "theme".
  Process {
    id: themeProbe
    command: ["bash", "-c",
      "sed -E 's/(^|-)([a-z])/\\1\\u\\2/g; s/-/ /g' " +
      "\"$HOME/.local/state/omarchy/current/theme.name\" 2>/dev/null"]
    stdout: StdioCollector {
      onStreamFinished: root.currentTheme = String(text || "").trim()
    }
  }

  // Opening a screen from here tells it where Back should go, so the chevron
  // returns to this list rather than dumping the user on the home screen two
  // levels down. A screen opened any other way gets no returnTo and closes
  // outright, which is what a single-level open should do.
  function openRow(row) {
    if (!row || !root.shell || typeof root.shell.summon !== "function") return
    root.dismiss()
    if (row.plugin)
      root.shell.summon(row.plugin, JSON.stringify({ returnTo: root.pluginId }))
    else
      root.shell.summon("omarchy.menu", JSON.stringify({ menu: row.route }))
  }

  IpcHandler {
    target: "settings"

    function state(): string { return root.opened ? "open" : "closed" }
    function open(): string {
      if (root.shell) root.shell.summon(root.pluginId, "{}")
      return "ok"
    }
    function close(): string { root.dismiss(); return "ok" }
    function toggle(): string {
      if (root.shell) root.shell.toggle(root.pluginId, "{}")
      return root.opened ? "open" : "closed"
    }
  }

  PanelWindow {
    id: settingsWindow

    visible: root.opened
    anchors { top: true; bottom: true; left: true; right: true }
    color: "transparent"

    WlrLayershell.namespace: "mobileomarchy-settings"
    WlrLayershell.layer: WlrLayer.Top

    // Reserve nothing, but be arranged into what the exclusive surfaces left,
    // so the status bar stays visible and the home pill keeps working.
    exclusionMode: ExclusionMode.Normal
    exclusiveZone: 0
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
            text: "Settings"
            font.family: Style.font.family
            font.pixelSize: Style.font.heading
            color: root.textOnSurface
          }
        }

        // --------------------------------------------------------- rows
        ListView {
          id: rowList
          width: parent.width
          height: Math.max(0, parent.height - y)
          clip: true
          spacing: Style.space(6)
          model: root.rows

          delegate: Rectangle {
            id: rowCard
            required property var modelData
            width: rowList.width
            height: Style.space(58)
            radius: root.radiusCard
            color: root.container

            Row {
              anchors.fill: parent
              anchors.leftMargin: Style.space(16)
              anchors.rightMargin: Style.space(14)
              spacing: Style.space(14)

              Text {
                anchors.verticalCenter: parent.verticalCenter
                text: rowCard.modelData.glyph
                font.family: Style.font.family
                font.pixelSize: Style.font.iconLarge
                color: root.textOnSurface
              }

              Column {
                anchors.verticalCenter: parent.verticalCenter
                width: parent.width - Style.space(64)
                spacing: 0

                Text {
                  width: parent.width
                  text: rowCard.modelData.label
                  font.family: Style.font.family
                  font.pixelSize: Style.font.body
                  color: root.textOnSurface
                  elide: Text.ElideRight
                }
                Text {
                  width: parent.width
                  visible: text !== ""
                  text: rowCard.modelData.detail || ""
                  font.family: Style.font.family
                  font.pixelSize: Style.font.caption
                  color: root.subdued
                  elide: Text.ElideRight
                }
              }

              Text {
                anchors.verticalCenter: parent.verticalCenter
                text: "󰅂"
                font.family: Style.font.family
                font.pixelSize: Style.font.iconSmall
                color: root.subdued
              }
            }

            MouseArea {
              anchors.fill: parent
              onClicked: root.openRow(rowCard.modelData)
            }
          }
        }
      }
    }
  }
}
