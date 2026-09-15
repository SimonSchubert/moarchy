// Coins, in the shell: the top hundred, the few you starred, one price column.
//
// The QML half of apps/coins. The files are the GTK app's own
// (~/.local/share/moarchy-coins), so a coin starred here is starred there.
// Chrome comes from shared/qs_ui, vendored into this plugin as ui/.
//
// The clock stops when the window leaves the screen. A coin tracker polling a
// price API from inside a pocket is a battery bug and a data bill wearing a
// feature's clothes, and CoinGecko's keyless tier is shared with everybody
// else behind the same carrier NAT.
import QtQuick
import QtQuick.Layouts
// The logo is round because the disc under it is: OpacityMask clips a square
// PNG to the same circle rather than trusting a hundred issuers to have shipped
// one. Qt5Compat is already a dependency -- Chrome.Icon tints through it.
import Qt5Compat.GraphicalEffects
import Quickshell
import Quickshell.Io
import "ui" as Chrome
import "ui/Theme.js" as Theme
import "ui/Metrics.js" as Metrics
import "ui/Plugin.js" as Plugin
import "Market.js" as Market
import "Store.js" as Store

Item {
  id: root

  property var shell: null
  property var manifest: null
  property var barWidgetRegistry: null
  property var pluginRegistry: null
  property var service: null

  readonly property string pluginId: "org.moarchy.coins"
  readonly property bool opened: coinWindow.visible
  readonly property var appWindow: coinWindow

  property string returnTo: ""
  // `colours` and not `palette`: QQuickItem already has a `palette`, and
  // shadowing it makes a binding resolve to whichever the compiler picked.
  readonly property var colours: themeFile.colours
  property int bodySize: Metrics.BODY
  Component.onCompleted: {
    root.bodySize = Metrics.shellBody(root)
    root.applyHarness()
  }

  property var coins: []
  property var favourites: []
  property real fetched: 0
  property string currency: Market.CURRENCY
  property double now: Date.now()

  property string query: ""
  property bool searching: false
  property int tab: 0

  property bool fetching: false
  property string trouble: ""
  property int failures: 0
  property real retryAt: 0
  property bool dirty: false
  property bool loaded: false
  property bool offline: false

  readonly property var backoff: [60, 150, 300, 600]

  property bool fetchingIcons: false

  readonly property color surface: colours.surface
  readonly property color background: colours.background
  readonly property color textOnSurface: colours.foreground
  readonly property color dim: colours.dim
  readonly property color line: colours.line
  readonly property color accent: colours.accent

  readonly property var shownList: Market.filter(root.coins, root.query)
  readonly property var starredList: Market.starred(root.coins, root.favourites, root.query)

  readonly property string dataDir: Plugin.dataDir(
    "coins", Quickshell.env("HOME"), Quickshell.env("XDG_DATA_HOME"),
    Quickshell.env("MOARCHY_COINS_DIR"))

  readonly property string iconDir: root.dataDir + "/icons"

  // --- the harness ------------------------------------------------------

  // The same variables apps/coins/shots.sh sets, read through Quickshell.env so
  // the screenshot list ports across unchanged. _OFFLINE is the one that
  // matters: with it the window shows the market demo.py wrote and never opens
  // a socket, which is why two shots taken a minute apart agree.
  function applyHarness() {
    root.offline = (Quickshell.env("MOARCHY_COINS_OFFLINE") || "") !== ""
    var page = Quickshell.env("MOARCHY_COINS_PAGE") || ""
    if (page === "favourites" || page === "starred") root.tab = 1
    var search = Quickshell.env("MOARCHY_COINS_SEARCH") || ""
    if (search.length) { root.searching = true; root.query = search }
    var money = Quickshell.env("MOARCHY_COINS_CURRENCY") || ""
    if (money.length) root.currency = money.toLowerCase()
  }

  // --- what the header says ---------------------------------------------

  function freshnessText() {
    if (root.fetching) return "Updating…"
    if (root.fetched <= 0) return root.coins.length ? "Cached prices" : "No prices yet"
    var age = Math.max(0, root.now / 1000 - root.fetched)
    if (root.failures) return "Not updating · " + Market.freshness(age)
    return "Updated " + Market.freshness(age)
  }

  function hueColor(name) {
    var hues = root.colours.hues || {}
    return hues[name] || root.accent
  }

  function badgeFill(coin) {
    return Theme.mix(root.hueColor(Market.badgeHue(coin.id)),
                     root.colours.background, Market.BADGE_TINT)
  }

  // Up is the theme's green and down is its red, and neither is ever alone:
  // Market.percent always writes a sign, because roughly one man in twelve
  // cannot tell those two apart.
  function changeColor(coin) {
    var way = Market.direction(coin.change)
    if (way === "up") return root.hueColor("green")
    if (way === "down") return root.hueColor("red")
    return root.dim
  }

  function isStarred(id) { return root.favourites.indexOf(id) >= 0 }

  // --- the logos --------------------------------------------------------

  // Empty until the file is known to be on the disk, and never a guess: an
  // Image pointed at a path that is not there logs `Cannot open` once per row,
  // which on a fresh phone is a hundred lines for an ordinary state and is
  // exactly what a real error would then be lost in. Found by the check
  // harness, which is the reason it greps the run at all.
  function iconSource(coin) {
    var file = Market.iconFile(coin.id)
    return root.iconsHave[file] ? "file://" + root.iconDir + "/" + file : ""
  }

  // Fetch every logo the list needs and does not have. All of them rather than
  // the visible or the starred ones: asking for all hundred says what asking
  // for the top hundred already said, while asking for four would name the
  // four.
  //
  // One curl for the batch -- a hundred processes is a hundred forks on a
  // 1.15GHz A53 -- and capped per run so the argument list stays sane and a
  // slow radio gets to draw between batches.
  function fetchIcons() {
    if (root.offline || root.fetchingIcons) return
    // -f so an HTTP error is not written to the file as if it were a logo, and
    // --remove-on-error so a half-written one is taken away rather than cached
    // forever as a broken image. curl 8 on the phone has both.
    var argv = ["curl", "-sS", "-f", "--remove-on-error",
                "--max-time", String(Market.TIMEOUT),
                "-H", "User-Agent: " + Market.AGENT]
    var wanted = 0
    for (var i = 0; i < root.coins.length && wanted < 24; i++) {
      var coin = root.coins[i]
      var file = Market.iconFile(coin.id)
      if (!coin.image || root.iconsHave[file] || root.iconsTried[file]) continue
      argv.push("-o", root.iconDir + "/" + file, coin.image)
      // Tried, so a coin whose logo 404s is not asked for again every minute.
      root.iconsTried[file] = true
      wanted += 1
    }
    if (!wanted) return
    root.fetchingIcons = true
    iconGetter.command = argv
    iconGetter.running = true
  }

  // What is on the disk, by filename, and what has been asked for once already
  // so a coin whose logo 404s is not chased every minute. Both last for the
  // life of the process, which is the right cadence for a logo.
  property var iconsHave: ({})
  property var iconsTried: ({})

  // Looking, rather than believing the exit code: curl can succeed for some
  // URLs of a batch and fail for others, and the file on the disk is the only
  // thing the Image will actually open.
  function scanIcons() {
    iconLister.running = false
    iconLister.running = true
  }

  function iconsSeen(names) {
    var have = {}
    var list = String(names || "").split("\n")
    for (var i = 0; i < list.length; i++) {
      var name = list[i].trim()
      if (name.length) have[name] = true
    }
    root.iconsHave = have
  }

  function iconsArrived(code) {
    root.fetchingIcons = false
    root.scanIcons()
    // More to go: the cap is per run, not per list.
    if (code === 0) Qt.callLater(root.fetchIcons)
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
    coinWindow.show()
    Qt.callLater(root.ensureLoaded)
  }

  function close() {
    root.searching = false
    root.query = ""
  }

  function dismiss() {
    root.close()
    coinWindow.hide()
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
    // Before any fetch: a phone that has had this app open before already has
    // the logos, and they should be on screen in the first frame rather than
    // after a round trip.
    Qt.callLater(root.scanIcons)
    favFile.reload()
    cacheFile.reload()
    root.loaded = true
  }

  // --- the stars --------------------------------------------------------

  function toggleStar(id) {
    var result = Store.toggle(root.favourites, id)
    if (result.full) {
      root.say(Store.MAX_FAVOURITES + " starred coins is as many as this app keeps.")
      return
    }
    root.favourites = result.favourites
    favFile.setText(Store.serializeFavourites(root.favourites))
  }

  // --- the network ------------------------------------------------------

  function due() {
    if (root.offline || root.fetching) return false
    if (root.retryAt && root.now / 1000 < root.retryAt) return false
    if (root.fetched <= 0) return true
    return (root.now / 1000 - root.fetched) >= Market.REFRESH_S
  }

  function argv(url) {
    var key = Quickshell.env("MOARCHY_COINS_KEY") || ""
    var out = ["curl", "-sS", "--max-time", String(Market.TIMEOUT),
               "-H", "User-Agent: " + Market.AGENT,
               "-H", "Accept: application/json"]
    // No key is required and one is used if offered.
    if (key.length) out.push("-H", "x-cg-demo-api-key: " + key)
    out.push("-w", "\n%{http_code}", url)
    return out
  }

  function fetch(manual) {
    if (root.fetching) return
    if (root.offline) { if (manual) root.say("Offline: showing the cached market."); return }
    root.fetching = true
    fetcher.manual = !!manual
    fetcher.command = root.argv(Market.url(root.currency, Market.TOP))
    fetcher.running = true
  }

  // The second request, and only when a starred coin has fallen out of the top
  // hundred -- the one case where the list on screen cannot answer for a coin
  // somebody asked to watch.
  function fetchMissing() {
    if (root.offline || chaser.running) return
    var want = Market.missing(root.coins, root.favourites)
    if (!want.length) return
    chaser.command = root.argv(Market.url(root.currency, want.length, want))
    chaser.running = true
  }

  function split(payload) {
    var text = String(payload || "")
    var cut = text.lastIndexOf("\n")
    return {
      status: cut >= 0 ? parseInt(text.slice(cut + 1).trim(), 10) : 0,
      body: cut >= 0 ? text.slice(0, cut) : text
    }
  }

  function trouble_for(status) {
    if (status === 429) return { text: "CoinGecko is rate-limiting this connection.",
                                 wait: Market.RATE_LIMIT_S }
    if (status >= 500) return { text: "CoinGecko is having trouble.", wait: 0 }
    return { text: "CoinGecko refused the request (" + status + ").", wait: 0 }
  }

  function arrived(code, payload) {
    root.fetching = false
    var manual = fetcher.manual
    if (code !== 0) { root.failed("No answer from CoinGecko.", 0, manual); return }

    var part = root.split(payload)
    if (part.status !== 200) {
      var t = root.trouble_for(part.status)
      root.failed(t.text, t.wait, manual)
      return
    }

    var parsed = Market.parseMarkets(part.body, true)
    if (parsed.error) { root.failed(parsed.error, 0, manual); return }

    root.failures = 0
    root.retryAt = 0
    root.trouble = ""
    root.coins = Store.replace(root.coins, parsed.coins)
    root.fetched = Date.now() / 1000
    root.dirty = true
    Qt.callLater(root.fetchMissing)
    Qt.callLater(root.fetchIcons)
  }

  function chased(code, payload) {
    if (code !== 0) return
    var part = root.split(payload)
    if (part.status !== 200) return
    // Not ordered: the answer is whichever coins were asked for, so its
    // positions mean nothing and each coin's own rank is what is drawn.
    var parsed = Market.parseMarkets(part.body, false)
    if (parsed.error || !parsed.coins.length) return
    root.coins = Store.replace(root.coins, root.coins.concat(parsed.coins))
    root.dirty = true
  }

  function failed(message, retry, manual) {
    root.failures += 1
    var wait = retry || root.backoff[Math.min(root.failures - 1, root.backoff.length - 1)]
    root.retryAt = Date.now() / 1000 + wait
    root.trouble = message
    // A price from four minutes ago is worth something and a blank page is
    // worth nothing, so the coins already on screen stay.
    if (manual || !root.coins.length) root.say(message)
  }

  function saveCache() {
    if (!root.dirty || !root.coins.length) return
    cacheFile.setText(Store.serializeMarket(root.coins, root.fetched, root.currency))
    root.dirty = false
  }

  // --- plumbing ---------------------------------------------------------

  Timer {
    id: tick
    interval: 1000
    repeat: true
    running: coinWindow.visible
    onTriggered: {
      root.now = Date.now()
      if (root.due()) root.fetch(false)
    }
  }

  Process { id: ensureDir; running: false; command: ["mkdir", "-p", root.iconDir] }

  Process {
    id: iconGetter
    running: false
    // qmllint disable signal-handler-parameters
    onExited: function (code, status) { root.iconsArrived(code) }
    // qmllint enable signal-handler-parameters
  }

  Process {
    id: iconLister
    running: false
    command: ["sh", "-c", "ls -1 " + JSON.stringify(root.iconDir) + " 2>/dev/null || true"]
    stdout: StdioCollector { id: listOut; waitForEnd: true }
    // qmllint disable signal-handler-parameters
    onExited: function (code, status) { root.iconsSeen(listOut.text) }
    // qmllint enable signal-handler-parameters
  }

  Process {
    id: fetcher
    property bool manual: false
    running: false
    stdout: StdioCollector { id: fetchOut; waitForEnd: true }
    // Quickshell's gap, not ours: `exited` carries a QProcess::ExitStatus and
    // that enum is not in the type information the module ships.
    // qmllint disable signal-handler-parameters
    onExited: function (code, status) { root.arrived(code, fetchOut.text) }
    // qmllint enable signal-handler-parameters
  }

  Process {
    id: chaser
    running: false
    stdout: StdioCollector { id: chaseOut; waitForEnd: true }
    // qmllint disable signal-handler-parameters
    onExited: function (code, status) { root.chased(code, chaseOut.text) }
    // qmllint enable signal-handler-parameters
  }

  Chrome.JsonFile {
    id: favFile
    path: root.dataDir + "/favourites.json"
    onParsed: function (data) { root.favourites = Store.parseFavourites(data) }
    onQuarantined: function (to) { root.say("The starred file was unreadable and was kept aside.") }
  }

  Chrome.JsonFile {
    id: cacheFile
    path: root.dataDir + "/market.json"
    onParsed: function (data) {
      var m = Store.parseMarket(data)
      if (!m.coins.length) return
      root.coins = m.coins
      root.fetched = m.fetched
      if (m.currency) root.currency = m.currency
      // A cold start from the cache knows the URLs already, so the logos do
      // not wait for the next market refresh.
      Qt.callLater(root.fetchIcons)
    }
  }

  Chrome.ThemeFile { id: themeFile }

  IpcHandler {
    target: "coins"
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
    // The harness's half: a screenshot script that names a page cannot
    // photograph the wrong one.
    function screen(name: string): string {
      root.tab = (name === "starred" || name === "favourites") ? 1 : 0
      return root.tab === 1 ? "starred" : "market"
    }
    function find(text: string): string {
      root.searching = text.length > 0
      root.query = text
      return String(root.shownList.length)
    }
    function settled(): bool { return !root.fetching }
  }

  // --- the window -------------------------------------------------------

  Chrome.AppWindow {
    id: coinWindow
    shell: root.shell
    appName: "Coins"
    pluginId: root.pluginId
    color: root.background

    onMapped: {
      root.now = Date.now()
      Qt.callLater(root.ensureLoaded)
      // Same reason as Habits: keepLoaded plus a watcher on a path that did
      // not exist means a cache written after the first open goes unseen.
      if (!root.coins.length) Qt.callLater(function () { cacheFile.reload() })
      Qt.callLater(root.scanIcons)
    }
    onUnmapped: root.saveCache()

    Rectangle {
      anchors.fill: parent
      color: root.background
      focus: true
      Keys.onEscapePressed: {
        if (root.searching) { root.searching = false; root.query = ""; return }
        root.dismiss()
      }

      ColumnLayout {
        anchors.fill: parent
        spacing: 0

        Chrome.AppBar {
          Layout.fillWidth: true
          Layout.preferredHeight: Metrics.TARGET + 12
          title: "Coins"
          subtitle: root.freshnessText()
          foreground: root.textOnSurface
          dim: root.dim
          bodySize: root.bodySize

          trailing: Row {
            Chrome.IconButton {
              color: root.textOnSurface
              names: ["system-search-symbolic", "edit-find-symbolic"]
              tooltip: "Search coins"
              onClicked: {
                root.searching = !root.searching
                if (!root.searching) root.query = ""
              }
            }
            Chrome.IconButton {
              color: root.textOnSurface
              names: ["view-refresh-symbolic"]
              tooltip: root.fetching ? "Updating prices" : "Refresh prices"
              spinning: root.fetching
              onClicked: root.fetch(true)
            }
          }
        }

        Chrome.AppBar {
          Layout.fillWidth: true
          Layout.preferredHeight: Metrics.TARGET + 8
          visible: root.searching
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
            placeholderText: "Name or symbol"
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
                  height: 68

                  required property var modelData
                  readonly property var coin: row.modelData

                  Rectangle {
                    anchors.fill: parent
                    color: rowTap.pressed
                           ? Theme.mix(root.colours.foreground, root.colours.background, 0.06)
                           : "transparent"
                  }

                  MouseArea {
                    id: rowTap
                    anchors.fill: parent
                    onClicked: root.toggleStar(row.coin.id)
                  }

                  RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 12
                    anchors.rightMargin: 4
                    spacing: 10

                    // The disc is tinted and the digits are the theme's own
                    // foreground: a solid hue with light text on it is
                    // unreadable on a yellow coin in a light theme.
                    Rectangle {
                      id: badge
                      Layout.preferredWidth: 36
                      Layout.preferredHeight: 36
                      Layout.alignment: Qt.AlignVCenter
                      radius: 18
                      color: root.badgeFill(row.coin)

                      // The rank, which is what the disc was for and still is
                      // whenever there is no logo on the disk: a phone that has
                      // never been online, a coin whose image 404s, or the
                      // second before the batch lands.
                      Chrome.TypedText {
                        anchors.centerIn: parent
                        visible: logo.status !== Image.Ready
                        role: "overline"
                        text: String(row.coin.rank)
                        color: root.textOnSurface
                        bodySize: root.bodySize
                      }

                      Image {
                        id: logo
                        anchors.fill: parent
                        source: root.iconSource(row.coin)
                        // 50x50 down to 36 at scale 1 and up to 72 at scale 2,
                        // so it is asked for at the size it is drawn rather
                        // than scaled by the scene graph every frame.
                        sourceSize.width: 72
                        sourceSize.height: 72
                        fillMode: Image.PreserveAspectFit
                        smooth: true
                        asynchronous: true
                        // A missing file is the ordinary case, not an error
                        // worth a line in the shell's log.
                        onStatusChanged: if (status === Image.Error) logo.visible = false
                        visible: status === Image.Ready
                        layer.enabled: true
                        layer.effect: OpacityMask {
                          maskSource: Rectangle {
                            width: badge.width
                            height: badge.height
                            radius: badge.radius
                          }
                        }
                      }
                    }

                    Column {
                      Layout.fillWidth: true
                      Layout.alignment: Qt.AlignVCenter
                      spacing: 1

                      Chrome.TypedText {
                        width: parent.width
                        role: "body"
                        text: row.coin.name
                        color: root.textOnSurface
                        bodySize: root.bodySize
                        elide: Text.ElideRight
                        maximumLineCount: 1
                      }
                      Chrome.TypedText {
                        width: parent.width
                        role: "caption"
                        text: row.coin.symbol + " · " + Market.compact(row.coin.cap, root.currency)
                        color: root.dim
                        bodySize: root.bodySize
                        elide: Text.ElideRight
                        maximumLineCount: 1
                      }
                    }

                    Column {
                      Layout.alignment: Qt.AlignVCenter
                      spacing: 1

                      Chrome.TypedText {
                        anchors.right: parent.right
                        role: "body"
                        text: Market.money(row.coin.price, root.currency)
                        color: root.textOnSurface
                        bodySize: root.bodySize
                      }
                      Chrome.TypedText {
                        anchors.right: parent.right
                        role: "caption"
                        text: Market.percent(row.coin.change)
                        color: root.changeColor(row.coin)
                        bodySize: root.bodySize
                      }
                    }

                    Chrome.IconButton {
                      Layout.alignment: Qt.AlignVCenter
                      color: root.isStarred(row.coin.id) ? root.hueColor("yellow") : root.dim
                      names: root.isStarred(row.coin.id)
                             ? ["starred-symbolic"]
                             : ["non-starred-symbolic", "starred-symbolic"]
                      tooltip: root.isStarred(row.coin.id) ? "Unstar" : "Star"
                      onClicked: root.toggleStar(row.coin.id)
                    }
                  }

                  Rectangle {
                    anchors.bottom: parent.bottom
                    width: parent.width
                    height: 1
                    color: root.line
                  }
                }
              }
            }
          }

          // The empty states, which are three different facts and say so.
          Chrome.TypedText {
            anchors.centerIn: parent
            width: parent.width - 48
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.WordWrap
            visible: listFlick.items.length === 0
            role: "body"
            color: root.dim
            bodySize: root.bodySize
            text: root.query.length
                  ? "No coin here is called that."
                  : (root.tab === 1
                     ? "Star a coin on the Market page and it is kept here."
                     : (root.coins.length ? "" : "No prices yet."))
          }

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
          color: root.background
          dim: root.dim
          accent: root.accent
          bodySize: root.bodySize
          currentIndex: root.tab
          onActivated: function (i) { root.tab = i }

          Chrome.BottomNavItem {
            text: "Market"
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
