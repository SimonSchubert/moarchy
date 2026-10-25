// The OWL widget store (docs/owl.md §B): Omalauncher's StoreScreen, widgets only.
//
// A grid of the store's widgets, each drawn in the current theme; a search
// field and chips over it; a widget's page with what it runs and what it needs
// before the button that installs it. Everything it knows and does goes through
// `moarchy-owl`, the one writer of what is installed (OW15), so the screen and
// an agent see the same thing.
import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Commons as Upstream
import qs.Ui as Ui
import "../moarchy.common" as Shared

Item {
  id: view

  // Settings itself: its colour roles, radii and shell.
  property var host: null

  property var widgets: []
  property string store: ""
  property int age: -1
  property bool offline: false
  property string problem: ""
  property bool loading: false
  // What the person is looking at: the grid, or one widget's page.
  property var selected: null
  property var missing: []           // the selected widget's packages not installed
  property string busy: ""           // "installing…", while moarchy-owl runs
  property string message: ""        // what the last action said

  property string query: ""
  property string tab: "all"

  // The theme's slug, for the preview drawn in it (OW9).
  property string themeSlug: ""
  FileView {
    path: (Quickshell.env("HOME") || "") + "/.local/state/omarchy/current/theme.name"
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: view.themeSlug = text().trim()
  }

  Component.onCompleted: view.load(false)

  function load(refresh): void {
    view.loading = true
    catalog.command = refresh ? ["moarchy-owl", "catalog", "--refresh"] : ["moarchy-owl", "catalog"]
    catalog.running = true
  }

  Process {
    id: catalog
    stdout: StdioCollector { id: catalogOut }
    stderr: StdioCollector { id: catalogErr }
    onExited: (code, status) => {
      view.loading = false
      if (code !== 0) {
        view.problem = String(catalogErr.text).replace(/^moarchy-owl: /, "").trim() || "could not read the store"
        return
      }
      try {
        var d = JSON.parse(String(catalogOut.text))
        view.widgets = d.widgets || []
        view.store = d.store || ""
        view.age = d.age === null ? -1 : d.age
        view.offline = !!d.offline
        view.problem = ""
        if (view.selected) view.selected = view.entry(view.selected.id)
      } catch (e) {
        view.problem = "the store's catalogue did not read"
      }
    }
  }

  function entry(id) {
    for (var i = 0; i < view.widgets.length; i++) if (view.widgets[i].id === id) return view.widgets[i]
    return null
  }

  // OW9. The chips: all, new, installed, then the catalogue's categories.
  readonly property var tabs: {
    var cats = []
    for (var i = 0; i < view.widgets.length; i++) {
      var c = view.widgets[i].category
      if (c && cats.indexOf(c) < 0) cats.push(c)
    }
    cats.sort()
    return ["all", "new", "installed"].concat(cats)
  }

  readonly property var shown: {
    var q = view.query.trim().toLowerCase()
    return view.widgets.filter(function (w) {
      if (view.tab === "new" && !w["new"]) return false
      if (view.tab === "installed" && !w.installed) return false
      if (view.tab !== "all" && view.tab !== "new" && view.tab !== "installed" && w.category !== view.tab) return false
      if (!q) return true
      return (String(w.name) + " " + String(w.description) + " " + String(w.author)).toLowerCase().indexOf(q) >= 0
    })
  }

  // The preview drawn in the current theme, else the plain one.
  function previewUrl(w) {
    if (!w) return ""
    var p = (w.themes && w.themes[view.themeSlug]) || w.preview || ""
    return p ? view.store + p : ""
  }

  function open(w, keepMessage): void {
    view.selected = w
    if (!keepMessage) view.message = ""
    view.missing = []
    show.command = ["moarchy-owl", "show", w.id]
    show.running = true
  }
  Process {
    id: show
    stdout: StdioCollector { id: showOut }
    onExited: {
      try { view.missing = JSON.parse(String(showOut.text)).missing || [] } catch (e) { view.missing = [] }
    }
  }

  // OW11-OW14, through the one writer. --yes only when the page already said
  // what changed and the person tapped the button that says "anyway".
  function act(verb): void {
    var w = view.selected
    if (!w || view.busy !== "") return
    var cmd = ["moarchy-owl", verb, w.id]
    if (verb === "update" && (w.changed || w.edited)) cmd.push("--yes")
    view.busy = verb === "install" ? "installing…" : verb === "update" ? "updating…" : "removing…"
    view.message = ""
    action.command = cmd
    action.running = true
  }
  Process {
    id: action
    stdout: StdioCollector { id: actionOut }
    stderr: StdioCollector { id: actionErr }
    onExited: (code, status) => {
      view.busy = ""
      var said = (String(actionOut.text).trim() + "\n" + String(actionErr.text).trim()).trim()
      view.message = said.replace(/moarchy-owl: /g, "")
      view.load(false)
      // What the action said stays under the button it answers.
      if (view.selected) view.open(view.entry(view.selected.id) || view.selected, true)
    }
  }

  // For `settings rows` on this page.
  function report(): string {
    var out = ["widgets=" + view.widgets.length + " shown=" + view.shown.length + " tab=" + view.tab
               + " offline=" + view.offline + (view.problem ? " problem=" + view.problem : "")]
    if (view.selected)
      out.push("selected=" + view.selected.id + " installed=" + (view.selected.installed || "no")
               + " missing=" + view.missing.join(",") + (view.message ? " message=" + view.message : ""))
    return out.join("\n")
  }

  component Label: Text {
    font.family: Style.font.family
    font.pixelSize: Style.font.caption
    font.weight: view.host ? view.host.textWeight : Font.Normal
    color: view.host ? view.host.subdued : "transparent"
    wrapMode: Text.Wrap
  }

  component Chip: Item {
    id: chip
    property string label: ""
    property bool on: false
    // A chip whose words are its colour whether chosen or not: `remove`.
    property bool inked: false
    property color ink: view.host ? view.host.accent : "transparent"
    signal activated()
    width: chipText.implicitWidth + Style.space(20)
    height: Style.space(36)
    Rectangle {
      anchors.fill: parent
      radius: view.host ? view.host.radiusOn(height) : 0
      color: chip.on ? (view.host ? view.host.containerHigh : "transparent") : "transparent"
      border.width: 1
      border.color: view.host ? view.host.container : "transparent"
      Shared.PressVeil {
        anchors.fill: parent
        radius: parent.radius
        ink: chip.ink
        on: chipArea.pressed
      }
    }
    Text {
      id: chipText
      anchors.centerIn: parent
      text: chip.label
      font.family: Style.font.family
      font.pixelSize: Style.font.bodySmall
      font.weight: view.host ? view.host.textWeight : Font.Normal
      color: chip.on || chip.inked ? chip.ink : (view.host ? view.host.textOnSurface : "transparent")
    }
    MouseArea {
      id: chipArea
      anchors.fill: parent
      onClicked: chip.activated()
    }
  }

  // ------------------------------------------------------------------ grid
  Column {
    id: top
    width: parent.width
    spacing: Style.space(8)
    visible: !view.selected

    Rectangle {
      width: parent.width
      height: Style.space(44)
      radius: view.host ? view.host.radiusCard : 0
      color: view.host ? view.host.container : "transparent"
      Ui.TextField {
        id: search
        anchors.fill: parent
        anchors.leftMargin: Style.space(14)
        anchors.rightMargin: Style.space(14)
        background: null
        verticalPadding: 0
        leftPadding: 0
        rightPadding: 0
        verticalAlignment: TextInput.AlignVCenter
        foreground: view.host ? view.host.textOnSurface : "white"
        accent: view.host ? view.host.accent : "white"
        placeholderText: "search " + view.widgets.length + " widgets"
        onTextChanged: view.query = text
        // G14. The tap is the request for the keyboard, not focus arriving.
        Shared.Osk { id: osk }
        MouseArea {
          anchors.fill: parent
          propagateComposedEvents: true
          onPressed: mouse => { osk.show(); mouse.accepted = false }
        }
      }
    }

    ListView {
      width: parent.width
      height: Style.space(36)
      orientation: ListView.Horizontal
      spacing: Style.space(6)
      clip: true
      boundsBehavior: Flickable.StopAtBounds
      model: view.tabs
      delegate: Chip {
        required property string modelData
        label: modelData
        on: view.tab === modelData
        onActivated: view.tab = modelData
      }
    }

    Label {
      width: parent.width
      visible: text !== ""
      text: view.problem !== "" ? view.problem
          : view.loading && view.widgets.length === 0 ? "loading…"
          : view.offline ? "offline: the store as it was " + Math.round(view.age / 3600) + " h ago"
          : view.shown.length === 0 ? (view.query ? "nothing matches \"" + view.query.trim() + "\"" : "none here")
          : ""
    }
  }

  GridView {
    id: grid
    visible: !view.selected
    anchors.top: top.bottom
    anchors.topMargin: Style.space(10)
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.bottom: parent.bottom
    clip: true
    cellWidth: width / 2
    cellHeight: Style.space(170)
    model: view.shown
    boundsBehavior: Flickable.StopAtBounds
    cacheBuffer: Style.space(170) * 2

    delegate: Item {
      id: card
      required property var modelData
      width: grid.cellWidth
      height: grid.cellHeight

      Rectangle {
        anchors.fill: parent
        anchors.margins: Style.space(4)
        radius: view.host ? view.host.radiusTile : 0
        color: view.host ? view.host.container : "transparent"
        clip: true

        Shared.PressVeil {
          anchors.fill: parent
          radius: parent.radius
          ink: view.host ? view.host.textOnSurface : "transparent"
          on: cardArea.pressed
        }
        Image {
          id: preview
          anchors.top: parent.top
          anchors.left: parent.left
          anchors.right: parent.right
          anchors.margins: Style.space(8)
          height: parent.height - Style.space(56)
          source: view.previewUrl(card.modelData)
          fillMode: Image.PreserveAspectFit
          asynchronous: true
          sourceSize.width: width * 2
        }
        Column {
          anchors.left: parent.left
          anchors.right: parent.right
          anchors.bottom: parent.bottom
          anchors.margins: Style.space(10)
          Text {
            width: parent.width
            text: card.modelData.name
            elide: Text.ElideRight
            font.family: Style.font.family
            font.pixelSize: Style.font.bodySmall
            font.weight: view.host ? view.host.textWeight : Font.Normal
            color: view.host ? view.host.textOnSurface : "transparent"
          }
          Text {
            width: parent.width
            text: card.modelData.update ? "update" : card.modelData.installed ? "on home"
                : card.modelData["new"] ? "new" : card.modelData.author
            elide: Text.ElideRight
            font.family: Style.font.family
            font.pixelSize: Style.font.caption
            font.weight: view.host ? view.host.textWeight : Font.Normal
            color: card.modelData.update || card.modelData["new"] ? (view.host ? view.host.accent : "transparent")
                 : (view.host ? view.host.subdued : "transparent")
          }
        }
        MouseArea {
          id: cardArea
          anchors.fill: parent
          onClicked: view.open(card.modelData)
        }
      }
    }
  }

  // ------------------------------------------------------- a widget's page
  // OW10. What it is, what it runs and what it needs, then the one button.
  Flickable {
    id: page
    visible: !!view.selected
    anchors.fill: parent
    contentHeight: detail.implicitHeight + Style.space(24)
    boundsBehavior: Flickable.StopAtBounds
    clip: true

    Column {
      id: detail
      width: page.width
      spacing: Style.space(10)
      readonly property var w: view.selected || ({})

      Chip {
        label: "‹ widgets"
        onActivated: { view.selected = null; view.message = "" }
      }

      Image {
        width: parent.width
        height: Style.space(220)
        source: view.previewUrl(view.selected)
        fillMode: Image.PreserveAspectFit
        asynchronous: true
        sourceSize.width: width * 2
      }

      Text {
        width: parent.width
        text: String(detail.w.name || "")
        font.family: Style.font.family
        font.pixelSize: Style.font.title
        font.weight: view.host ? view.host.textWeight : Font.Normal
        color: view.host ? view.host.textOnSurface : "transparent"
      }
      Label {
        width: parent.width
        text: [detail.w.category || "other", detail.w.author, "v" + detail.w.version, detail.w.license,
               detail.w.size ? detail.w.size[0] + "x" + detail.w.size[1] : ""].filter(function (x) { return !!x }).join(" · ")
      }
      Text {
        width: parent.width
        text: String(detail.w.description || "")
        wrapMode: Text.Wrap
        font.family: Style.font.family
        font.pixelSize: Style.font.bodySmall
        font.weight: view.host ? view.host.textWeight : Font.Normal
        color: view.host ? view.host.textOnSurface : "transparent"
      }

      // OW12. Before the button, never after it.
      Label {
        width: parent.width
        text: "what it runs"
        color: view.host ? view.host.textOnSurface : "transparent"
      }
      Label {
        width: parent.width
        text: (detail.w.commands && detail.w.commands.length) ? detail.w.commands.join("\n") : "nothing"
        font.family: "JetBrainsMono Nerd Font"
        maximumLineCount: 12
        elide: Text.ElideRight
      }
      Label {
        width: parent.width
        text: "what it needs"
        color: view.host ? view.host.textOnSurface : "transparent"
      }
      Label {
        width: parent.width
        readonly property var pkgs: detail.w.requires && detail.w.requires.pacman ? detail.w.requires.pacman : []
        text: pkgs.length === 0 ? "nothing" : pkgs.map(function (p) {
          return (view.missing.indexOf(p) >= 0 ? "✗ " : "✓ ") + p
        }).join("   ")
      }

      Label {
        width: parent.width
        visible: !!detail.w.changed
        text: "its commands or packages changed since the version you approved"
        color: Upstream.Color.urgent
      }
      Label {
        width: parent.width
        visible: !!detail.w.edited && !!detail.w.update
        text: "your changes to it go"
        color: Upstream.Color.urgent
      }
      Label {
        width: parent.width
        visible: detail.w.supported === false
        text: "needs a newer runtime (owl " + detail.w.owl + ")"
        color: Upstream.Color.urgent
      }

      Row {
        spacing: Style.space(8)
        visible: detail.w.supported !== false
        Chip {
          visible: !detail.w.installed
          label: view.busy !== "" ? view.busy : "add to home"
          on: true
          onActivated: view.act("install")
        }
        Chip {
          visible: !!detail.w.installed && !!detail.w.update
          label: view.busy !== "" ? view.busy
               : (detail.w.changed || detail.w.edited ? "update anyway " : "update ")
                 + detail.w.installed + " → " + detail.w.version
          on: true
          onActivated: view.act("update")
        }
        Chip {
          visible: !!detail.w.installed && view.busy === ""
          label: "remove"
          inked: true
          ink: Upstream.Color.urgent
          onActivated: view.act("remove")
        }
      }
      Label {
        width: parent.width
        visible: view.message !== ""
        text: view.message
      }
    }
  }
}
