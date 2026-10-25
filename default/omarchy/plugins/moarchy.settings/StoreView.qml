// The OWL widget store (docs/owl.md §B): Omalauncher's StoreScreen, widgets only.
//
// Its `store` panel, drawn in the Settings window under a header of its own
// (OW7): a grid of outlined cards, each drawn in the current theme; a search
// field and counted chips over it; a widget's page with what it installs and
// runs before the bracket action that adds it. Opened from the home menu it is
// the whole of Settings' stack, so back from it is home (OW7a). Everything it knows and does goes through
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

  // OW7a. The whole of Settings' stack: back closes the window, to home.
  readonly property bool alone: !!view.host && view.host.stack.length === 1

  // What the back swipe and Escape ask first: a widget's page goes back to
  // the grid before Settings goes anywhere.
  function goBack(): bool {
    if (!view.selected) return false
    view.selected = null
    view.message = ""
    return true
  }
  function back(): void {
    if (view.goBack() || !view.host) return
    if (!view.host.goBack()) view.host.dismiss()
  }

  // Omalauncher's radii are its frame's 16px stretched, times the corner scale
  // the preset already put into `frame`, so `square` stays square.
  Shared.UiFile { id: ui }
  function radiusFrameAt(px, size): int { return Math.min(Math.round(ui.radiusFrame * px / 16), Math.floor(size / 2)) }

  // Omalauncher's border is the theme's `muted`; its green and red are the
  // theme's own, which Upstream.Color does not carry.
  readonly property color border: Upstream.Color.muted
  property color green: Upstream.Color.accent
  property color red: Upstream.Color.urgent
  FileView {
    path: (Quickshell.env("HOME") || "") + "/.local/state/omarchy/current/theme/colors.toml"
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: {
      var t = text()
      var g = /^\s*green\s*=\s*"(#[0-9a-fA-F]{6})"/m.exec(t)
      var r = /^\s*red\s*=\s*"(#[0-9a-fA-F]{6})"/m.exec(t)
      view.green = g ? g[1] : Upstream.Color.accent
      view.red = r ? r[1] : Upstream.Color.urgent
    }
  }

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

  // OW9. The chips, each with its count: all, new, the catalogue's categories
  // biggest first, then installed with the updates waiting.
  readonly property var tabs: {
    var counts = {}
    var fresh = 0, installed = 0, updates = 0
    for (var i = 0; i < view.widgets.length; i++) {
      var w = view.widgets[i]
      var c = w.category || "other"
      counts[c] = (counts[c] || 0) + 1
      if (w["new"]) fresh++
      if (w.installed) installed++
      if (w.update) updates++
    }
    var cats = Object.keys(counts).sort(function (a, b) {
      return (a === "other") - (b === "other") || counts[b] - counts[a] || (a < b ? -1 : a > b ? 1 : 0)
    })
    var out = [{ name: "all", label: "all " + view.widgets.length },
               { name: "new", label: "new " + fresh }]
    for (var j = 0; j < cats.length; j++) out.push({ name: cats[j], label: cats[j] + " " + counts[cats[j]] })
    if (installed > 0)
      out.push({ name: "installed", label: "installed " + installed + (updates > 0 ? " · " + updates + "↑" : "") })
    return out
  }

  readonly property var shown: {
    var q = view.query.trim().toLowerCase()
    return view.widgets.filter(function (w) {
      if (view.tab === "new" && !w["new"]) return false
      if (view.tab === "installed" && !w.installed) return false
      if (view.tab !== "all" && view.tab !== "new" && view.tab !== "installed"
          && (w.category || "other") !== view.tab) return false
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
    action.verb = verb
    action.command = cmd
    action.running = true
  }
  Process {
    id: action
    property string verb: ""
    stdout: StdioCollector { id: actionOut }
    stderr: StdioCollector { id: actionErr }
    onExited: (code, status) => {
      view.busy = ""
      // OW10a. An install with nothing to say shows the widget on home.
      if (action.verb === "install" && code === 0 && String(actionErr.text).trim() === "" && view.host) {
        view.selected = null
        view.load(false)
        view.host.dismiss()
        return
      }
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
               + " alone=" + view.alone
               + " offline=" + view.offline + (view.problem ? " problem=" + view.problem : "")]
    if (view.selected)
      out.push("selected=" + view.selected.id + " installed=" + (view.selected.installed || "no")
               + " missing=" + view.missing.join(",") + (view.message ? " message=" + view.message : ""))
    return out.join("\n")
  }


  // Omalauncher's text sizes, a step for a step: Small, Body, Item, Title.
  readonly property int textSmall: Style.font.bodySmall
  readonly property int textBody: Style.font.body
  readonly property int textItem: Style.font.subtitle
  readonly property int textTitle: Style.font.heading
  readonly property color ink: view.host ? view.host.textOnSurface : "transparent"
  readonly property color muted: view.host ? view.host.subdued : "transparent"
  readonly property color accent: view.host ? view.host.accent : "transparent"
  readonly property color fill: view.host ? view.host.container : "transparent"
  readonly property int weight: view.host ? view.host.textWeight : Font.Normal

  component Label: Text {
    font.family: Style.font.family
    font.pixelSize: view.textSmall
    font.weight: view.weight
    color: view.muted
    wrapMode: Text.Wrap
  }

  // Omalauncher's BracketAction: a terminal-style `[ label ]`, 44 tall to tap.
  component Bracket: Item {
    id: bracket
    property string label: ""
    property color ink: view.accent
    signal activated()
    width: bracketText.implicitWidth + Style.space(16)
    height: Style.space(44)
    Shared.PressVeil {
      anchors.fill: parent
      ink: bracket.ink
      on: bracketArea.pressed
    }
    Text {
      id: bracketText
      anchors.centerIn: parent
      text: "[ " + bracket.label + " ]"
      font.family: Style.font.family
      font.pixelSize: view.textBody
      font.weight: view.weight
      color: bracket.ink
    }
    MouseArea {
      id: bracketArea
      anchors.fill: parent
      onClicked: bracket.activated()
    }
  }

  // Omalauncher's Chip: outlined, the chosen one in accent over 15% accent.
  component Chip: Item {
    id: chip
    property string label: ""
    property bool on: false
    signal activated()
    width: chipText.implicitWidth + Style.space(24)
    height: Style.space(44)
    Rectangle {
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      height: chipText.implicitHeight + Style.space(12)
      radius: view.radiusFrameAt(14, height)
      color: chip.on ? Util.alpha(view.accent, 0.15) : "transparent"
      border.width: 1
      border.color: chip.on ? view.accent : view.border
      Shared.PressVeil {
        anchors.fill: parent
        radius: parent.radius
        ink: view.accent
        on: chipArea.pressed
      }
    }
    Text {
      id: chipText
      anchors.centerIn: parent
      text: chip.label
      font.family: Style.font.family
      font.pixelSize: view.textSmall
      font.weight: view.weight
      color: chip.on ? view.accent : view.ink
    }
    MouseArea {
      id: chipArea
      anchors.fill: parent
      onClicked: chip.activated()
    }
  }

  // Marks a widget the catalogue calls new, beside its name.
  component NewBadge: Rectangle {
    width: badgeText.implicitWidth + Style.space(10)
    height: badgeText.implicitHeight + Style.space(2)
    radius: view.radiusFrameAt(6, height)
    color: Util.alpha(view.accent, 0.15)
    border.width: 1
    border.color: view.accent
    Text {
      id: badgeText
      anchors.centerIn: parent
      text: "new"
      font.family: Style.font.family
      font.pixelSize: view.textSmall
      font.weight: view.weight
      color: view.accent
    }
  }

  // ---------------------------------------------------------------- header
  // OW7. Omalauncher's panel header: the title in accent, `‹` before it when
  // back goes somewhere, refresh and the red ✕ at the right.
  Item {
    id: header
    width: parent.width
    height: Style.space(44)
    readonly property bool backward: !!view.selected || !view.alone

    Item {
      id: titleSlot
      anchors.left: parent.left
      anchors.top: parent.top
      anchors.bottom: parent.bottom
      width: Math.min(titleRow.implicitWidth + Style.space(8), header.width - actions.width)
      Row {
        id: titleRow
        anchors.verticalCenter: parent.verticalCenter
        spacing: Style.space(6)
        Text {
          visible: header.backward
          anchors.verticalCenter: parent.verticalCenter
          // fa-angle-left, SheetHeader's chevron.
          text: "\uf104"
          font.family: Style.font.family
          font.pixelSize: view.textTitle
          font.weight: view.weight
          color: view.accent
        }
        Text {
          anchors.verticalCenter: parent.verticalCenter
          width: Math.min(implicitWidth, header.width - actions.width - Style.space(40))
          text: view.selected ? String(view.selected.name || "") : "store"
          elide: Text.ElideRight
          font.family: Style.font.family
          font.pixelSize: view.textTitle
          font.weight: view.weight
          color: view.accent
        }
      }
      MouseArea {
        anchors.fill: parent
        enabled: header.backward
        // no press state (style.md H7): Omalauncher's title is its own back
        onClicked: view.back()
      }
    }

    Row {
      id: actions
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      Item {
        visible: !view.selected
        width: Style.space(44)
        height: Style.space(44)
        Ui.OpticalGlyph {
          anchors.fill: parent
          // nf-md-refresh, as an escape: a rune like it is the kind an editor eats.
          text: "\udb81\udc50"
          fontFamily: Style.font.family
          fontSize: view.textTitle
          color: view.loading ? view.accent : view.muted
        }
        MouseArea {
          anchors.fill: parent
          enabled: !view.loading
          // no press state (style.md H7): it turns accent while it runs
          onClicked: view.load(true)
        }
      }
      Item {
        visible: view.alone && !view.selected
        width: Style.space(44)
        height: Style.space(44)
        Ui.OpticalGlyph {
          anchors.fill: parent
          // nf-md-close, as an escape: a rune like it is the kind an editor eats.
          text: "\udb80\udd56"
          fontFamily: Style.font.family
          fontSize: view.textTitle
          color: view.red
        }
        MouseArea {
          anchors.fill: parent
          // no press state (style.md H7): it closes the window
          onClicked: if (view.host) view.host.dismiss()
        }
      }
    }
  }

  // ------------------------------------------------------------------ grid
  Column {
    id: top
    anchors.top: header.bottom
    anchors.topMargin: Style.space(8)
    width: parent.width
    spacing: Style.space(4)
    visible: !view.selected

    Rectangle {
      width: parent.width
      height: Style.space(46)
      radius: view.radiusFrameAt(24, height)
      color: view.fill
      Ui.TextField {
        id: search
        anchors.fill: parent
        anchors.leftMargin: Style.space(18)
        anchors.rightMargin: Style.space(18)
        background: null
        verticalPadding: 0
        leftPadding: 0
        rightPadding: 0
        verticalAlignment: TextInput.AlignVCenter
        font.pixelSize: view.textItem
        foreground: view.ink
        accent: view.accent
        placeholderTextColor: view.muted
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
      height: Style.space(44)
      orientation: ListView.Horizontal
      spacing: Style.space(6)
      clip: true
      boundsBehavior: Flickable.StopAtBounds
      model: view.tabs
      delegate: Chip {
        required property var modelData
        label: modelData.label
        on: view.tab === modelData.name
        onActivated: view.tab = modelData.name
      }
    }

    Label {
      width: parent.width
      text: "reviewed widgets from github.com/SimonSchubert/omarchy-widgets"
    }
    Label {
      width: parent.width
      visible: text !== ""
      color: view.problem !== "" ? view.red : view.muted
      text: view.problem !== "" ? view.problem
          : view.loading && view.widgets.length === 0 ? "loading…"
          : view.offline ? "offline: the store as it was " + Math.round(view.age / 3600) + " h ago"
          : view.widgets.length > 0 && view.shown.length === 0
            ? (view.query.trim() ? "nothing matches \"" + view.query.trim() + "\"" : "no " + view.tab + " widgets")
          : ""
    }
  }

  GridView {
    id: grid
    visible: !view.selected
    anchors.top: top.bottom
    anchors.topMargin: Style.space(6)
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.bottom: parent.bottom
    clip: true
    cellWidth: width / 2
    cellHeight: Style.space(176)
    model: view.shown
    boundsBehavior: Flickable.StopAtBounds
    cacheBuffer: Style.space(176) * 2

    delegate: Item {
      id: card
      required property var modelData
      required property int index
      width: grid.cellWidth
      height: grid.cellHeight

      readonly property var w: card.modelData
      readonly property var status:
          w.update ? [ "update available", view.accent ]
        : w.installed ? [ "✓ installed", view.green ]
        : w.supported === false ? [ "needs a newer runtime", view.red ]
        : [ (w.category || "other") + (w.size ? " · " + w.size[0] + "x" + w.size[1] : ""), view.muted ]

      Rectangle {
        anchors.fill: parent
        // 8px between cards, as Omalauncher spaces its grid.
        anchors.leftMargin: card.index % 2 ? Style.space(4) : 0
        anchors.rightMargin: card.index % 2 ? 0 : Style.space(4)
        anchors.bottomMargin: Style.space(8)
        radius: view.radiusFrameAt(12, height)
        color: "transparent"
        border.width: 1
        border.color: view.border

        Shared.PressVeil {
          anchors.fill: parent
          radius: parent.radius
          ink: view.ink
          on: cardArea.pressed
        }
        Item {
          id: previewSlot
          anchors.top: parent.top
          anchors.left: parent.left
          anchors.right: parent.right
          anchors.margins: Style.space(8)
          height: Style.space(104)
          Rectangle {
            anchors.fill: parent
            visible: preview.status !== Image.Ready
            color: view.fill
            Text {
              anchors.centerIn: parent
              width: parent.width - Style.space(8)
              horizontalAlignment: Text.AlignHCenter
              elide: Text.ElideRight
              text: card.w.name
              font.family: Style.font.family
              font.pixelSize: view.textSmall
              font.weight: view.weight
              color: view.muted
            }
          }
          Image {
            id: preview
            anchors.fill: parent
            source: view.previewUrl(card.w)
            fillMode: Image.PreserveAspectFit
            asynchronous: true
            sourceSize.width: width * 2
          }
        }
        Column {
          anchors.left: parent.left
          anchors.right: parent.right
          anchors.top: previewSlot.bottom
          anchors.topMargin: Style.space(4)
          anchors.leftMargin: Style.space(8)
          anchors.rightMargin: Style.space(8)
          spacing: Style.space(4)
          Row {
            width: parent.width
            spacing: Style.space(6)
            Text {
              id: cardName
              width: Math.min(implicitWidth, parent.width - (badge.visible ? badge.width + parent.spacing : 0))
              anchors.verticalCenter: parent.verticalCenter
              text: card.w.name
              elide: Text.ElideRight
              font.family: Style.font.family
              font.pixelSize: view.textBody
              font.weight: view.weight
              color: view.ink
            }
            NewBadge {
              id: badge
              visible: !!card.w["new"]
              anchors.verticalCenter: parent.verticalCenter
            }
          }
          Text {
            width: parent.width
            text: card.status[0]
            elide: Text.ElideRight
            font.family: Style.font.family
            font.pixelSize: view.textSmall
            font.weight: view.weight
            color: card.status[1]
          }
        }
        MouseArea {
          id: cardArea
          anchors.fill: parent
          onClicked: view.open(card.w)
        }
      }
    }
  }

  // ------------------------------------------------------- a widget's page
  // OW10. What it is, what it installs and runs, then the one action (OW12).
  Flickable {
    id: page
    visible: !!view.selected
    anchors.top: header.bottom
    anchors.topMargin: Style.space(8)
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.bottom: parent.bottom
    contentHeight: detail.implicitHeight + Style.space(24)
    boundsBehavior: Flickable.StopAtBounds
    clip: true

    Column {
      id: detail
      width: page.width
      spacing: Style.space(6)
      readonly property var w: view.selected || ({})
      readonly property var pkgs: detail.w.requires && detail.w.requires.pacman ? detail.w.requires.pacman : []
      readonly property var commands: detail.w.commands || []

      // As wide as the page, but no taller than 320px, so a tall widget does
      // not push its description off screen.
      Image {
        id: bigPreview
        width: parent.width
        height: status === Image.Ready && implicitWidth > 0
                ? Math.min(Style.space(320), width * implicitHeight / implicitWidth) : Style.space(160)
        source: view.previewUrl(view.selected)
        fillMode: Image.PreserveAspectFit
        asynchronous: true
        sourceSize.width: width * 2
      }
      Item { width: 1; height: Style.space(4) }

      Row {
        width: parent.width
        spacing: Style.space(8)
        Text {
          width: Math.min(implicitWidth, parent.width - (detailBadge.visible ? detailBadge.width + parent.spacing : 0))
          anchors.verticalCenter: parent.verticalCenter
          text: String(detail.w.name || "")
          elide: Text.ElideRight
          font.family: Style.font.family
          font.pixelSize: view.textTitle
          font.weight: view.weight
          color: view.ink
        }
        NewBadge {
          id: detailBadge
          visible: !!detail.w["new"]
          anchors.verticalCenter: parent.verticalCenter
        }
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
        font.pixelSize: view.textBody
        font.weight: view.weight
        color: view.ink
      }
      Item { width: 1; height: Style.space(4) }

      // OW12. What it installs and runs, before the button, never after it.
      Label {
        width: parent.width
        color: view.ink
        text: "installs packages: " + (detail.pkgs.length === 0 ? "none" : detail.pkgs.map(function (p) {
          return p + (view.missing.indexOf(p) >= 0 ? " ✗" : " ✓")
        }).join(", "))
      }
      Label {
        width: parent.width
        visible: !!detail.w.changed
        text: "its commands or packages changed since the version you approved"
        color: view.red
      }
      Label {
        width: parent.width
        color: view.ink
        text: detail.commands.length === 0 ? "runs no commands" : "runs these commands:"
      }
      Repeater {
        model: detail.commands
        delegate: Rectangle {
          required property var modelData
          width: detail.width
          height: code.implicitHeight + Style.space(12)
          color: view.fill
          Text {
            id: code
            anchors.fill: parent
            anchors.margins: Style.space(6)
            text: String(modelData).replace(/\s+$/, "")
            wrapMode: Text.WrapAnywhere
            maximumLineCount: 12
            elide: Text.ElideRight
            font.family: "JetBrainsMono Nerd Font"
            font.pixelSize: view.textSmall
            font.weight: view.weight
            color: view.ink
          }
        }
      }
      Item { width: 1; height: Style.space(4) }

      Label {
        width: parent.width
        visible: !!detail.w.edited && !!detail.w.update
        text: "your changes to it go"
        color: view.red
      }
      Label {
        width: parent.width
        visible: detail.w.supported === false
        text: "needs a newer runtime (owl " + detail.w.owl + ")"
        color: view.red
      }
      Text {
        visible: view.busy !== ""
        height: Style.space(44)
        verticalAlignment: Text.AlignVCenter
        text: view.busy
        font.family: Style.font.family
        font.pixelSize: view.textBody
        font.weight: view.weight
        color: view.accent
      }
      Text {
        visible: view.busy === "" && !!detail.w.installed && !detail.w.update
        height: Style.space(32)
        verticalAlignment: Text.AlignVCenter
        text: "✓ on your home screen"
        font.family: Style.font.family
        font.pixelSize: view.textBody
        font.weight: view.weight
        color: view.green
      }
      Row {
        x: -Style.space(8)
        visible: view.busy === "" && detail.w.supported !== false
        Bracket {
          visible: !detail.w.installed
          label: "add to home"
          onActivated: view.act("install")
        }
        Bracket {
          visible: !!detail.w.installed && !!detail.w.update
          label: (detail.w.changed || detail.w.edited ? "update anyway " : "update ")
                 + detail.w.installed + " → " + detail.w.version
          onActivated: view.act("update")
        }
        Bracket {
          visible: !!detail.w.installed
          label: "remove"
          ink: view.red
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
