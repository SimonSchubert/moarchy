// Launches, in the shell: the next twenty, the few you starred, one clock.
//
// The QML half of apps/launches. The files are the GTK app's own
// (~/.local/share/moarchy-launches), so a star tapped here is a star there.
// Chrome comes from shared/qs_ui, vendored into this plugin as ui/.
//
// The clock stops when the window leaves the screen: an app that keeps
// pulling the pad after the phone is in a pocket is a battery bug and a data
// bill wearing a feature's clothes.
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import "ui" as Chrome
import "ui/Theme.js" as Theme
import "ui/Metrics.js" as Metrics
import "ui/Plugin.js" as Plugin
import "Launches.js" as Launches
import "Store.js" as Store

Item {
  id: root

  property var shell: null
  property var manifest: null
  property var barWidgetRegistry: null
  property var pluginRegistry: null
  property var service: null

  readonly property string pluginId: "org.moarchy.launches"
  readonly property bool opened: launchWindow.visible
  readonly property var appWindow: launchWindow

  property string returnTo: ""
  // `colours` and not `palette`: QQuickItem already has a `palette`, and
  // shadowing it makes a binding resolve to whichever the compiler picked --
  // The property-override warning names it, and it is the one warning here
  // that could silently draw the wrong thing. (A comment must not open with
  // the linter's own name: it reads the rest of the line as a directive.)
  readonly property var colours: themeFile.colours
  readonly property int radiusCard: uiFile.radiusCard
  // The shell's text size when the shell is there to ask, 16 otherwise.
  property int bodySize: Metrics.BODY
  Component.onCompleted: root.bodySize = Metrics.shellBody(root)

  property var launches: []
  property var favourites: []
  property real fetched: 0
  property double now: Date.now()

  property string query: ""
  property bool searching: false
  property int tab: 0
  property string openId: ""

  property bool fetching: false
  property string trouble: ""
  property int failures: 0
  property real retryAt: 0
  property bool dirty: false
  property bool loaded: false

  readonly property var backoff: [60, 150, 300, 600]

  readonly property color surface: colours.surface
  readonly property color background: colours.background
  readonly property color textOnSurface: colours.foreground
  readonly property color dim: colours.dim
  readonly property color line: colours.line
  readonly property color accent: colours.accent

  readonly property var shownList: Launches.filter(root.launches, root.query)
  readonly property var starredList: Launches.starred(root.launches, root.favourites, root.query)
  readonly property var current: Launches.find(root.launches, root.openId)

  readonly property string dataDir: Plugin.dataDir(
    "launches", Quickshell.env("HOME"), Quickshell.env("XDG_DATA_HOME"),
    Quickshell.env("MOARCHY_LAUNCHES_DIR"))

  // --- what the header says --------------------------------------------

  function freshnessText() {
    if (root.fetching) return "Updating…"
    if (!root.launches.length) return "No launches yet"
    var age = root.fetched > 0 ? Math.max(0, root.now / 1000 - root.fetched) : 0
    if (root.fetched <= 0) return "No launches yet"
    if (root.failures) return "Not updating · " + Launches.freshness(age)
    return "Updated " + Launches.freshness(age)
  }

  function hueColor(name) {
    var hues = root.colours.hues || {}
    return hues[name] || root.accent
  }

  function toneColor(item) {
    var way = Launches.tone(item, root.now)
    if (way === "soon") return root.hueColor("green")
    if (way === "late") return root.hueColor("red")
    if (way === "wait") return root.hueColor("yellow")
    return root.dim
  }

  function badgeFill(item) {
    return Theme.mix(root.hueColor(Launches.hue(item)), root.colours.background, 0.28)
  }

  function isStarred(id) {
    return root.favourites.indexOf(id) >= 0
  }

  function say(text) { toast.show(text) }

  // --- the shell's plugin contract --------------------------------------

  function open(payloadJson) {
    Plugin.hideOverlays(root.shell)
    root.returnTo = ""
    try {
      var payload = JSON.parse(String(payloadJson || "{}"))
      if (payload.returnTo) root.returnTo = String(payload.returnTo)
    } catch (e) {}
    launchWindow.show()
    Qt.callLater(root.ensureLoaded)
  }

  function close() {
    root.openId = ""
  }

  function dismiss() {
    root.close()
    launchWindow.hide()
    if (root.shell && typeof root.shell.hide === "function")
      root.shell.hide(root.pluginId)
    var back = root.returnTo
    root.returnTo = ""
    if (back && root.shell && typeof root.shell.summon === "function")
      root.shell.summon(back, "{}")
  }

  function ensureLoaded() {
    if (root.loaded) return
    ensureDir.running = true
    favFile.reload()
    cacheFile.reload()
    root.loaded = true
  }

  // --- the stars --------------------------------------------------------

  function toggleStar(id) {
    var result = Store.toggle(root.favourites, id)
    if (result.full) {
      root.say(Store.MAX_FAVOURITES + " starred launches is as many as this app keeps.")
      return
    }
    root.favourites = result.favourites
    favFile.setText(Store.serializeFavourites(root.favourites))
  }

  // --- the network ------------------------------------------------------

  function due() {
    if (root.fetching) return false
    if (root.retryAt && root.now / 1000 < root.retryAt) return false
    if (root.fetched <= 0) return true
    var age = root.now / 1000 - root.fetched
    return age >= Launches.refreshAfter(root.launches, root.now)
  }

  function fetch(manual) {
    if (root.fetching) return
    root.fetching = true
    fetcher.manual = !!manual
    var key = Quickshell.env("MOARCHY_LAUNCHES_KEY") || ""
    var argv = ["curl", "-sS", "--max-time", String(Launches.TIMEOUT),
                "-H", "User-Agent: " + Launches.AGENT,
                "-H", "Accept: application/json"]
    if (key.length) argv.push("-H", "Authorization: Token " + key)
    argv.push("-w", "\n%{http_code}", Launches.url(Launches.LIMIT))
    fetcher.command = argv
    fetcher.running = true
  }

  function arrived(code, payload) {
    root.fetching = false
    var manual = fetcher.manual

    if (code !== 0) {
      root.failed("No answer from Launch Library.", 0, manual)
      return
    }

    var text = String(payload || "")
    var cut = text.lastIndexOf("\n")
    var status = cut >= 0 ? parseInt(text.slice(cut + 1).trim(), 10) : 0
    var body = cut >= 0 ? text.slice(0, cut) : text

    if (status === 429) {
      root.failed("Launch Library is rate-limiting this connection.",
                  Launches.RATE_LIMIT_S, manual)
      return
    }
    if (status >= 500) {
      root.failed("Launch Library is having trouble.", 0, manual)
      return
    }
    if (status !== 200) {
      root.failed("Launch Library refused the request (" + status + ").", 0, manual)
      return
    }

    var parsed = Launches.parseUpcoming(body)
    if (parsed.error) {
      root.failed(parsed.error, 0, manual)
      return
    }

    root.failures = 0
    root.retryAt = 0
    root.trouble = ""
    root.launches = Store.dedupe(parsed.launches)
    root.fetched = Date.now() / 1000
    root.dirty = true
  }

  function failed(message, retry, manual) {
    root.failures += 1
    var wait = retry || root.backoff[Math.min(root.failures - 1, root.backoff.length - 1)]
    root.retryAt = Date.now() / 1000 + wait
    root.trouble = message
    // A NET from four minutes ago is worth something and a blank page is
    // worth nothing, so the launches already on screen stay.
    if (manual || !root.launches.length) root.say(message)
  }

  function saveCache() {
    if (!root.dirty || !root.launches.length) return
    cacheFile.setText(Store.serializeUpcoming(root.launches, root.fetched))
    root.dirty = false
  }

  // --- plumbing ---------------------------------------------------------

  Timer {
    id: tick
    interval: 1000
    repeat: true
    running: launchWindow.visible
    onTriggered: {
      root.now = Date.now()
      if (root.due()) root.fetch(false)
    }
  }

  Process {
    id: ensureDir
    running: false
    command: ["mkdir", "-p", root.dataDir]
  }

  Process {
    id: fetcher
    property bool manual: false
    running: false
    stdout: StdioCollector { id: fetchOut; waitForEnd: true }
    // The disable is Quickshell's gap, not ours: `exited` carries a
    // QProcess::ExitStatus, and that enum is not in the type information the
    // module ships, so the linter cannot resolve a parameter this handler
    // does not even read. Narrow on purpose -- one category, one line.
    // qmllint disable signal-handler-parameters
    onExited: function (code, status) { root.arrived(code, fetchOut.text) }
    // qmllint enable signal-handler-parameters
  }

  FileView {
    id: favFile
    path: root.dataDir + "/favourites.json"
    watchChanges: true
    printErrors: false
    onLoaded: root.favourites = Store.parseFavourites(text())
    onFileChanged: Qt.callLater(function () { favFile.reload() })
  }

  FileView {
    id: cacheFile
    path: root.dataDir + "/upcoming.json"
    watchChanges: true
    printErrors: false
    onLoaded: {
      var cached = Store.parseUpcoming(text())
      if (!cached.launches.length) return
      // Only take the cache while nothing fresher has arrived.
      if (cached.fetched >= root.fetched) {
        root.launches = cached.launches
        root.fetched = cached.fetched
      }
    }
    onFileChanged: Qt.callLater(function () { cacheFile.reload() })
  }

  Chrome.ThemeFile { id: themeFile }
  Chrome.UiFile { id: uiFile }

  IpcHandler {
    target: "launches"
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

  // --- the window -------------------------------------------------------

  Chrome.AppWindow {
    id: launchWindow
    shell: root.shell
    appName: "Launches"
    pageTitle: root.current ? root.current.name : ""
    pluginId: root.pluginId
    color: root.background

    onMapped: {
      root.now = Date.now()
      Qt.callLater(root.ensureLoaded)
    }
    onUnmapped: root.saveCache()

    Rectangle {
      anchors.fill: parent
      color: root.background
      focus: true
      Keys.onEscapePressed: {
        if (root.openId) { root.openId = ""; return }
        if (root.searching) { root.searching = false; root.query = ""; return }
        root.dismiss()
      }

      ColumnLayout {
        anchors.fill: parent
        spacing: 0

        Chrome.AppBar {
          Layout.fillWidth: true
          Layout.preferredHeight: Metrics.TARGET + 12
          title: root.current ? root.current.name : "Launches"
          subtitle: root.current ? Launches.note(root.current) : root.freshnessText()
          foreground: root.textOnSurface
          dim: root.dim
          bodySize: root.bodySize

          leading: Chrome.BackButton {
            visible: !!root.openId
            color: root.textOnSurface
            onClicked: root.openId = ""
          }

          trailing: Row {
            Chrome.IconButton {
              visible: !root.openId
              color: root.textOnSurface
              names: ["system-search-symbolic", "edit-find-symbolic"]
              tooltip: "Search launches"
              onClicked: {
                root.searching = !root.searching
                if (!root.searching) root.query = ""
              }
            }
            Chrome.IconButton {
              visible: !!root.openId
              color: root.openId && root.isStarred(root.openId) ? root.hueColor("yellow") : root.textOnSurface
              names: root.openId && root.isStarred(root.openId)
                     ? ["starred-symbolic"]
                     : ["non-starred-symbolic", "starred-symbolic"]
              tooltip: "Star"
              onClicked: root.toggleStar(root.openId)
            }
            Chrome.IconButton {
              color: root.textOnSurface
              names: ["view-refresh-symbolic"]
              tooltip: root.fetching ? "Updating launches" : "Refresh launches"
              spinning: root.fetching
              onClicked: root.fetch(true)
            }
          }
        }

        Chrome.AppBar {
          Layout.fillWidth: true
          Layout.preferredHeight: Metrics.TARGET + 8
          visible: root.searching && !root.openId
          foreground: root.textOnSurface
          bodySize: root.bodySize

          center: Chrome.TextField {
            anchors.verticalCenter: parent.verticalCenter
            anchors.left: parent.left
            anchors.right: parent.right
            color: root.surface
            bodySize: root.bodySize
            leadingNames: ["system-search-symbolic"]
            trailingNames: ["edit-clear-symbolic"]
            trailingClickable: true
            placeholderText: "Mission, vehicle, pad"
            foreground: root.textOnSurface
            accent: root.accent
            iconColor: root.dim
            text: root.query
            onTextChanged: root.query = text
            onTrailingClicked: root.query = ""
          }
        }

        // --- the list ----------------------------------------------------

        Item {
          Layout.fillWidth: true
          Layout.fillHeight: true

          Flickable {
            id: listFlick
            anchors.fill: parent
            visible: !root.openId
            clip: true
            contentWidth: width
            contentHeight: listCol.height
            boundsBehavior: Flickable.StopAtBounds

            readonly property var items: root.tab === 0 ? root.shownList : root.starredList

            Column {
              id: listCol
              width: listFlick.width

              Repeater {
                model: listFlick.items

                delegate: Item {
                  id: row
                  width: listCol.width
                  height: 72

                  readonly property var item: modelData

                  Rectangle {
                    anchors.fill: parent
                    color: rowTap.pressed ? Theme.mix(root.colours.foreground, root.colours.background, 0.06)
                                          : "transparent"
                  }

                  MouseArea {
                    id: rowTap
                    anchors.fill: parent
                    onClicked: root.openId = row.item.id
                  }

                  RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 12
                    anchors.rightMargin: 4
                    spacing: 10

                    Rectangle {
                      Layout.preferredWidth: 36
                      Layout.preferredHeight: 36
                      Layout.alignment: Qt.AlignVCenter
                      radius: 18
                      color: root.badgeFill(row.item)

                      Chrome.TypedText {
                        anchors.centerIn: parent
                        role: "overline"
                        text: Launches.disc(row.item)
                        color: root.textOnSurface
                        bodySize: root.bodySize
                      }
                    }

                    Column {
                      Layout.fillWidth: true
                      Layout.alignment: Qt.AlignVCenter
                      spacing: 1

                      Chrome.TypedText {
                        width: parent.width
                        role: "body"
                        text: row.item.name
                        color: root.textOnSurface
                        bodySize: root.bodySize
                        elide: Text.ElideRight
                        maximumLineCount: 1
                      }
                      Chrome.TypedText {
                        width: parent.width
                        visible: text.length > 0
                        role: "caption"
                        text: Launches.note(row.item)
                        color: root.dim
                        bodySize: root.bodySize
                        elide: Text.ElideRight
                        maximumLineCount: 1
                      }
                      Chrome.TypedText {
                        width: parent.width
                        visible: text.length > 0
                        role: "caption"
                        text: row.item.location || row.item.pad
                        color: root.dim
                        bodySize: root.bodySize
                        elide: Text.ElideRight
                        maximumLineCount: 1
                      }
                    }

                    Chrome.TypedText {
                      Layout.alignment: Qt.AlignVCenter
                      role: "body"
                      text: Launches.headline(row.item, root.now)
                      color: root.toneColor(row.item)
                      bodySize: root.bodySize
                    }

                    Chrome.IconButton {
                      Layout.alignment: Qt.AlignVCenter
                      names: root.isStarred(row.item.id)
                             ? ["starred-symbolic"]
                             : ["non-starred-symbolic", "starred-symbolic"]
                      color: root.isStarred(row.item.id) ? root.hueColor("yellow") : root.dim
                      tooltip: root.isStarred(row.item.id) ? "Unstar" : "Star"
                      onClicked: root.toggleStar(row.item.id)
                    }
                  }

                  Rectangle {
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.bottom: parent.bottom
                    height: 1
                    color: root.line
                  }
                }
              }
            }
          }

          // --- nothing to show ---------------------------------------------

          Column {
            anchors.centerIn: parent
            width: parent.width - 64
            spacing: 8
            visible: !root.openId && listFlick.items.length === 0

            Chrome.TypedText {
              width: parent.width
              role: "subtitle"
              text: {
                if (root.query) return "No match"
                if (root.tab === 1) return "Nothing starred"
                return "No launches yet"
              }
              color: root.textOnSurface
              bodySize: root.bodySize
              horizontalAlignment: Text.AlignHCenter
            }
            Chrome.TypedText {
              width: parent.width
              role: "caption"
              text: {
                if (root.query) return "Nothing here is called “" + root.query + "”."
                if (root.tab === 1)
                  return "Tap the star beside a launch and it stays on this page until it flies."
                if (root.trouble) return root.trouble
                return "Fetching launches…"
              }
              color: root.dim
              bodySize: root.bodySize
              horizontalAlignment: Text.AlignHCenter
            }
          }

          // --- one launch ---------------------------------------------------

          Flickable {
            id: detailFlick
            anchors.fill: parent
            visible: !!root.openId
            clip: true
            contentWidth: width
            contentHeight: detailCol.height
            boundsBehavior: Flickable.StopAtBounds

            Column {
              id: detailCol
              width: detailFlick.width
              leftPadding: 16
              rightPadding: 16
              topPadding: 12
              bottomPadding: 24
              spacing: 10

              Row {
                spacing: 12

                Rectangle {
                  width: 44
                  height: 44
                  radius: 22
                  visible: !!root.current
                  color: root.current ? root.badgeFill(root.current) : "transparent"

                  Chrome.TypedText {
                    anchors.centerIn: parent
                    role: "caption"
                    text: root.current ? Launches.disc(root.current) : ""
                    color: root.textOnSurface
                    bodySize: root.bodySize
                  }
                }

                Column {
                  width: detailCol.width - detailCol.leftPadding - detailCol.rightPadding - 56
                  anchors.verticalCenter: parent.verticalCenter
                  spacing: 2

                  Chrome.TypedText {
                    width: parent.width
                    role: "subtitle"
                    text: root.current ? root.current.name : ""
                    color: root.textOnSurface
                    bodySize: root.bodySize
                    wrapMode: Text.WordWrap
                  }
                  Chrome.TypedText {
                    width: parent.width
                    visible: text.length > 0
                    role: "caption"
                    text: root.current ? Launches.note(root.current) : ""
                    color: root.dim
                    bodySize: root.bodySize
                    wrapMode: Text.WordWrap
                  }
                }
              }

              Chrome.TypedText {
                width: parent.width - parent.leftPadding - parent.rightPadding
                role: "title"
                text: root.current ? Launches.headline(root.current, root.now) : ""
                color: root.current ? root.toneColor(root.current) : root.dim
                bodySize: root.bodySize
              }

              Repeater {
                model: Launches.facts(root.current)

                delegate: Column {
                  width: detailCol.width - detailCol.leftPadding - detailCol.rightPadding
                  spacing: 1
                  topPadding: 6
                  bottomPadding: 6

                  Chrome.TypedText {
                    width: parent.width
                    role: "caption"
                    text: modelData.label
                    color: root.dim
                    bodySize: root.bodySize
                  }
                  Chrome.TypedText {
                    width: parent.width
                    role: "body"
                    text: modelData.value
                    color: root.textOnSurface
                    bodySize: root.bodySize
                    wrapMode: Text.WordWrap
                  }

                  Rectangle {
                    width: parent.width
                    height: 1
                    color: root.line
                  }
                }
              }

              Chrome.TypedText {
                width: parent.width - parent.leftPadding - parent.rightPadding
                visible: text.length > 0
                role: "body"
                text: root.current ? root.current.description : ""
                color: root.textOnSurface
                bodySize: root.bodySize
                wrapMode: Text.WordWrap
                topPadding: 8
              }
            }
          }

          // --- a sentence, not a spinner --------------------------------------

          Chrome.Toast {
            id: toast
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.bottom: parent.bottom
            anchors.bottomMargin: 14
            colours: root.colours
            bodySize: root.bodySize
          }
        }

        Chrome.BottomNav {
          id: bottomNav
          Layout.fillWidth: true
          Layout.preferredHeight: Metrics.BOTTOM_NAV
          visible: !root.openId
          color: root.background
          dim: root.dim
          accent: root.accent
          bodySize: root.bodySize
          currentIndex: root.tab
          onActivated: function (i) { root.tab = i }

          Chrome.BottomNavItem {
            text: "Upcoming"
            names: ["view-list-symbolic"]
            onActivated: bottomNav.selectItem(this)
          }
          Chrome.BottomNavItem {
            text: "Starred"
            names: ["starred-symbolic"]
            onActivated: bottomNav.selectItem(this)
          }
        }
      }

    }
  }
}
