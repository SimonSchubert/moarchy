// Settings: a stack of phone screens over Omarchy's menu.
//
// ---------------------------------------------------------------------------
// What this replaced
// ---------------------------------------------------------------------------
// Eight rows, of which seven summoned `omarchy.menu` at a route and handed the
// user Omarchy's desktop list. That list is a popup this port cannot dismiss by
// tapping outside -- install/port-4x.sh stubs out HyprlandFocusGrab, which has
// no Quickshell.I3 counterpart -- so every one of those rows was a trapdoor.
//
// The screens live in Pages.js as data; this file is the machinery that renders
// them. docs/menu-coverage.md records which of upstream's 320 entries land
// where, and docs/settings.md is the contract with the acceptance criteria.
//
// ---------------------------------------------------------------------------
// Three things here are load-bearing and look optional
// ---------------------------------------------------------------------------
// 1. open() does no reading. It sets the page and returns; the guard batch runs
//    from Qt.callLater. open() is called inside the IPC handler for
//    `omarchy-shell shell summon`, and anything that spins a nested event loop
//    there leaves it unfinished -- which maps a layer surface that never paints:
//    a black rectangle over the whole screen, logged nowhere. Same trap
//    port-4x.sh documents on the launcher's FileView.
//
// 2. Row visibility is a property looked up per row, not a filter over the
//    model. A ListView whose model array is replaced tears down and recreates
//    its delegates, and a delegate recreated under a finger eats the tap.
//
// 3. No property here is named on<Uppercase>. QML reserves that prefix for
//    signal handlers, so such a property reads back undefined, and undefined
//    assigned to a color renders pure black with nothing logged.
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs.Commons
import qs.Ui as Ui
import "Pages.js" as Pages
import "Guards.js" as Guards

Item {
  id: root

  // Injected by the host in onLoaded, by name, after construction. NOT
  // `readonly` and NOT `required`: readonly makes the assignment throw,
  // required makes the component fail to instantiate, and either way the
  // plugin silently does not load.
  property string omarchyPath: Quickshell.env("OMARCHY_PATH")
                               || (Quickshell.env("HOME") + "/.local/share/omarchy")
  property var shell: null
  property var manifest: null
  property var barWidgetRegistry: null
  property var pluginRegistry: null
  property var service: null

  readonly property string pluginId: "moarchy.settings"

  property bool opened: false

  // K1. Summoned and not yet closed, which is a longer life than `opened`:
  // the strip's up-swipe, a bridged launch and handing off to the theme picker
  // all put this surface away without ending it. The carousel keeps a card for
  // exactly this span, and the page stack below survives it.
  property bool running: false

  property string returnTo: ""

  // The page stack, root first. currentPage is its top.
  property var stack: ["root"]
  readonly property string currentPage: root.stack.length
                                        ? root.stack[root.stack.length - 1] : "root"

  // Answers from the last guard batch, keyed by row id.
  property var whenMap: ({})
  property var valueMap: ({})
  property string pageValue: ""

  // Rows a provider or text page built for itself. Empty for ordinary pages.
  // `dynamicLoaded` is separate from `dynamicRows.length` because a provider is
  // allowed to return nothing -- a phone with no extra wallpapers -- and
  // keying off the length alone re-ran it forever.
  property var dynamicRows: []
  property bool dynamicLoaded: false

  // Bumped on every page change and every refresh. A batch that comes back
  // carrying an older number is answering a question about a page we have left,
  // and applying it would paint one page with another's state.
  //
  // Restarting matters as much as tagging: `Process.running = true` is a no-op
  // on a process already running, so setting a new command while the last batch
  // is still in flight would leave the old one to answer for it.
  property int generation: 0

  // Set by `settings dryRun 1`. Records what would have run instead of running
  // it, which is what lets the selftest exercise every bridged row on a phone
  // it is not allowed to reboot.
  property bool dryRun: false
  property string lastLaunch: ""

  property string confirmText: ""
  property var confirmRow: null

  // `input` row text, keyed by row id, and which of them has the keyboard.
  //
  // Reassigned wholesale, never mutated in place: a `var` property holding an
  // object emits no change on a member write, so `inputMap[id] = v` would
  // update the field and leave every binding that reads it -- the Set row's
  // enabled state, the command it builds -- looking at the old value.
  //
  // Cleared by afterPageChange, so nothing typed here outlives the screen (J12).
  property var inputMap: ({})
  property string focusedInput: ""

  function inputValue(id) {
    var v = root.inputMap[id]
    return v === undefined ? "" : String(v)
  }

  function setInput(id, value) {
    var next = ({})
    for (var k in root.inputMap) next[k] = root.inputMap[k]
    next[id] = String(value)
    root.inputMap = next
  }

  // Must match moarchy.gestures' own stripHeight. Duplicated rather than
  // read across plugins for the same reason the shade duplicates it: this
  // surface has to know the number even when the gestures plugin failed to
  // load, and a sheet that ran off the bottom of the screen in that case would
  // be worse than one that leaves the band unused.
  //
  // Not 20 pixels. Style.space rounds a *scaled* value and the scale comes from
  // the theme's shell.toml, so this is nearer 23 at the default ~1.15 -- which
  // is why nothing here or in the selftest writes the number down.
  readonly property int gestureStrip: Style.space(20)

  readonly property int radiusCard: Style.space(18)

  // NOT `onSurface` / `onAccent` -- see the header.
  readonly property color surface: Color.menu.background
  readonly property color textOnSurface: Color.menu.text
  readonly property color container: Util.alpha(Color.menu.text, 0.08)

  // The detail line is computed per theme rather than fixed, because no single
  // alpha is right for all 22.
  //
  // Measured across every theme's colors.toml, foreground at 0.7 over this card
  // falls below AA in six of them and reaches 3.14:1 on rose-pine. Calibrating
  // on Catppuccin -- which passes at 5.44 -- is what hides that; it is one of
  // the more forgiving themes for this pair. A constant has to be tuned for the
  // worst theme, which then makes it wrong for the other 21: the alpha that
  // clears AA everywhere is 0.9, and at 0.9 a subtitle is within ten percent of
  // its label and the hierarchy the alpha existed to create is gone.
  //
  // So: start quiet and walk toward the foreground only until it clears 4.5:1.
  // Every theme ends up as quiet as it can afford -- 0.55 on vantablack, 0.88
  // on rose-pine, and sixteen of the twenty-two below 0.70.
  //
  // Evaluated once per theme change, not per row.
  readonly property color cardOpaque: root.mix(root.surface, Color.menu.text, 0.08)
  readonly property color subdued: root.readableOn(root.cardOpaque, Color.menu.text,
                                                   0.55, 4.5)
  readonly property color accent: Color.accent

  // ------------------------------------------------------- press (style.md H)
  //
  // One blended quad the size of the chrome, the control's own ink at 12%
  // composited over whatever the resting fill is -- so a control whose colour
  // already says something keeps saying it while pressed (H2).
  //
  // Both ends are one ink at two alphas, never "transparent". That is
  // #00000000 and it carries black: a ColorAnimation to it would fade through
  // a grey wash, and Qt.tint over it returns 12% grey rather than 12% ink (H3).
  //
  // Instant in, 120 out (H5). A Behavior reads `enabled` at the moment of the
  // write, when the property still holds the *old* colour -- so this is false
  // arriving and true leaving, with no second binding to order against.
  //
  // Culled at rest rather than drawn transparent: nothing in the scene graph
  // culls an alpha-0 rectangle, and this is a Mali-400.
  component PressVeil: Rectangle {
    id: pv
    property color ink: root.textOnSurface
    property bool on: false
    visible: pv.color.a > 0
    color: Util.alpha(pv.ink, pv.on ? 0.12 : 0)
    Behavior on color {
      enabled: pv.color.a > 0
      ColorAnimation { duration: 120 }
    }
  }

  // The same weight the bar runs at. Light text on a dark surface reads thinner
  // than it measures; moarchy.bar's textWeight carries the ink
  // measurements behind DemiBold rather than Medium.
  readonly property int textWeight: Font.DemiBold

  readonly property var pageDef: Pages.page(root.currentPage)
  readonly property string pageTitle: root.pageDef ? root.pageDef.title : "Settings"

  // Stable identity for an ordinary page: the same array object comes back from
  // Pages.js every time, so the ListView keeps its delegates.
  readonly property var currentRows: {
    var p = root.pageDef
    if (!p) return []
    if (!p.provider && !p.text) return p.rows
    // `before` is the reminders screen: the list it builds goes above the two
    // rows the page declares, rather than instead of them, so opening the page
    // is the whole of showing them (docs/settings.md J1).
    if (p.provider && p.provider.before) return root.dynamicRows.concat(p.rows)
    return root.dynamicRows
  }

  // WCAG 2.1 relative luminance and contrast, and a linear composite. `container`
  // is painted with alpha over `surface`, so the background the text actually
  // lands on is the blend of the two -- measuring against `surface` alone
  // overstates the contrast by the width of that lift.
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

  function rowsTsv(pageId) {
    if (!Pages.exists(pageId)) return "unknown page: " + pageId
    var live = (pageId === root.currentPage)
    var rows = live ? root.currentRows : Pages.page(pageId).rows
    var out = []
    for (var i = 0; i < rows.length; i++) {
      var r = rows[i]
      out.push([r.id, r.type, r.label,
                live ? (root.rowVisible(r) ? "1" : "0") : "?",
                live ? (root.rowChecked(r) ? "1" : "0") : "?",
                live ? root.rowDetail(r) : "",
                live ? (root.rowEnabled(r) ? "1" : "0") : "?"].join("\t"))
    }
    return out.join("\n")
  }

  // A deep link arrives as one page id, but back has to walk up from it. Page
  // ids are dotted the way upstream's menu ids are, so the ancestors are the
  // prefixes: system.power -> root, system, system.power. Without this, back
  // from the shade's power glyph would close Settings rather than go up a level.
  function stackFor(pageId) {
    if (pageId === "root") return ["root"]
    var parts = String(pageId).split(".")
    var out = ["root"]
    var acc = ""
    for (var i = 0; i < parts.length; i++) {
      acc = acc ? acc + "." + parts[i] : parts[i]
      if (Pages.exists(acc)) out.push(acc)
    }
    return out
  }

  function rowByValue(value) {
    var rows = root.currentRows
    for (var i = 0; i < rows.length; i++)
      if (rows[i].type === "choice" && String(rows[i].value) === String(value))
        return rows[i]
    return null
  }

  function rowById(id) {
    var rows = root.currentRows
    for (var i = 0; i < rows.length; i++) if (rows[i].id === id) return rows[i]
    return null
  }

  // A row with no `when` is visible. One with a `when` is visible only on an
  // explicit pass -- so a guard that fails, hangs or is missing hides its row
  // rather than showing it wrongly.
  function rowVisible(row) {
    if (!row) return false
    if (!row.when) return true
    return root.whenMap[row.id] === true
  }

  // Drawn but not yet able to act: Set a reminder before a duration is typed.
  // Deliberately not the same question as `rowVisible` -- a row that vanishes
  // when a field is empty and reappears when it is not would move the list
  // under a thumb (J8).
  function rowEnabled(row) {
    if (!row) return false
    if (!row.requires) return true
    return root.inputValue(String(row.requires)) !== ""
  }

  function rowChecked(row) {
    if (!row) return false
    if (row.type === "switch") {
      // Unknown is not "off inverted". Before the first read there is no answer,
      // and an inverted switch would otherwise paint ON for a frame and then
      // flip -- which reads as the tap having done something.
      var raw = root.valueMap[row.id]
      // A provider that built this row already knows: one `listPlugins` answers
      // for all forty-odd of them, where a `read` per row is a fork per row on
      // a 1.15GHz A53. The guard batch still wins when there is one, so a row
      // may carry both.
      if (raw === undefined && row.state !== undefined) raw = row.state
      if (raw === undefined) return false
      var v = String(raw).toLowerCase()
      var on = (v === "true" || v === "1" || v === "on" || v === "enabled")
      return row.invert ? !on : on
    }
    if (row.type === "choice")
      return root.pageValue !== "" &&
             root.pageValue === String(row.readValue || row.value)
    return false
  }

  // `detail` is prose carried by the row; `read` and `detailCmd` are shell
  // expressions the guard batch answers. Two kinds of field rather than one
  // guessed apart at runtime -- "Keep the screen on" and
  // "basename \"$(omarchy-theme-bg-current)\"" are not distinguishable by
  // inspection, and guessing got it wrong in both directions.
  //
  // Keyed off the command fields, not off the row type: the keybindings page
  // builds info rows that carry their second column inline and ask nothing, and
  // treating every info row as guard-answered blanked all of them.
  function rowDetail(row) {
    if (!row) return ""
    // A switch's `read` answers `checked`, not the second line. Without this
    // every switch printed its own raw state under its label -- "Show status
    // bar / false" next to a toggle that was visibly on.
    if (row.type === "switch") return String(row.detail || "")
    if (row.read || row.detailCmd) return String(root.valueMap[row.id] || "")
    return String(row.detail || "")
  }

  // ------------------------------------------------------------ lifecycle
  function open(payloadJson) {
    if (root.shell && typeof root.shell.isPluginOpen === "function") {
      var others = ["moarchy.shade", "moarchy.drawer",
                    "moarchy.recents", "moarchy.themes"]
      for (var i = 0; i < others.length; i++)
        if (root.shell.isPluginOpen(others[i])) root.shell.hide(others[i])
    }

    root.returnTo = ""
    var start = "root"
    var resume = false
    try {
      var payload = JSON.parse(String(payloadJson || "{}"))
      if (payload.returnTo) root.returnTo = String(payload.returnTo)
      if (payload.page && Pages.exists(String(payload.page)))
        start = String(payload.page)
      resume = payload.resume === true
    } catch (e) {
      // A malformed payload is not worth refusing to open over.
    }

    // K5. A resume is the carousel handing the screen back to a Settings that
    // was hidden rather than closed, so it comes back on the page it left.
    //
    // `running` is read before it is set, and that ordering is the whole
    // guard: after a close (K6) it is false, so a stale `{resume:true}` --
    // from a card that outlived its screen, or a hand-typed IPC call --
    // rebuilds the stack instead of resuming a page nobody is standing on.
    // docs/settings.md A6 is untouched by this: reopening a *closed* Settings
    // still lands on the root.
    // A rebuilt stack is a different screen, so the fields on the old one go
    // with it; a resume is the same screen coming back and keeps what was typed.
    if (!resume || !root.running) {
      root.stack = root.stackFor(start)
      root.resetFields()
    }
    // Always, and this is the half that open() was missing: `refresh()` runs a
    // provider only while `dynamicLoaded` is false, so an open onto a provider
    // page painted the rows the *last* provider page built -- "No reminders set"
    // under a "Font" header. push() and pop() have always had this through
    // afterPageChange(); open() reached refresh() without it.
    root.resetReadState()
    root.confirmText = ""
    root.running = true
    root.opened = true
    // Deferred, always. See note 1 in the header.
    Qt.callLater(root.refresh)
  }

  // Hidden, not closed. Every hide in this shell lands here -- shell.hide()
  // calls it -- so `running` deliberately survives: the card stays in the
  // carousel and the stack stays standing for K5 to resume.
  function close() { root.opened = false }

  // K6. Closed for good: the card leaves the carousel and the next opening is
  // a fresh one at the root. Exactly two gestures reach this -- flicking the
  // card away (E3) and back on the root page (B3) -- and nothing else may, or
  // a screen that was merely put away comes back having forgotten where it
  // was.
  function quit(): void {
    root.running = false
    root.stack = ["root"]
    root.confirmText = ""
    root.confirmRow = null
    root.hideOnly()
  }

  // Put the surface away without going anywhere. Handing off to another plugin
  // and launching a command both need this: dismiss() would additionally summon
  // whatever opened us, so tapping Screenshot from the shade's gear would take a
  // screenshot of the shade coming back.
  function hideOnly() {
    if (root.shell && typeof root.shell.hide === "function") root.shell.hide(root.pluginId)
    else root.close()
  }

  // Every caller of this means *close*: the header chevron and Escape on the
  // root page, and the two IPC verbs that spell it. K6, so it quits rather
  // than hiding -- the gestures that hide go through shell.hide() instead.
  function dismiss() {
    var back = root.returnTo
    root.returnTo = ""
    root.quit()
    if (back && root.shell && typeof root.shell.summon === "function")
      root.shell.summon(back, "{}")
  }

  // ---------------------------------------------------------- navigation
  function push(pageId) {
    if (!Pages.exists(pageId)) return false
    if (pageId === root.currentPage) return true   // pushing the top is a no-op
    var next = root.stack.slice()
    next.push(pageId)
    root.stack = next
    root.afterPageChange()
    return true
  }

  function pop() {
    if (root.stack.length <= 1) return false
    var next = root.stack.slice()
    next.pop()
    root.stack = next
    root.afterPageChange()
    return true
  }

  // What the left-edge back gesture calls. True means "consumed"; false means
  // there is nothing left to go back to, so the gesture layer closes us.
  function goBack() {
    if (root.confirmText !== "") { root.confirmText = ""; root.confirmRow = null; return true }
    return root.pop()
  }

  // What a page answered: its guards, its reader, and the rows a provider built
  // for it. Every arrival on a page clears this, because keeping any of it is
  // showing the page you came from.
  function resetReadState() {
    root.whenMap = ({})
    root.valueMap = ({})
    root.pageValue = ""
    root.dynamicRows = []
    root.dynamicLoaded = false
  }

  // Fields do not outlive the screen (J12), and the surface must not be left
  // holding a bottom inset for a keyboard whose field has just been
  // destroyed -- a delegate torn down while focused reports no focus loss.
  function resetFields() {
    root.inputMap = ({})
    root.focusedInput = ""
  }

  function afterPageChange() {
    root.resetReadState()
    root.resetFields()
    root.refresh()
  }

  // Re-run a page's provider. `refresh` alone will not: it runs the provider
  // only while `dynamicLoaded` is false, which is what stops it looping.
  function reloadDynamic() {
    var p = root.pageDef
    if (p && (p.provider || p.text)) root.dynamicLoaded = false
    root.refresh()
  }

  // ------------------------------------------------------ reading a page
  //
  // One bash for the whole page. A provider or text page needs its rows before
  // there is anything to ask about, so that runs first and calls back here.
  function refresh() {
    var p = root.pageDef
    if (!p) return
    if ((p.provider || p.text) && !root.dynamicLoaded) {
      root.generation += 1
      dynamicProc.wanted = root.generation
      if (dynamicProc.running) dynamicProc.running = false
      // `json` or `list`, whichever the provider declares. This read
      // `p.provider.list` unconditionally until 2026-09-07, so a json provider
      // was handed `undefined` as its command: the page painted its declared
      // rows and nothing else, which looks exactly like a provider that
      // legitimately found nothing.
      var command = p.provider ? (p.provider.json || p.provider.list) : p.text
      dynamicProc.command = ["bash", "-lc", String(command || "")]
      dynamicProc.running = true
      return
    }
    var script = Guards.build(root.currentRows, p.reader || "")
    if (!script) return
    root.generation += 1
    guardProc.wanted = root.generation
    if (guardProc.running) guardProc.running = false
    guardProc.command = ["bash", "-lc", script]
    guardProc.running = true
  }

  Process {
    id: dynamicProc
    property int wanted: 0
    stdout: StdioCollector {
      onStreamFinished: {
        if (dynamicProc.wanted !== root.generation) return
        var p = root.pageDef
        if (!p) return
        // A `provider.json` answers with the rows themselves -- id, type,
        // label, and the command each one runs -- because a reminder's row
        // carries its own `cancel <unit>`, which one-value-per-line cannot
        // express. JSON and not TSV: the label is a message somebody typed,
        // and a tab in it would silently become a column.
        if (p.provider && p.provider.json) {
          var rows = []
          try {
            var parsed = JSON.parse(String(text || "[]"))
            if (parsed && parsed.length !== undefined) rows = parsed
          } catch (e) {
            // Half a page is worse than an empty one: a provider that answers
            // nothing usable says so with its own info row, and a provider
            // that is not there at all leaves the declared rows alone.
            rows = []
          }
          root.dynamicRows = rows
          root.dynamicLoaded = true
          Qt.callLater(root.refresh)
          return
        }

        var lines = String(text || "").split("\n")
        var built = []
        for (var i = 0; i < lines.length; i++) {
          var line = lines[i]
          if (!line || !line.trim()) continue
          if (p.text) {
            // Columnar output from omarchy-menu-keybindings --print: keys,
            // action, section, padded apart. Two or more spaces is the split.
            var parts = line.split(/\s{2,}/)
            built.push({ id: "k" + i, type: "info",
                         label: (parts[0] || "").trim(),
                         detail: (parts[1] || "").trim() })
          } else {
            var value = line.trim()
            var label = value
            if (p.provider.label === "basename")
              label = value.replace(/^.*\//, "")
            // The same transform omarchy-theme-bg-current applies, so the row
            // that ticks reads the way the Appearance detail line above it does:
            // "Quattro", not "1-quattro.jpg".
            // "Europe/Berlin" -> "Berlin", "America/New_York" -> "New York".
            // The value stays the whole zone, because that is what timedatectl
            // takes and what the reader answers.
            else if (p.provider.label === "city")
              label = value.replace(/^.*\//, "").replace(/_/g, " ")
            else if (p.provider.label === "background")
              label = value.replace(/^.*\//, "").replace(/\.[^.]+$/, "")
                           .replace(/^\d+-/, "").replace(/-/g, " ")
                           .replace(/\b\w/g, function (c) { return c.toUpperCase() })
            built.push({ id: "p" + i, type: "choice", label: label, value: value,
                         write: p.write + " " + root.shellQuote(value) })
          }
        }
        root.dynamicRows = built
        root.dynamicLoaded = true
        Qt.callLater(root.refresh)
      }
    }
  }

  Process {
    id: guardProc
    property int wanted: 0
    stdout: StdioCollector {
      onStreamFinished: {
        if (guardProc.wanted !== root.generation) return
        var parsed = Guards.parse(String(text || ""))
        root.whenMap = parsed.when
        root.valueMap = parsed.value
        root.pageValue = parsed.value["__page"] !== undefined
                         ? String(parsed.value["__page"]) : ""
      }
    }
  }

  // ------------------------------------------------------------ activating
  // Single quotes, not JSON. A double-quoted argument still expands $ and `,
  // and a wallpaper path or a font family is user data.
  function shellQuote(value) {
    return "'" + String(value).split("'").join("'\\''") + "'"
  }

  function commandFor(row) {
    if (!row) return ""
    if (row.type === "link")
      return "omarchy-launch-webapp " + root.shellQuote(String(row.url))
    if (row.type === "choice") return String(row.write || "")
    if (row.launch === "tui")
      return "omarchy-launch-floating-terminal-with-presentation " + String(row.run)
    var cmd = String(row.run || "")
    // Every named field is appended, shell-quoted, even when it is empty: the
    // script's argument positions are fixed, and dropping an empty message
    // would make the next argument the message.
    if (row.argsFrom)
      for (var i = 0; i < row.argsFrom.length; i++)
        cmd += " " + root.shellQuote(root.inputValue(String(row.argsFrom[i])))
    return cmd
  }

  function runCommand(cmd) {
    if (!cmd) return
    root.lastLaunch = cmd
    if (root.dryRun) return
    Quickshell.execDetached(["bash", "-lc", cmd])
  }

  function setSwitch(row, on) {
    if (!row) return
    var cmd = on ? row.on : row.off
    if (!cmd) return
    root.lastLaunch = String(cmd)
    if (root.dryRun) return
    // Process.running rather than execDetached: the write is only half of it,
    // and onExited is what tells us to read the state back. Stopped first
    // because assigning `running = true` to a process already running is a
    // no-op, so a second tap would set a command nothing ever runs.
    if (switchProc.running) switchProc.running = false
    switchProc.command = ["bash", "-lc", String(cmd)]
    switchProc.running = true
  }

  Process {
    id: switchProc
    // reloadDynamic, not refresh: on a provider page `refresh` re-runs the
    // provider only while `dynamicLoaded` is false, so a switch whose state
    // comes from the provider would flip back to the built-in value on the next
    // read. Off a provider page the two are the same call.
    onExited: Qt.callLater(root.reloadDynamic)
  }

  // `confirmed` is a parameter, not a reading of confirmText. It used to arm the
  // sheet whenever `row.confirm` was set and confirmText happened to be empty --
  // and Continue clears confirmText before calling this, so every Continue tap
  // re-armed the very sheet it was dismissing. The button looked dead: the
  // dialog never closed and the action never ran.
  function activate(row, confirmed) {
    if (!row) return
    // Before the confirm sheet, not after: a row that cannot act must not be
    // able to ask a question either. The IPC form answers `not ready`, because
    // a test has to tell "refused" from "ran and did nothing".
    if (!root.rowEnabled(row)) return
    if (row.confirm && !confirmed) {
      root.confirmText = String(row.confirm)
      root.confirmRow = row
      return
    }
    root.confirmText = ""
    root.confirmRow = null

    if (row.type === "nav") { root.push(row.page); return }

    if (row.type === "plugin") {
      var target = String(row.plugin)
      var here = root.currentPage
      root.hideOnly()
      if (root.shell && typeof root.shell.summon === "function")
        root.shell.summon(target, JSON.stringify({ returnTo: root.pluginId,
                                                   page: here }))
      return
    }

    if (row.type === "switch") { root.setSwitch(row, !root.rowChecked(row)); return }

    if (row.type === "choice") {
      root.runCommand(root.commandFor(row))
      // Re-read rather than assume: the reader is the truth, and a write that
      // did not take must not leave the tick moved.
      if (!root.dryRun) Qt.callLater(root.refresh)
      return
    }

    if (row.type === "info" || row.type === "input") return

    var cmd = root.commandFor(row)

    // `inline` is a native action: no terminal to uncover and no vendored
    // picker to get out from under, so the screen stays up and the page reads
    // itself again when the command exits (J6). `back` pops first, so the tap
    // is answered now rather than when the script finishes.
    if (row.launch === "inline") {
      root.lastLaunch = cmd
      if (root.dryRun) return
      if (inlineProc.running) inlineProc.running = false
      inlineProc.command = ["bash", "-lc", cmd]
      inlineProc.running = true
      if (row.back) root.pop()
      return
    }

    // action, link. Settings goes away first so the terminal or the vendored
    // picker is not underneath a layer surface -- and so a screenshot is not
    // a screenshot of this screen.
    if (!root.dryRun) root.hideOnly()
    root.runCommand(cmd)
  }

  // Separate from switchProc so a write and a native action cannot cancel each
  // other: assigning a command to a Process that is already running is a no-op,
  // and these two are started from different taps.
  Process {
    id: inlineProc
    onExited: Qt.callLater(root.reloadDynamic)
  }

  // ------------------------------------------------------------------ IPC
  IpcHandler {
    target: "settings"

    function state(): string { return root.opened ? "open" : "closed" }

    // K1/K6. `state` answers whether the surface is on screen, which stopped
    // being the same question once a hidden Settings kept its card. Both
    // verbs below are here so a test can tell the two apart without reading
    // the carousel's list and inferring.
    function running(): string { return root.running ? "running" : "stopped" }

    // Hide without closing -- what the strip's up-swipe does (K4), reachable
    // without a finger. `close` remains the one that quits.
    function hide(): string { root.hideOnly(); return "ok" }

    // K5. What tapping the card does: come back on the page it was hidden on.
    function resume(): string {
      if (root.shell)
        root.shell.summon(root.pluginId, JSON.stringify({ resume: true }))
      return "ok"
    }

    // Quickshell's typed IPC has no optional arguments -- a declared parameter
    // is required -- so the no-argument and one-argument forms are separate
    // functions rather than one with a default.
    function open(): string {
      if (root.shell) root.shell.summon(root.pluginId, "{}")
      return "ok"
    }

    function openAt(page: string): string {
      if (!Pages.exists(page)) return "unknown page: " + page
      if (root.shell)
        root.shell.summon(root.pluginId, JSON.stringify({ page: page }))
      return "ok"
    }

    function close(): string { root.dismiss(); return "ok" }

    function toggle(): string {
      if (root.shell) root.shell.toggle(root.pluginId, "{}")
      return root.opened ? "open" : "closed"
    }

    function page(): string { return root.currentPage }

    function stack(): string { return root.stack.join("\n") }

    function goto(page: string): string {
      if (!Pages.exists(page)) return "unknown page: " + page
      root.push(page)
      return "ok"
    }

    function back(): string {
      if (root.goBack()) return root.currentPage
      root.dismiss()
      return "closed"
    }

    // TSV so a value with a space in it survives: rowId, type, label, visible,
    // checked, detail. Visibility and state are only real for the page that is
    // actually open -- another page's guards have not been run, and answering
    // "0" for those would read as "hidden" rather than "not asked".
    function rows(): string { return root.rowsTsv(root.currentPage) }

    function rowsOn(page: string): string { return root.rowsTsv(page) }

    // Accepts a row id, or the id of the open choice page -- "what is the DNS
    // set to" is a question about the page, not about one of its four rows.
    function value(rowId: string): string {
      if (rowId === root.currentPage && root.pageDef && root.pageDef.reader)
        return root.pageValue
      var row = root.rowById(rowId)
      if (!row) return "unknown row"
      if (row.type === "switch") return root.rowChecked(row) ? "on" : "off"
      if (row.type === "choice") return root.pageValue
      if (row.type === "input") return root.inputValue(rowId)
      return String(root.valueMap[rowId] || "")
    }

    function set(rowId: string, value: string): string {
      var row = root.rowById(rowId)
      // Setting the page sets whichever of its rows carries that value.
      if (!row && rowId === root.currentPage && root.pageDef && root.pageDef.reader)
        row = root.rowByValue(value)
      if (!row) return "unknown row"
      if (!root.rowVisible(row)) return "hidden"
      if (row.type === "switch") {
        root.setSwitch(row, value === "on" || value === "true" || value === "1")
        return "ok"
      }
      if (row.type === "choice") {
        root.runCommand(root.commandFor(row))
        if (!root.dryRun) Qt.callLater(root.refresh)
        return "ok"
      }
      // The only way to put text in a field without a finger and a keyboard,
      // which is what makes J7 to J9 checkable over ssh at all.
      if (row.type === "input") {
        root.setInput(rowId, value)
        return "ok"
      }
      return "not settable"
    }

    function activate(rowId: string): string {
      var row = root.rowById(rowId)
      if (!row) return "unknown row"
      if (!root.rowVisible(row)) return "hidden"
      if (!root.rowEnabled(row)) return "not ready"
      root.activate(row)
      return "ok"
    }

    // A row carrying `confirm` arms a question and returns; without these two
    // there was no verb that could answer it, so no destructive row could be
    // exercised from a terminal at all (J4, J5).
    function confirmText(): string { return root.confirmText }

    function confirm(): string {
      var row = root.confirmRow
      if (root.confirmText === "" && !row) return "nothing to confirm"
      root.confirmText = ""
      root.confirmRow = null
      if (row) root.activate(row, true)
      return "ok"
    }

    // Which field holds the keyboard, and therefore why the bottom inset is
    // where it is (J11).
    function focused(): string { return root.focusedInput }

    function guards(): string {
      var out = []
      var rows = root.currentRows
      for (var i = 0; i < rows.length; i++)
        out.push(rows[i].id + "\t" + (root.rowVisible(rows[i]) ? "1" : "0"))
      return out.join("\n")
    }

    // reloadDynamic, not refresh: `refresh` runs a page's provider only while
    // `dynamicLoaded` is false, so on a provider page the plain form re-ran the
    // guards and left the list exactly as it was. Two reminders set from a
    // terminal and a page still reading "No reminders set", with the Clear all
    // guard correctly flipped on above it (J13).
    function refresh(): string { root.reloadDynamic(); return "ok" }

    function dryRun(on: string): string {
      root.dryRun = (on === "1" || on === "true" || on === "on")
      return "ok"
    }

    // Readable, because the selftest's most delicate block rests on it. `dryRun`
    // is the precondition for every check that activates a row without wanting
    // it to happen, and a dropped call left the run *really* activating things:
    // the row ran, `back: true` popped the page, and the next `activate`
    // answered "unknown row" -- a red J9 that said nothing about J9. A verb that
    // can only be written cannot be asserted before it is relied on.
    function dryRunState(): string { return root.dryRun ? "1" : "0" }

    function lastLaunch(): string { return root.lastLaunch }

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
      var gap = Math.round(settingsWindow.height - rowList.mapToItem(null, 0, rowList.height).y + rowList.bottomMargin)
      return "w=" + settingsWindow.width
           + " h=" + settingsWindow.height
           + " margin=" + settingsWindow.margins.bottom
           + " strip=" + root.gestureStrip
           + " gap=" + gap
           + " screen=" + (settingsWindow.screen
               ? settingsWindow.screen.width + "x" + settingsWindow.screen.height : "?")
    }


    // Emitted from Pages.js, not from the doc -- which is what makes coverage
    // parity a bash assertion rather than a promise.
    function coverage(): string {
      var rows = Pages.coverage()
      var out = []
      var names = { N: "Native", B: "Bridged", S: "Shade" }
      for (var i = 0; i < rows.length; i++)
        out.push([rows[i][0], names[rows[i][1]] || rows[i][1],
                  rows[i][2], rows[i][3]].join("\t"))
      return out.join("\n")
    }
  }

  // --------------------------------------------------------------- surface
  PanelWindow {
    id: settingsWindow

    visible: root.opened
    anchors { top: true; bottom: true; left: true; right: true }
    color: "transparent"

    WlrLayershell.namespace: "moarchy-settings"
    WlrLayershell.layer: WlrLayer.Top

    exclusionMode: ExclusionMode.Normal
    exclusiveZone: 0

    // Extend past the bottom of the usable area, under the gesture strip. A
    // zero exclusive zone means sway arranges this *into* what the exclusive
    // surfaces left, so without this the sheet stops at the top of the strip
    // and a band of wallpaper -- or of the app behind -- shows under it with
    // the pill drawn on it (docs/gestures.md I1).
    //
    // The exclusion mode is deliberately untouched. The strip still reserves
    // its band off every window and this surface is still arranged around the
    // on-screen keyboard, because a margin moves only this surface's own bottom
    // edge. Reserving and drawing-under are separate questions.
    //
    // Negative is legal, not a trick: wlroots stores layer-shell margins as
    // int32_t and computes `box.height = bounds.height - (margin.top +
    // margin.bottom)` with no clamping, and sway delegates to it and adds no
    // validation of its own.
    //
    // Gated on focus since Set a reminder gave Settings its first text field
    // (J11). The inset is what lets the sheet draw under the gesture strip;
    // while a field has the keyboard it has to go, or the field ends up behind
    // it. Keyed on focus rather than on the keyboard being visible, because
    // focus is the signal that arrives first -- the same arrangement the Wi-Fi
    // passphrase field and the drawer's search field use.
    margins.bottom: root.focusedInput !== "" ? 0 : -root.gestureStrip
    WlrLayershell.keyboardFocus: root.opened ? WlrKeyboardFocus.Exclusive
                                             : WlrKeyboardFocus.None

    Rectangle {
      anchors.fill: parent
      color: root.surface
      opacity: root.opened ? 1 : 0
      Behavior on opacity { NumberAnimation { duration: 140 } }

      focus: true
      Keys.onEscapePressed: { if (!root.goBack()) root.dismiss() }

      Column {
        anchors.fill: parent
        anchors.leftMargin: Style.space(12)
        anchors.rightMargin: Style.space(12)
        anchors.topMargin: Style.space(8)
        anchors.bottomMargin: Style.space(8)
        spacing: Style.space(10)

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

            PressVeil { anchors.fill: parent; radius: parent.radius; on: backArea.pressed }

            // fa-angle-left, and centred on its ink rather than on its advance
            // -- both for the same reason the row chevron is. `anchors.centerIn`
            // centres the box the font reserves, and a Nerd Font glyph is rarely
            // centred inside that box; measured on this circle the gear in the
            // shade's matching button sat 4 device pixels right of centre.
            Ui.OpticalGlyph {
              anchors.fill: parent
              text: ""
              fontFamily: Style.font.family
              fontSize: Style.font.icon
              color: root.textOnSurface
            }
            // Answers over 44 while staying drawn at 38 (docs/style.md E1,
            // E2). The header is 44 tall and the circle is centred in it,
            // so the 3px is already there vertically; horizontally it eats into
            // the surface margin on one side and the 12px before the title on
            // the other, and neither takes a tap.
            MouseArea {
              id: backArea
              anchors.fill: parent
              anchors.margins: -Style.space(3)
              onClicked: { if (!root.goBack()) root.dismiss() }
            }
          }

          Text {
            anchors.left: backButton.right
            anchors.leftMargin: Style.space(12)
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            text: root.pageTitle
            font.family: Style.font.family
            font.pixelSize: Style.font.heading
            font.weight: root.textWeight
            color: root.textOnSurface
            elide: Text.ElideRight
          }
        }

        ListView {
          id: rowList
          width: parent.width
          height: Math.max(0, parent.height - y)
          clip: true
          spacing: Style.space(6)
          // Scroll padding, so the last row rests a strip clear of the home
          // pill now that the page runs under it (docs/gestures.md I4).
          bottomMargin: root.gestureStrip
          model: root.currentRows
          boundsBehavior: Flickable.StopAtBounds
          interactive: contentHeight > height
          cacheBuffer: Style.space(58) * 4

          delegate: SettingsRow {
            required property var modelData
            width: rowList.width
            visible: root.rowVisible(modelData)
            height: visible ? Style.space(58) : 0
            color: root.container
            rowType: modelData.type
            glyph: modelData.glyph || ""
            label: modelData.label || ""
            detail: root.rowDetail(modelData)
            checked: root.rowChecked(modelData)
            rowEnabled: root.rowEnabled(modelData)
            placeholder: modelData.placeholder || ""
            numeric: modelData.numeric === true
            inputText: modelData.type === "input"
                       ? root.inputValue(modelData.id) : ""
            textColor: root.textOnSurface
            subduedColor: root.subdued
            accentColor: root.accent
            onActivated: root.activate(modelData)
            onEdited: function (value) { root.setInput(modelData.id, value) }
            // The id, not a bool: two fields on this page, and clearing the
            // flag on the one that just lost focus to the other would drop the
            // inset for a frame and bounce the keyboard.
            onFocusTaken: function (has) {
              if (has) root.focusedInput = modelData.id
              else if (root.focusedInput === modelData.id) root.focusedInput = ""
            }
          }
        }
      }

      // ------------------------------------------------------- confirm
      Rectangle {
        anchors.fill: parent
        visible: root.confirmText !== ""
        color: Util.alpha(root.surface, 0.92)

        MouseArea {
          // no press state (style.md H7): a tap swallower behind a modal. It
          // exists to stop taps reaching the page under the confirm card.
          anchors.fill: parent
        }

        Rectangle {
          anchors.centerIn: parent
          width: parent.width - Style.space(48)
          height: confirmCol.implicitHeight + Style.space(32)
          radius: root.radiusCard
          color: root.container

          Column {
            id: confirmCol
            anchors.centerIn: parent
            width: parent.width - Style.space(32)
            spacing: Style.space(16)

            Text {
              width: parent.width
              text: root.confirmText
              wrapMode: Text.WordWrap
              font.family: Style.font.family
              font.pixelSize: Style.font.body
              font.weight: root.textWeight
              color: root.textOnSurface
            }

            Row {
              anchors.horizontalCenter: parent.horizontalCenter
              spacing: Style.space(12)

              Rectangle {
                width: Style.space(110); height: Style.space(44)
                radius: height / 2
                color: Util.alpha(root.textOnSurface, 0.10)
                PressVeil { anchors.fill: parent; radius: parent.radius; on: cancelArea.pressed }
                Text {
                  anchors.centerIn: parent; text: "Cancel"
                  font.family: Style.font.family; font.pixelSize: Style.font.body
                  font.weight: root.textWeight
                  color: root.textOnSurface
                }
                MouseArea {
                  id: cancelArea
                  anchors.fill: parent
                  onClicked: { root.confirmText = ""; root.confirmRow = null }
                }
              }

              Rectangle {
                width: Style.space(110); height: Style.space(44)
                radius: height / 2
                color: root.accent
                // This surface has no `textOnAccent` role, and H4 wants the
                // control's own ink: the label below is already root.surface.
                PressVeil {
                  anchors.fill: parent
                  radius: parent.radius
                  ink: root.surface
                  on: continueArea.pressed
                }
                Text {
                  anchors.centerIn: parent; text: "Continue"
                  font.family: Style.font.family; font.pixelSize: Style.font.body
                  font.weight: root.textWeight
                  color: root.surface
                }
                MouseArea {
                  id: continueArea
                  anchors.fill: parent
                  onClicked: {
                    var row = root.confirmRow
                    root.confirmText = ""
                    root.confirmRow = null
                    if (row) root.activate(row, true)
                  }
                }
              }
            }
          }
        }
      }
    }
  }
}
