// Mail, in the shell: one account, its folders, and the messages in them.
//
// Five screens. **Sign in** is an address and a password, with the servers
// found for you and shown so they can be changed. **A folder** is its messages,
// newest first, unread in bold, with drafts and anything not yet sent at the
// top of the Inbox. **Folders** is the list, and the account. **A message** is
// the text, its attachments, and Reply, Reply all and Forward. **Writing** is
// To, Cc, Subject and the text, with names from Contacts.
//
// This replaces Geary. Every word said to a server goes through moarchy-mail
// (bin/), one process per request, because QML cannot open a TLS socket; the
// app keeps what it was told in JSON files it alone writes, so a folder draws
// from the file first and from the server when it answers. The shell keeps the
// plugin loaded, and every fifteen minutes it asks the Inbox what is new --
// one short run of moarchy-mail, not a process sitting on a connection.
//
// No HTML is drawn. moarchy-mail turns a message into text and links, and
// what reaches the Text below has no tag in it moarchy-mail did not write.
pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import "ui" as Chrome
import "ui/Theme.js" as Theme
import "ui/Metrics.js" as Metrics
import "ui/Plugin.js" as Plugin
import "Address.js" as Address
import "Compose.js" as Compose
import "Helper.js" as Helper
import "Mailbox.js" as Mailbox
import "Store.js" as Store

Item {
  id: root

  property var shell: null
  property var manifest: null
  property var barWidgetRegistry: null
  property var pluginRegistry: null
  property var service: null

  readonly property string pluginId: "org.moarchy.mail"
  readonly property bool opened: mailWindow.visible
  readonly property var appWindow: mailWindow

  property string returnTo: ""
  readonly property var colours: themeFile.colours
  property int bodySize: Metrics.BODY
  readonly property int shellFurniture: root.shell ? 60 : 0

  readonly property bool offline: (Quickshell.env("MOARCHY_MAIL_OFFLINE") || "") !== ""
  readonly property string helper: Quickshell.env("MOARCHY_MAIL_HELPER") || "moarchy-mail"

  readonly property string dataDir: Plugin.dataDir(
    "mail", Quickshell.env("HOME"), Quickshell.env("XDG_DATA_HOME"),
    Quickshell.env("MOARCHY_MAIL_DIR"))
  readonly property string contactsPath: Plugin.dataDir(
    "contacts", Quickshell.env("HOME"), Quickshell.env("XDG_DATA_HOME"),
    Quickshell.env("MOARCHY_CONTACTS_DIR")) + "/contacts.json"

  readonly property color background: root.colours.background
  readonly property color ink: root.colours.foreground
  readonly property color dim: root.colours.dim
  readonly property color accent: root.colours.accent
  readonly property color red: (root.colours.hues && root.colours.hues.red) || "#e01b24"
  readonly property color yellow: (root.colours.hues && root.colours.hues.yellow) || "#f5c211"

  // moarchy-mail draws quoted text in this, because it cannot know the theme.
  readonly property string quoteInk: "#8a8a8f"
  // A folder drawn from its file is refreshed when it is older than this.
  readonly property int staleMs: 2 * 60 * 1000
  readonly property int peekMs: 15 * 60 * 1000

  readonly property string iconDir: "/usr/share/icons/Adwaita/symbolic/"

  // --- state ----------------------------------------------------------------------

  // "setup" | "list" | "folders" | "message" | "compose"
  property string page: "list"
  property bool warm: false
  // The list is built the first time the window is, and kept: coming back
  // from a message to a list scrolled back to the top is a list that forgot.
  // Every other screen exists only while it is on screen, because a mail app
  // is closed far more than it is open and the shell holds it all the time.
  property bool everShown: false

  property var account: null
  property bool accountKnown: false
  property bool editingAccount: false

  property var folders: []
  property bool foldersLoaded: false
  property bool foldersBusy: false

  property bool stateLoaded: false
  property string folder: "INBOX"
  property var inbox: ({ uidvalidity: 0, uidnext: 0, account: "" })
  property var drafts: []
  property var outbox: []

  property var box: Mailbox.empty("INBOX")
  property bool boxLoaded: false
  property string syncingFolder: ""
  property bool loadingOlder: false
  property string syncError: ""
  property var pending: ({})
  property int seq: 0
  property bool peeking: false
  property bool peekDue: false

  property var people: []
  property real now: Date.now()

  property var openRow: null
  property var body: null
  property bool bodyLoading: false
  property string bodyError: ""

  property var compose: Compose.blank(0)
  property string composeFrom: "list"
  property bool showCc: false
  property bool sendArmed: false
  property bool discardArmed: false

  property var menuRow: null
  property var menuExtra: null
  property bool messageMenu: false
  property bool armed: false
  property string linkHref: ""

  property string setupError: ""
  property string setupNote: ""
  property bool signingIn: false
  property bool forgetArmed: false

  property var readQueue: []
  property var actQueue: []

  readonly property bool syncing: root.syncingFolder !== "" && root.syncingFolder === root.folder
  readonly property string folderLabel: Store.label(root.folders, root.folder)
  readonly property string folderRole: {
    var f = Store.find(root.folders, root.folder)
    return f ? f.role : (root.folder === "INBOX" ? "inbox" : "")
  }
  readonly property string sentFolder: Store.byRole(root.folders, "sent")
  readonly property string trashFolder: Store.byRole(root.folders, "trash")
  readonly property string archiveFolder: Store.byRole(root.folders, "archive")
  readonly property string junkFolder: Store.byRole(root.folders, "junk")
  readonly property int unseen: Mailbox.unseen(root.box, root.pending)

  // What is drawn is only built while somebody can see it.
  readonly property bool showing: mailWindow.visible
  readonly property var rows: root.showing && root.page === "list" ? Mailbox.view(root.box, root.pending) : []
  readonly property var extras: {
    if (!root.showing || root.page !== "list" || root.folder !== "INBOX") return []
    var out = []
    for (var i = 0; i < root.outbox.length; i++) out.push({ kind: "outbox", item: root.outbox[i] })
    for (var j = 0; j < root.drafts.length; j++) out.push({ kind: "draft", item: root.drafts[j] })
    return out
  }
  readonly property var shownRow: Mailbox.shown(root.folder, root.openRow, root.pending)
  readonly property var menuShown: Mailbox.shown(root.folder, root.menuRow, root.pending)
  readonly property string bodyMarkup: root.body ? String(root.body.markup || "").split(root.quoteInk).join(String(root.dim)) : ""
  readonly property bool canReplyAll: {
    if (!root.body || !root.account) return false
    var both = Address.replyAll(root.body, root.account.email)
    return both.to.length + both.cc.length > 1
  }

  // --- the plugin contract ----------------------------------------------------------

  Component.onCompleted: root.bodySize = Metrics.shellBody(root)

  function open(payloadJson: string): void {
    Plugin.hideOverlays(root.shell)
    var ask = Compose.parsePayload(payloadJson, Date.now())
    root.returnTo = ask.returnTo
    root.warmUp()
    mailWindow.show()
    if (ask.draft) root.startCompose(ask.draft, root.page === "compose" ? "list" : root.page)
  }

  function close(): void {
    root.closeMenus()
    mailWindow.hide()
  }

  function dismiss(): void {
    root.close()
    if (root.shell && typeof root.shell.hide === "function") root.shell.hide(root.pluginId)
    var back = root.returnTo
    root.returnTo = ""
    if (back && root.shell && typeof root.shell.summon === "function")
      root.shell.summon(back, "{}")
  }

  function closeMenus(): void {
    root.menuRow = null
    root.menuExtra = null
    root.messageMenu = false
    root.linkHref = ""
    root.armed = false
  }

  function back(): void {
    if (root.menuRow || root.menuExtra || root.messageMenu || root.linkHref) { root.closeMenus(); return }
    if (root.page === "compose") { root.leaveCompose(); return }
    if (root.page === "message") { root.closeMessage(); return }
    if (root.page === "folders") { root.page = "list"; root.forgetArmed = false; return }
    if (root.page === "setup" && root.account) { root.page = "list"; root.editingAccount = false; return }
    root.dismiss()
  }

  function say(text: string): void { toast.show(text) }

  function warmUp(): void {
    if (root.warm) return
    root.warm = true
    ensureDir.running = true
  }

  // Everything that waits on the files having been read, and on a window.
  function whenReady(): void {
    if (!root.account || !root.stateLoaded || !root.boxLoaded || !root.showing) return
    if (root.page === "list" && Date.now() - root.box.at > root.staleMs) root.refresh(false)
    if (root.foldersLoaded && root.folders.length === 0) root.refreshFolders()
  }

  // --- jobs -----------------------------------------------------------------------------
  //
  // Two lanes, so that opening a message is not queued behind a folder that is
  // taking its time. "read" is refreshing: sync, folders, peek, autoconfig.
  // "act" is everything a person did: open, mark, move, send, sign in.

  function run(verb: string, input: var, lane: string, context: var, urgent: bool): void {
    var job = { verb: verb, input: input || {}, context: context || {} }
    var queue = lane === "read" ? root.readQueue : root.actQueue
    if (urgent) queue.unshift(job)
    else queue.push(job)
    root.pump(lane)
  }

  function pump(lane: string): void {
    var proc = lane === "read" ? readLane : actLane
    var queue = lane === "read" ? root.readQueue : root.actQueue
    if (proc.running || proc.job || queue.length === 0) return
    var job = queue.shift()
    if (root.offline) {
      Qt.callLater(function () {
        root.finished(job, { ok: false, kind: "offline", error: "Mail is offline here." })
        root.pump(lane)
      })
      return
    }
    proc.job = job
    proc.stdinEnabled = true
    proc.command = Helper.command(root.helper, job.verb)
    proc.running = true
  }

  function finished(job: var, answer: var): void {
    switch (job.verb) {
    case "autoconfig": root.autoconfigured(job, answer); break
    case "setup": root.setUp(job, answer); break
    case "forget": root.forgotten(answer); break
    case "folders": root.foldersListed(answer); break
    case "sync": root.synced(job, answer); break
    case "peek": root.peeked(answer); break
    case "body": root.bodyFetched(job, answer); break
    case "attachment": root.attachmentSaved(job, answer); break
    case "flag": case "move": case "delete": root.changed(job, answer); break
    case "send": root.mailSent(job, answer); break
    }
  }

  // --- files ------------------------------------------------------------------------------

  function cachePath(folder: string): string {
    var email = root.account ? root.account.email : ""
    return root.dataDir + "/cache/" + Qt.md5(email + "\n" + folder) + ".json"
  }

  function saveState(): void {
    if (!root.stateLoaded) return
    stateFile.setText(Store.serializeState({
      folder: root.folder, inbox: root.inbox, drafts: root.drafts, outbox: root.outbox
    }))
  }

  function saveBox(): void {
    if (!root.boxLoaded || !boxFile.path) return
    boxFile.setText(Mailbox.serialize(root.box))
  }

  function saveFolders(): void {
    if (!root.foldersLoaded || !root.account) return
    foldersFile.setText(Store.serializeFolders(root.folders, root.account.email))
  }

  // --- a folder -------------------------------------------------------------------------

  function openFolder(name: string): void {
    root.closeMenus()
    root.page = "list"
    root.forgetArmed = false
    if (name === root.folder && root.boxLoaded) {
      root.refresh(false)
      return
    }
    root.folder = name
    root.box = Mailbox.empty(name)
    root.boxLoaded = false
    root.loadingOlder = false
    root.syncError = ""
    root.saveState()
  }

  function refresh(older: bool): void {
    if (!root.account || !root.boxLoaded) return
    if (older) {
      if (root.loadingOlder) return
      root.loadingOlder = true
    } else if (root.syncing) {
      return
    }
    root.syncingFolder = root.folder
    root.run("sync", {
      folder: root.folder, uidvalidity: root.box.uidvalidity, uids: Mailbox.uids(root.box),
      limit: 50, older: older
    }, "read", { folder: root.folder, older: older }, false)
  }

  function synced(job: var, answer: var): void {
    if (job.context.folder !== root.folder) return
    root.syncingFolder = ""
    if (job.context.older) root.loadingOlder = false
    if (!answer.ok) {
      root.syncError = answer.kind === "offline" ? "" : answer.error
      return
    }
    root.syncError = ""
    root.box = Mailbox.merge(root.box, answer, Date.now())
    root.saveBox()
    root.folders = Store.withCounts(root.folders, root.folder, answer.unseen, answer.exists)
    root.saveFolders()
    if (root.folder === "INBOX") root.noteInbox(answer.uidvalidity, answer.uidnext)
  }

  function refreshFolders(): void {
    if (!root.account || root.foldersBusy) return
    root.foldersBusy = true
    root.run("folders", {}, "read", {}, false)
  }

  function foldersListed(answer: var): void {
    root.foldersBusy = false
    if (!answer.ok) {
      if (!Helper.quiet(answer) && root.page === "folders") root.say(answer.error)
      return
    }
    root.folders = Store.parseFolders(answer)
    root.saveFolders()
    if (root.folder !== "INBOX" && !Store.find(root.folders, root.folder)) root.openFolder("INBOX")
  }

  // --- new mail -----------------------------------------------------------------------------

  function noteInbox(uidvalidity: real, uidnext: real): void {
    var email = root.account ? root.account.email : ""
    var same = root.inbox.uidvalidity === uidvalidity && root.inbox.account === email
    root.inbox = {
      uidvalidity: uidvalidity,
      uidnext: same ? Math.max(root.inbox.uidnext, uidnext) : uidnext,
      account: email
    }
    root.saveState()
  }

  // Asked for by a timer that may fire before the files are read.
  function peekWhenReady(): void {
    if (!root.peekDue || !root.account || !root.stateLoaded) return
    root.peekDue = false
    root.peek()
  }

  function peek(): void {
    if (!root.account || root.peeking || !root.stateLoaded) return
    root.peeking = true
    var same = root.inbox.account === root.account.email
    root.run("peek", {
      uidvalidity: same ? root.inbox.uidvalidity : 0,
      since: same ? root.inbox.uidnext : 0
    }, "read", {}, false)
  }

  function peeked(answer: var): void {
    root.peeking = false
    if (!answer.ok || !root.account) return
    var known = root.inbox.account === root.account.email && root.inbox.uidvalidity === answer.uidvalidity
    var fresh = known && root.inbox.uidnext > 0 ? (answer.rows || []) : []
    root.noteInbox(answer.uidvalidity, answer.uidnext)
    var inboxFolder = Store.find(root.folders, "INBOX")
    root.folders = Store.withCounts(root.folders, "INBOX", answer.unseen, inboxFolder ? inboxFolder.total : 0)
    root.saveFolders()
    if (fresh.length) root.arrived(fresh)
  }

  function arrived(list: var): void {
    root.now = Date.now()
    if (root.folder === "INBOX" && root.showing) root.refresh(false)
    if (root.showing && root.page === "list" && root.folder === "INBOX") return
    ping.command = ["sh", "-c", "exec fbcli -E message-new-email -t -1 -w 30", "fbcli"]
    ping.running = true
    if (list.length === 1) {
      Quickshell.execDetached(root.notifyCommand(Address.label(list[0].from) || "New mail",
                                                 list[0].subject || "No subject"))
    } else {
      var names = list.map(function (r) { return Address.label(r.from) })
      Quickshell.execDetached(root.notifyCommand(list.length + " new messages", names.join(", ")))
    }
  }

  function notifyCommand(title: string, text: string): var {
    return ["sh", "-c",
            "command -v omarchy-notification-send >/dev/null 2>&1 || exit 0\n" +
            "exec omarchy-notification-send \"$1\" \"$2\" >/dev/null 2>&1",
            "sh", title, text]
  }

  // --- a message ------------------------------------------------------------------------

  function openMessage(row: var): void {
    root.closeMenus()
    root.openRow = row
    root.body = null
    root.bodyError = ""
    root.bodyLoading = true
    root.page = "message"
    var path = Mailbox.bodyPath(root.dataDir, Qt.md5(root.folder), root.box.uidvalidity, row.uid)
    if (bodyFile.path === path) bodyFile.reload()
    else bodyFile.path = path
    if (!Mailbox.has(row, Mailbox.SEEN)) root.setFlag([row.uid], "seen", true)
  }

  function closeMessage(): void {
    root.closeMenus()
    root.page = "list"
    root.openRow = null
    root.body = null
    bodyFile.path = ""
  }

  function fetchBody(): void {
    if (!root.openRow) return
    root.bodyLoading = true
    root.bodyError = ""
    root.run("body", { folder: root.folder, uidvalidity: root.box.uidvalidity, uid: root.openRow.uid },
             "act", { folder: root.folder, uid: root.openRow.uid }, true)
  }

  function bodyFetched(job: var, answer: var): void {
    if (!root.openRow || job.context.uid !== root.openRow.uid || job.context.folder !== root.folder) return
    root.bodyLoading = false
    if (answer.ok) {
      root.body = answer
      return
    }
    root.bodyError = answer.kind === "offline" ? "This message has not been downloaded." : answer.error
    if (answer.kind === "gone") {
      root.box = Mailbox.without(root.box, [job.context.uid])
      root.saveBox()
    }
  }

  function followLink(link: string): void {
    if (!root.body) return
    var href = (root.body.links || [])[parseInt(String(link).slice(1), 10)]
    if (!href) return
    if (/^mailto:/i.test(href)) {
      root.startCompose(Compose.fromMailto(href, Date.now()), "message")
      return
    }
    root.linkHref = href
  }

  function copyText(text: string, said: string): void {
    clip.text = text
    clip.selectAll()
    clip.copy()
    clip.text = ""
    root.say(said)
  }

  function saveAttachment(file: var): void {
    if (!root.openRow) return
    root.say("Saving " + file.name + "…")
    root.run("attachment", {
      folder: root.folder, uidvalidity: root.box.uidvalidity, uid: root.openRow.uid, index: file.index
    }, "act", { name: file.name }, true)
  }

  function attachmentSaved(job: var, answer: var): void {
    if (!answer.ok) { root.say(answer.error); return }
    root.say("Saved to Downloads")
    Quickshell.execDetached(["xdg-open", answer.path])
  }

  // --- marking, moving, deleting ------------------------------------------------------------

  function setFlag(uids: var, what: string, on: bool): void {
    root.seq += 1
    var flag = what === "seen" ? Mailbox.SEEN : Mailbox.FLAGGED
    root.pending = Mailbox.withPending(root.pending, root.folder, uids, what, on, root.seq)
    root.run("flag", {
      folder: root.folder, uids: uids, add: on ? [flag] : [], remove: on ? [] : [flag]
    }, "act", { folder: root.folder, uids: uids, what: what, on: on, flag: flag, seq: root.seq }, false)
  }

  function moveTo(uids: var, target: string, said: string): void {
    root.seq += 1
    root.pending = Mailbox.withPending(root.pending, root.folder, uids, "gone", true, root.seq)
    root.run("move", { folder: root.folder, uids: uids, to: target },
             "act", { folder: root.folder, uids: uids, what: "gone", seq: root.seq }, false)
    if (root.page === "message") root.closeMessage()
    if (said) root.say(said)
  }

  // To Trash, or -- in Trash, or with no Trash -- gone. The second is asked twice.
  function remove(row: var): bool {
    if (root.trashFolder && root.folder !== root.trashFolder) {
      root.moveTo([row.uid], root.trashFolder, "Moved to " + Store.label(root.folders, root.trashFolder))
      return true
    }
    if (!root.armed) {
      root.armed = true
      return false
    }
    root.armed = false
    root.seq += 1
    root.pending = Mailbox.withPending(root.pending, root.folder, [row.uid], "gone", true, root.seq)
    root.run("delete", { folder: root.folder, uids: [row.uid] },
             "act", { folder: root.folder, uids: [row.uid], what: "gone", seq: root.seq }, false)
    if (root.page === "message") root.closeMessage()
    root.say("Deleted")
    return true
  }

  function changed(job: var, answer: var): void {
    var c = job.context
    root.pending = Mailbox.clearPending(root.pending, c.folder, c.uids, c.what, c.seq)
    if (!answer.ok) {
      if (answer.kind !== "offline") root.say(answer.error)
      return
    }
    if (c.folder !== root.folder) return
    if (c.what === "gone") root.box = Mailbox.without(root.box, c.uids)
    else root.box = Mailbox.withFlag(root.box, c.uids, c.flag, c.on)
    root.saveBox()
    root.folders = Store.withCounts(root.folders, root.folder, root.box.unseen, root.box.exists)
    root.saveFolders()
  }

  // --- writing -----------------------------------------------------------------------------

  function startCompose(draft: var, from: string): void {
    root.closeMenus()
    root.compose = draft
    root.composeFrom = from || "list"
    root.showCc = draft.cc.length > 0 || draft.bcc.length > 0
    root.sendArmed = false
    root.discardArmed = false
    // A page that is not up yet fills itself from root.compose as it is made.
    if (root.page === "compose" && composePage.item) (composePage.item as ComposeForm).load(draft)
    else root.page = "compose"
  }

  // What is in the form now, or the draft as it was if the form is gone.
  function typedDraft(): var {
    return composePage.item ? (composePage.item as ComposeForm).typed() : root.compose
  }

  function afterCompose(): void {
    root.page = root.composeFrom === "message" && root.openRow ? "message" : "list"
  }

  // Back keeps what was written, unless nothing was.
  function leaveCompose(): void {
    var d = root.typedDraft()
    if (Compose.isEmpty(d) || Compose.untouched(d)) {
      root.drafts = Store.withoutId(root.drafts, d.id)
    } else {
      d.at = Date.now()
      root.drafts = Store.withDraft(root.drafts, d)
      root.say("Kept as a draft")
    }
    root.saveState()
    root.afterCompose()
  }

  function discardCompose(): void {
    if (!root.discardArmed) {
      root.discardArmed = true
      root.say("Tap again to throw this away")
      return
    }
    root.discardArmed = false
    root.drafts = Store.withoutId(root.drafts, root.compose.id)
    root.saveState()
    root.afterCompose()
  }

  function send(): void {
    var d = root.typedDraft()
    var problem = Compose.check(d)
    if (problem) { root.say(problem); return }
    if (!d.subject.trim() && !root.sendArmed) {
      root.sendArmed = true
      root.say("No subject. Tap Send again to send it anyway.")
      return
    }
    root.sendArmed = false
    var item = { id: "o" + Date.now(), draft: d, status: "sending", error: "", at: Date.now() }
    root.outbox = root.outbox.concat([item])
    root.drafts = Store.withoutId(root.drafts, d.id)
    root.saveState()
    root.afterCompose()
    root.run("send", Compose.request(d, root.sentFolder), "act", { id: item.id }, false)
  }

  function mailSent(job: var, answer: var): void {
    if (answer.ok) {
      root.outbox = Store.withoutId(root.outbox, job.context.id)
      root.say(answer.warning || "Sent")
      if (root.folder === root.sentFolder) root.refresh(false)
    } else {
      root.outbox = Store.withStatus(root.outbox, job.context.id, "failed", answer.error)
      root.say("Not sent. It is at the top of the Inbox.")
    }
    root.saveState()
  }

  function openExtra(extra: var): void {
    if (extra.kind === "draft") { root.startCompose(extra.item, "list"); return }
    if (extra.item.status === "sending") { root.say("Still sending"); return }
    var d = Compose.withFields(extra.item.draft, { error: extra.item.error })
    root.outbox = Store.withoutId(root.outbox, extra.item.id)
    root.drafts = Store.withDraft(root.drafts, d)
    root.saveState()
    root.startCompose(d, "list")
  }

  function reply(all: bool): void {
    if (!root.body || !root.account) return
    root.startCompose(Compose.reply(root.body, root.folder, root.account.email, all, Date.now()), "message")
  }

  function forward(): void {
    if (!root.body) return
    root.startCompose(Compose.forward(root.body, root.folder, Date.now()), "message")
  }

  // --- the account ------------------------------------------------------------------------

  function startSetup(edit: bool): void {
    root.closeMenus()
    root.editingAccount = edit && !!root.account
    root.setupError = ""
    root.setupNote = ""
    if (root.page === "setup" && setupPage.item) (setupPage.item as SetupForm).fill(root.editingAccount ? root.account : null)
    else root.page = "setup"
  }

  function autoconfigured(job: var, answer: var): void {
    if (!answer.ok || !setupPage.item) return
    if ((setupPage.item as SetupForm).applyServers(job.context.email, answer)) root.setupNote = answer.note || ""
  }

  function signIn(): void {
    if (!setupPage.item) return
    var form = setupPage.item as SetupForm
    var request = form.request()
    if (request.email.indexOf("@") < 1) { root.setupError = "Type your email address first."; return }
    var keeping = root.editingAccount && Address.same(root.account.email, request.email)
    if (!request.password.length && !keeping) { root.setupError = "Type your password."; return }
    if (!request.imap.host || !request.smtp.host) {
      form.showServers = true
      root.setupError = "The servers are not filled in yet. Give them a moment to be found, or type them in."
      return
    }
    root.setupError = ""
    root.signingIn = true
    root.run("setup", request, "act", {}, true)
  }

  function setUp(job: var, answer: var): void {
    root.signingIn = false
    if (!answer.ok) {
      root.setupError = answer.kind === "offline" ? "Mail is offline here." : answer.error
      return
    }
    var before = root.account ? root.account.email : ""
    root.account = Store.parseAccount(answer.account)
    root.editingAccount = false
    root.foldersLoaded = true
    root.folders = Store.parseFolders(answer)
    root.saveFolders()
    if (!root.account || root.account.email !== before) {
      root.folder = "INBOX"
      root.box = Mailbox.empty("INBOX")
      root.boxLoaded = false
      root.pending = ({})
    }
    root.page = "list"
    root.refreshFolders()
    root.peek()
  }

  function forget(): void {
    if (!root.forgetArmed) { root.forgetArmed = true; return }
    root.forgetArmed = false
    root.run("forget", {}, "act", {}, true)
  }

  function forgotten(answer: var): void {
    if (!answer.ok) { root.say(answer.error); return }
    root.account = null
    root.folders = []
    root.folder = "INBOX"
    root.box = Mailbox.empty("INBOX")
    root.boxLoaded = false
    root.pending = ({})
    root.drafts = []
    root.outbox = []
    root.inbox = { uidvalidity: 0, uidnext: 0, account: "" }
    root.startSetup(false)
  }

  // --- the harness --------------------------------------------------------------------------

  property bool harnessed: false

  function applyHarness(): void {
    if (root.harnessed) return
    root.harnessed = true
    var page = Quickshell.env("MOARCHY_MAIL_PAGE") || ""
    if (page === "folders") root.page = "folders"
    if (page === "setup") {
      root.startSetup(false)
      var typed = (Quickshell.env("MOARCHY_MAIL_TYPED") || "").split("|")
      var form = setupPage.item as SetupForm
      form.type(typed[0] || "", typed[1] || "", typed[2] || "")
      if ((typed[1] || "").indexOf("@") > 0) {
        var domain = typed[1].split("@")[1]
        root.autoconfigured({ context: { email: typed[1] } }, {
          ok: true, username: typed[1],
          imap: { host: "imap." + domain, port: 993, security: "tls" },
          smtp: { host: "smtp." + domain, port: 465, security: "tls" },
          note: Quickshell.env("MOARCHY_MAIL_NOTE") || ""
        })
      }
      root.setupError = Quickshell.env("MOARCHY_MAIL_ERROR") || ""
    }
    if (page === "compose") {
      var d = Compose.blank(Date.now())
      d.to = Quickshell.env("MOARCHY_MAIL_TO") || ""
      d.subject = Quickshell.env("MOARCHY_MAIL_SUBJECT") || ""
      d.text = Quickshell.env("MOARCHY_MAIL_TYPED") || ""
      root.startCompose(d, "list")
      if ((Quickshell.env("MOARCHY_MAIL_FOCUS") || "") === "to")
        Qt.callLater(function () { (composePage.item as ComposeForm).focusTo() })
    }
    var uid = parseInt(Quickshell.env("MOARCHY_MAIL_OPEN") || "0", 10)
    var row = uid > 0 ? Mailbox.find(root.box, uid) : null
    if (row) root.openMessage(row)
    var menu = parseInt(Quickshell.env("MOARCHY_MAIL_MENU") || "0", 10)
    if (menu > 0 && Mailbox.find(root.box, menu)) root.menuRow = Mailbox.find(root.box, menu)
  }

  function applyBodyHarness(): void {
    var reply = Quickshell.env("MOARCHY_MAIL_REPLY") || ""
    if (!reply || root.page !== "message") return
    if (reply === "forward") root.forward()
    else root.reply(reply === "all")
  }

  // --- processes and files --------------------------------------------------------------------

  // 0700: this directory holds the account, and its password in a file of its own.
  Process { id: ensureDir; running: false; command: ["mkdir", "-p", "-m", "700", root.dataDir + "/cache"] }

  // The two forms. Named, rather than written inside their Loaders, so that
  // the functions the rest of this file calls on them are checked by qmllint
  // against a type instead of guessed at on a QObject.
  component ComposeForm: Flickable {
    id: composeFlick
    clip: true
    boundsBehavior: Flickable.StopAtBounds
    contentHeight: composeColumn.implicitHeight + Metrics.GUTTER

    // Which address field has the caret, and who in Contacts
    // could be what is being typed into it.
    readonly property string addressField: toField.inputFocus ? "to"
                                           : ccField.inputFocus ? "cc"
                                           : bccField.inputFocus ? "bcc" : ""
    readonly property var suggestions: {
      if (!composeFlick.addressField) return []
      var typed = composeFlick.addressField === "to" ? toField.text
                : composeFlick.addressField === "cc" ? ccField.text : bccField.text
      return Address.matching(root.people, typed, 5)
    }

    // The form, filled from a draft. What was filled in shows
    // from its start; the caret goes where writing starts -- To
    // for a new message, above the quote for a reply.
    function load(draft: var): void {
      toField.text = draft.to
      ccField.text = draft.cc
      bccField.text = draft.bcc
      subjectField.text = draft.subject
      bodyEdit.text = draft.text
      toField.cursorPosition = 0
      ccField.cursorPosition = 0
      bccField.cursorPosition = 0
      subjectField.cursorPosition = 0
      composeFlick.contentY = 0
      Qt.callLater(function () {
        if (!draft.to.length) toField.focusInput()
        else {
          bodyEdit.cursorPosition = 0
          bodyEdit.forceActiveFocus()
        }
      })
    }

    function typed(): var {
      return Compose.withFields(root.compose, {
        to: toField.text, cc: ccField.text, bcc: bccField.text,
        subject: subjectField.text, text: bodyEdit.text, error: ""
      })
    }

    function focusTo(): void {
      toField.focusInput()
      toField.cursorPosition = toField.text.length
    }

    function pickAddress(p: var): void {
      var field = composeFlick.addressField === "cc" ? ccField
                : composeFlick.addressField === "bcc" ? bccField : toField
      field.text = Address.replaceLastToken(field.text, p)
      field.focusInput()
    }

    Component.onCompleted: composeFlick.load(root.compose)

    // Keeps the caret on screen as it moves, and as the screen moves
    // under it -- the keyboard coming up takes half of it.
    function ensureVisible(): void {
      if (!bodyEdit.activeFocus) return
      var r = bodyEdit.cursorRectangle
      var at = bodyEdit.mapToItem(composeColumn, r.x, r.y)
      var top = at.y + composeColumn.y - Metrics.PAD
      var bottom = at.y + r.height + composeColumn.y + Metrics.PAD
      if (composeFlick.contentY > top) composeFlick.contentY = Math.max(0, top)
      else if (composeFlick.contentY + composeFlick.height < bottom)
        composeFlick.contentY = bottom - composeFlick.height
    }

    onHeightChanged: Qt.callLater(composeFlick.ensureVisible)

    ColumnLayout {
      id: composeColumn
      x: Metrics.GUTTER
      y: 4
      width: composeFlick.width - Metrics.GUTTER * 2
      spacing: Metrics.GAP

      Chrome.Card {
        Layout.fillWidth: true
        visible: root.compose.error.length > 0
        colours: root.colours
        tint: root.red

        Chrome.TypedText {
          Layout.fillWidth: true
          role: "caption"
          text: "Not sent: " + root.compose.error
          color: root.ink
          bodySize: root.bodySize
        }
      }

      Chrome.Card {
        id: headerCard
        Layout.fillWidth: true
        colours: root.colours
        spacing: Metrics.GAP

        RowLayout {
          Layout.fillWidth: true
          spacing: Metrics.GAP

          FieldLabel { text: "To" }

          Chrome.TextField {
            id: toField
            Layout.fillWidth: true
            placeholderText: "Name or address"
            colours: root.colours
            foreground: root.ink
            accent: root.accent
            iconColor: root.dim
            bodySize: root.bodySize
            inputMethodHints: Qt.ImhEmailCharactersOnly | Qt.ImhNoAutoUppercase | Qt.ImhNoPredictiveText
            onAccepted: subjectField.focusInput()
          }

          Chrome.Button {
            visible: !root.showCc
            colours: root.colours
            kind: "plain"
            text: "Cc"
            pad: 10
            implicitHeight: Metrics.PILL
            bodySize: root.bodySize
            onClicked: {
              root.showCc = true
              Qt.callLater(function () { ccField.focusInput() })
            }
          }
        }

        RowLayout {
          Layout.fillWidth: true
          visible: root.showCc
          spacing: Metrics.GAP

          FieldLabel { text: "Cc" }

          Chrome.TextField {
            id: ccField
            Layout.fillWidth: true
            placeholderText: "Name or address"
            colours: root.colours
            foreground: root.ink
            accent: root.accent
            iconColor: root.dim
            bodySize: root.bodySize
            inputMethodHints: Qt.ImhEmailCharactersOnly | Qt.ImhNoAutoUppercase | Qt.ImhNoPredictiveText
          }
        }

        RowLayout {
          Layout.fillWidth: true
          visible: root.showCc
          spacing: Metrics.GAP

          FieldLabel { text: "Bcc" }

          Chrome.TextField {
            id: bccField
            Layout.fillWidth: true
            placeholderText: "Seen by nobody else"
            colours: root.colours
            foreground: root.ink
            accent: root.accent
            iconColor: root.dim
            bodySize: root.bodySize
            inputMethodHints: Qt.ImhEmailCharactersOnly | Qt.ImhNoAutoUppercase | Qt.ImhNoPredictiveText
          }
        }

        Chrome.TextField {
          id: subjectField
          Layout.fillWidth: true
          placeholderText: "Subject"
          colours: root.colours
          foreground: root.ink
          accent: root.accent
          iconColor: root.dim
          bodySize: root.bodySize
          onTextChanged: root.sendArmed = false
          onAccepted: bodyEdit.forceActiveFocus()
        }
      }

      // Names from Contacts, under whichever address field has the caret.
      Chrome.Group {
        id: suggestGroup
        Layout.fillWidth: true
        visible: composeFlick.suggestions.length > 0
        colours: root.colours

        Repeater {
          model: composeFlick.suggestions

          delegate: Chrome.ListRow {
            id: suggestRow
            required property var modelData
            Layout.fillWidth: true
            minHeight: 48
            radius: suggestGroup.innerRadius
            colours: root.colours
            bodySize: root.bodySize
            title: Address.label(suggestRow.modelData)
            subtitle: suggestRow.modelData.name ? suggestRow.modelData.email : ""
            onClicked: composeFlick.pickAddress(suggestRow.modelData)
          }
        }
      }

      Chrome.Card {
        id: textCard
        Layout.fillWidth: true
        colours: root.colours

        TextEdit {
          id: bodyEdit
          Layout.fillWidth: true
          // Down to the bottom of the screen at least, so the whole of
          // the empty box is somewhere to tap.
          Layout.minimumHeight: Math.max(160, composeFlick.height - composeColumn.y - textCard.y
                                         - Metrics.PAD * 2 - Metrics.GUTTER)
          textFormat: TextEdit.PlainText
          wrapMode: TextEdit.Wrap
          color: root.ink
          selectionColor: Theme.alpha(root.accent, 0.4)
          selectedTextColor: root.ink
          // Dragging scrolls; a drag that selected would leave a long
          // quoted reply with no way down it.
          selectByMouse: false
          font.family: Metrics.FONT
          font.pixelSize: Metrics.typeSize(root.bodySize, "body")
          onCursorRectangleChanged: composeFlick.ensureVisible()
          onTextChanged: root.sendArmed = false

          cursorDelegate: Rectangle {
            width: 2
            color: root.accent
            visible: bodyEdit.activeFocus
          }

          Chrome.Osk { id: osk }

          // A tap on the text asks for the keyboard; focus alone does
          // not (moarchy's gestures.md G14). The press goes on to the
          // TextEdit, which places the caret.
          MouseArea {
            anchors.fill: parent
            onPressed: function (mouse) {
              osk.show()
              mouse.accepted = false
            }
          }

          Chrome.TypedText {
            visible: bodyEdit.length === 0
            role: "body"
            text: "Write your message"
            color: root.dim
            bodySize: root.bodySize
          }
        }
      }

      Chrome.Section {
        id: forwardSection
        Layout.fillWidth: true
        visible: root.compose.attachments.length > 0
        colours: root.colours
        bodySize: root.bodySize
        title: "Sent with it"
        pad: Metrics.GROUP_PAD
        cardSpacing: 0
        radius: Metrics.radius(root.colours, Metrics.RADIUS_LG)

        Repeater {
          model: root.compose.attachments

          delegate: Chrome.ListRow {
            id: attachedRow
            required property var modelData
            Layout.fillWidth: true
            minHeight: 48
            interactive: false
            radius: forwardSection.innerRadius
            colours: root.colours
            bodySize: root.bodySize
            title: attachedRow.modelData

            leading: Chrome.Icon {
              slot: 28
              size: Metrics.ICON_INK
              color: root.dim
              names: [root.iconDir + "status/mail-attachment-symbolic.svg", "mail-attachment-symbolic"]
            }
          }
        }
      }
    }
  }

  component SetupForm: Flickable {
    id: setupFlick
    clip: true
    boundsBehavior: Flickable.StopAtBounds
    contentHeight: setupColumn.implicitHeight + Metrics.GUTTER * 2

    property bool showServers: false
    // True while the form is being filled in by code, so that
    // what autoconfig wrote is not taken for somebody's typing.
    property bool filling: false
    property bool serversEdited: false
    property string imapSecurity: "tls"
    property string smtpSecurity: "tls"

    function fill(a: var): void {
      setupFlick.filling = true
      setupFlick.serversEdited = !!a
      setupFlick.showServers = !!a
      nameField.text = a ? a.name : ""
      emailField.text = a ? a.email : ""
      passwordField.text = ""
      usernameField.text = a ? a.username : ""
      imapHostField.text = a ? a.imap.host : ""
      imapPortField.text = a ? String(a.imap.port) : ""
      smtpHostField.text = a ? a.smtp.host : ""
      smtpPortField.text = a ? String(a.smtp.port) : ""
      setupFlick.imapSecurity = a ? a.imap.security : "tls"
      setupFlick.smtpSecurity = a ? a.smtp.security : "tls"
      setupFlick.filling = false
    }

    function type(name: string, email: string, password: string): void {
      setupFlick.filling = true
      nameField.text = name
      emailField.text = email
      passwordField.text = password
      setupFlick.filling = false
    }

    function emailTyped(): void {
      if (setupFlick.filling || setupFlick.serversEdited) return
      autoconfigTimer.restart()
    }

    function serverTyped(): void {
      if (!setupFlick.filling) setupFlick.serversEdited = true
    }

    function lookUpServers(): void {
      var email = emailField.text.trim()
      if (!/^[^@\s]+@[^@\s]+\.[^@\s]{2,}$/.test(email) || setupFlick.serversEdited) return
      root.run("autoconfig", { email: email }, "read", { email: email }, false)
    }

    // Whether the servers were filled in: not for an address that
    // has been changed since it was asked about, and never over
    // what somebody typed.
    function applyServers(email: string, answer: var): bool {
      if (setupFlick.serversEdited || email !== emailField.text.trim()) return false
      setupFlick.filling = true
      imapHostField.text = answer.imap.host
      imapPortField.text = String(answer.imap.port)
      setupFlick.imapSecurity = answer.imap.security
      smtpHostField.text = answer.smtp.host
      smtpPortField.text = String(answer.smtp.port)
      setupFlick.smtpSecurity = answer.smtp.security
      usernameField.text = answer.username
      setupFlick.filling = false
      return true
    }

    function request(): var {
      var email = emailField.text.trim()
      return {
        name: nameField.text.trim(), email: email, password: passwordField.text,
        username: usernameField.text.trim() || email,
        imap: { host: imapHostField.text.trim(), port: parseInt(imapPortField.text, 10) || 0,
                security: setupFlick.imapSecurity },
        smtp: { host: smtpHostField.text.trim(), port: parseInt(smtpPortField.text, 10) || 0,
                security: setupFlick.smtpSecurity }
      }
    }

    Component.onCompleted: setupFlick.fill(root.editingAccount ? root.account : null)

    Timer {
      id: autoconfigTimer
      interval: 900
      onTriggered: setupFlick.lookUpServers()
    }

    ColumnLayout {
      id: setupColumn
      x: Metrics.GUTTER
      y: 4
      width: setupFlick.width - Metrics.GUTTER * 2
      spacing: Metrics.GUTTER

      Chrome.Section {
        Layout.fillWidth: true
        colours: root.colours
        bodySize: root.bodySize
        title: "Your account"

        Chrome.TextField {
          id: nameField
          Layout.fillWidth: true
          placeholderText: "Your name, as people see it"
          colours: root.colours
          foreground: root.ink
          accent: root.accent
          iconColor: root.dim
          bodySize: root.bodySize
          onAccepted: emailField.focusInput()
        }

        Chrome.TextField {
          id: emailField
          Layout.fillWidth: true
          placeholderText: "Email address"
          colours: root.colours
          foreground: root.ink
          accent: root.accent
          iconColor: root.dim
          bodySize: root.bodySize
          inputMethodHints: Qt.ImhEmailCharactersOnly | Qt.ImhNoAutoUppercase | Qt.ImhNoPredictiveText
          onTextChanged: setupFlick.emailTyped()
          onAccepted: passwordField.focusInput()
        }

        Chrome.TextField {
          id: passwordField
          Layout.fillWidth: true
          placeholderText: root.editingAccount ? "Password (leave empty to keep it)" : "Password"
          colours: root.colours
          foreground: root.ink
          accent: root.accent
          iconColor: root.dim
          bodySize: root.bodySize
          echoMode: TextInput.Password
          inputMethodHints: Qt.ImhHiddenText | Qt.ImhNoAutoUppercase | Qt.ImhNoPredictiveText | Qt.ImhSensitiveData
          onAccepted: root.signIn()
        }

        Chrome.TypedText {
          Layout.fillWidth: true
          role: "caption"
          text: "The password stays on this phone, in a file only you can read, and goes to nobody but the servers below."
          color: root.dim
          bodySize: root.bodySize
        }
      }

      Chrome.Card {
        Layout.fillWidth: true
        visible: root.setupNote.length > 0
        colours: root.colours
        tint: root.yellow

        Chrome.TypedText {
          Layout.fillWidth: true
          role: "caption"
          text: root.setupNote
          color: root.ink
          bodySize: root.bodySize
        }
      }

      Chrome.Section {
        Layout.fillWidth: true
        visible: setupFlick.showServers || imapHostField.text.length > 0
        colours: root.colours
        bodySize: root.bodySize
        title: "Servers"

        // The summary, until somebody wants to change it.
        RowLayout {
          Layout.fillWidth: true
          visible: !setupFlick.showServers
          spacing: Metrics.GAP

          ColumnLayout {
            Layout.fillWidth: true
            spacing: 2

            Chrome.TypedText {
              Layout.fillWidth: true
              role: "body"
              text: imapHostField.text
              color: root.ink
              bodySize: root.bodySize
              elide: Text.ElideMiddle
              maximumLineCount: 1
            }

            Chrome.TypedText {
              Layout.fillWidth: true
              role: "caption"
              text: "Incoming · " + imapPortField.text + " · " + Store.securityLabel(setupFlick.imapSecurity)
              color: root.dim
              bodySize: root.bodySize
            }

            Chrome.TypedText {
              Layout.fillWidth: true
              Layout.topMargin: 6
              role: "body"
              text: smtpHostField.text
              color: root.ink
              bodySize: root.bodySize
              elide: Text.ElideMiddle
              maximumLineCount: 1
            }

            Chrome.TypedText {
              Layout.fillWidth: true
              role: "caption"
              text: "Outgoing · " + smtpPortField.text + " · " + Store.securityLabel(setupFlick.smtpSecurity)
              color: root.dim
              bodySize: root.bodySize
            }
          }

          Chrome.Button {
            Layout.alignment: Qt.AlignTop
            colours: root.colours
            kind: "tonal"
            text: "Change"
            pad: 14
            bodySize: root.bodySize
            onClicked: setupFlick.showServers = true
          }
        }

        Chrome.TypedText {
          Layout.fillWidth: true
          visible: setupFlick.showServers
          role: "overline"
          text: "INCOMING (IMAP)"
          color: root.dim
          bodySize: root.bodySize
        }

        RowLayout {
          Layout.fillWidth: true
          visible: setupFlick.showServers
          spacing: Metrics.GAP

          Chrome.TextField {
            id: imapHostField
            Layout.fillWidth: true
            placeholderText: "imap.example.org"
            colours: root.colours
            foreground: root.ink
            accent: root.accent
            iconColor: root.dim
            bodySize: root.bodySize
            inputMethodHints: Qt.ImhUrlCharactersOnly | Qt.ImhNoAutoUppercase | Qt.ImhNoPredictiveText
            onTextChanged: setupFlick.serverTyped()
          }

          Chrome.TextField {
            id: imapPortField
            Layout.preferredWidth: 76
            placeholderText: "993"
            colours: root.colours
            foreground: root.ink
            accent: root.accent
            iconColor: root.dim
            bodySize: root.bodySize
            inputMethodHints: Qt.ImhDigitsOnly
            onTextChanged: setupFlick.serverTyped()
          }
        }

        Row {
          visible: setupFlick.showServers
          spacing: 6

          Repeater {
            model: ["tls", "starttls", "none"]

            delegate: Chrome.Chip {
              id: imapChip
              required property string modelData
              colours: root.colours
              bodySize: root.bodySize
              text: Store.securityLabel(imapChip.modelData)
              on: setupFlick.imapSecurity === imapChip.modelData
              onClicked: { setupFlick.imapSecurity = imapChip.modelData; setupFlick.serverTyped() }
            }
          }
        }

        Chrome.TypedText {
          Layout.fillWidth: true
          Layout.topMargin: 4
          visible: setupFlick.showServers
          role: "overline"
          text: "OUTGOING (SMTP)"
          color: root.dim
          bodySize: root.bodySize
        }

        RowLayout {
          Layout.fillWidth: true
          visible: setupFlick.showServers
          spacing: Metrics.GAP

          Chrome.TextField {
            id: smtpHostField
            Layout.fillWidth: true
            placeholderText: "smtp.example.org"
            colours: root.colours
            foreground: root.ink
            accent: root.accent
            iconColor: root.dim
            bodySize: root.bodySize
            inputMethodHints: Qt.ImhUrlCharactersOnly | Qt.ImhNoAutoUppercase | Qt.ImhNoPredictiveText
            onTextChanged: setupFlick.serverTyped()
          }

          Chrome.TextField {
            id: smtpPortField
            Layout.preferredWidth: 76
            placeholderText: "465"
            colours: root.colours
            foreground: root.ink
            accent: root.accent
            iconColor: root.dim
            bodySize: root.bodySize
            inputMethodHints: Qt.ImhDigitsOnly
            onTextChanged: setupFlick.serverTyped()
          }
        }

        Row {
          visible: setupFlick.showServers
          spacing: 6

          Repeater {
            model: ["tls", "starttls", "none"]

            delegate: Chrome.Chip {
              id: smtpChip
              required property string modelData
              colours: root.colours
              bodySize: root.bodySize
              text: Store.securityLabel(smtpChip.modelData)
              on: setupFlick.smtpSecurity === smtpChip.modelData
              onClicked: { setupFlick.smtpSecurity = smtpChip.modelData; setupFlick.serverTyped() }
            }
          }
        }

        Chrome.TextField {
          id: usernameField
          Layout.fillWidth: true
          Layout.topMargin: 4
          visible: setupFlick.showServers
          placeholderText: "User name, if it is not the address"
          colours: root.colours
          foreground: root.ink
          accent: root.accent
          iconColor: root.dim
          bodySize: root.bodySize
          inputMethodHints: Qt.ImhNoAutoUppercase | Qt.ImhNoPredictiveText
          onTextChanged: setupFlick.serverTyped()
        }
      }

      Chrome.Card {
        Layout.fillWidth: true
        visible: root.setupError.length > 0
        colours: root.colours
        tint: root.red

        Chrome.TypedText {
          Layout.fillWidth: true
          role: "body"
          text: root.setupError
          color: root.ink
          bodySize: root.bodySize
        }
      }

      Chrome.Button {
        Layout.fillWidth: true
        colours: root.colours
        kind: "filled"
        text: root.signingIn ? "Signing in…" : root.editingAccount ? "Save" : "Sign in"
        enabled: !root.signingIn
        bodySize: root.bodySize
        onClicked: root.signIn()
      }
    }
  }

  // To, Cc and Bcc, in front of their fields: filled in, three pills of
  // addresses are otherwise three pills nobody can tell apart.
  component FieldLabel: Chrome.TypedText {
    Layout.preferredWidth: 30
    role: "caption"
    color: root.dim
    bodySize: root.bodySize
  }

  component Lane: Process {
    id: lane
    property var job: null
    signal answered(var job, var answer)
    running: false
    stdinEnabled: true
    stdout: StdioCollector { id: laneOut; waitForEnd: true }
    stderr: StdioCollector { id: laneErr; waitForEnd: true }
    // The request goes in and stdin is closed, which is the end of it.
    onStarted: {
      lane.write(JSON.stringify(lane.job.input))
      lane.stdinEnabled = false
    }
    // qmllint disable signal-handler-parameters
    onExited: function (code, status) {
      var done = lane.job
      lane.job = null
      lane.answered(done, Helper.result(code, laneOut.text, laneErr.text))
    }
    // qmllint enable signal-handler-parameters
  }

  Lane {
    id: readLane
    onAnswered: function (job, answer) {
      root.finished(job, answer)
      root.pump("read")
    }
  }

  Lane {
    id: actLane
    onAnswered: function (job, answer) {
      root.finished(job, answer)
      root.pump("act")
    }
  }

  // fbcli ends its feedback on the first byte it can read from stdin, so the
  // pipe is held open and nothing is written to it.
  Process {
    id: ping
    running: false
    stdinEnabled: true
  }

  // The first look at the Inbox waits until the shell has long finished
  // starting, and after that it is one short run every fifteen minutes.
  Timer {
    interval: 90 * 1000
    running: !root.offline
    onTriggered: {
      root.peekDue = true
      root.warmUp()
      root.peekWhenReady()
    }
  }

  Timer {
    interval: root.peekMs
    repeat: true
    running: !root.offline && root.account !== null
    onTriggered: root.peek()
  }

  Timer {
    interval: 60 * 1000
    repeat: true
    running: root.showing
    onTriggered: {
      root.now = Date.now()
      root.whenReady()
    }
  }

  Chrome.JsonFile {
    id: accountFile
    path: root.warm ? root.dataDir + "/account.json" : ""

    onParsed: function (data) {
      if (!accountFile.path) return
      var before = root.account ? root.account.email : ""
      root.account = Store.parseAccount(data)
      root.accountKnown = true
      if (!root.account) {
        if (root.page !== "compose" && root.page !== "setup") root.startSetup(false)
        Qt.callLater(root.applyHarness)
        return
      }
      root.peekWhenReady()
      if (root.account.email !== before && before !== "") {
        root.box = Mailbox.empty(root.folder)
        root.boxLoaded = false
      }
      Qt.callLater(root.whenReady)
    }
  }

  Chrome.JsonFile {
    id: stateFile
    path: root.warm ? root.dataDir + "/state.json" : ""
    watchChanges: false

    onParsed: function (data) {
      if (!stateFile.path || root.stateLoaded) return
      var state = Store.parseState(data)
      root.folder = state.folder
      root.box = Mailbox.empty(state.folder)
      root.inbox = state.inbox
      root.drafts = state.drafts
      root.outbox = state.outbox
      root.stateLoaded = true
      root.peekWhenReady()
    }
  }

  Chrome.JsonFile {
    id: foldersFile
    path: root.warm && root.account ? root.dataDir + "/folders.json" : ""
    watchChanges: false

    onParsed: function (data) {
      if (!foldersFile.path || !root.account) return
      root.folders = Store.parseFolders(data, root.account.email)
      root.foldersLoaded = true
      Qt.callLater(root.whenReady)
    }
  }

  Chrome.JsonFile {
    id: boxFile
    path: root.warm && root.account && root.stateLoaded ? root.cachePath(root.folder) : ""
    watchChanges: false

    onParsed: function (data) {
      if (!boxFile.path || root.boxLoaded) return
      root.box = Mailbox.parse(data, root.folder)
      root.boxLoaded = true
      Qt.callLater(root.applyHarness)
      Qt.callLater(root.whenReady)
    }
  }

  // A message's body, as moarchy-mail cached it. Missing is the ordinary case
  // for a message not opened before, and asks the server.
  Chrome.JsonFile {
    id: bodyFile
    path: ""
    watchChanges: false

    onParsed: function (data) {
      if (!bodyFile.path || !root.openRow) return
      if (data && data.ok === true && data.uid === root.openRow.uid && data.schema === 1) {
        root.body = data
        root.bodyLoading = false
        Qt.callLater(root.applyBodyHarness)
      } else {
        root.fetchBody()
      }
    }
  }

  Chrome.JsonFile {
    id: contactsFile
    path: root.warm ? root.contactsPath : ""

    onParsed: function (data) {
      if (contactsFile.path) root.people = Address.people(data)
    }
  }

  Chrome.ThemeFile { id: themeFile }

  // The clipboard, reached the one way QML has: a TextEdit asked to copy.
  TextEdit { id: clip; visible: false }

  IpcHandler {
    target: "mail"

    function state(): string { return root.opened ? "open" : "closed" }
    function open(): string {
      if (root.shell) root.shell.summon(root.pluginId, "{}")
      else root.open("{}")
      return "ok"
    }
    function close(): string { root.dismiss(); return "ok" }
    function toggle(): string {
      if (root.shell) root.shell.toggle(root.pluginId, "{}")
      return root.opened ? "open" : "closed"
    }
    function compose(to: string): string {
      var payload = JSON.stringify({ to: to })
      if (root.shell) root.shell.summon(root.pluginId, payload)
      else root.open(payload)
      return "ok"
    }
    function check(): string {
      root.peekDue = true
      root.warmUp()
      root.peekWhenReady()
      return root.accountKnown && !root.account ? "no account" : "checking"
    }
    function refresh(): string {
      root.warmUp()
      root.refresh(false)
      return root.boxLoaded ? "refreshing " + root.folder : "not loaded yet"
    }
    // For testing on the device, where ssh has no finger to press Send with.
    // The message goes through the outbox exactly as a tapped one does.
    function send(to: string, subject: string, text: string): string {
      if (!root.account) return "no account"
      if (!root.stateLoaded) return "not loaded yet"
      var d = Compose.withFields(Compose.blank(Date.now()), { to: to, subject: subject, text: text })
      var problem = Compose.check(d)
      if (problem) return problem
      var item = { id: "o" + Date.now(), draft: d, status: "sending", error: "", at: Date.now() }
      root.outbox = root.outbox.concat([item])
      root.saveState()
      root.run("send", Compose.request(d, root.sentFolder), "act", { id: item.id }, false)
      return item.id
    }
    function outbox(): string { return JSON.stringify(root.outbox.map(function (o) { return o.status + ": " + o.error })) }
    function unread(): int { return root.unseen }
    function settled(): bool { return root.accountKnown && root.stateLoaded }
  }

  // --- the window ---------------------------------------------------------------------------

  Chrome.AppWindow {
    id: mailWindow
    shell: root.shell
    appName: "Mail"
    pluginId: root.pluginId
    color: root.background
    pageTitle: root.page === "message" && root.openRow ? root.openRow.subject
             : root.page === "compose" ? Compose.title(root.compose)
             : root.page === "folders" ? "Folders"
             : root.page === "setup" ? "Sign in" : root.folderLabel

    onMapped: {
      root.everShown = true
      root.warmUp()
      root.now = Date.now()
      Qt.callLater(root.whenReady)
    }

    Rectangle {
      anchors.fill: parent
      color: root.background
      focus: true

      Keys.onPressed: function (event) {
        if (event.key === Qt.Key_Escape) { root.back(); event.accepted = true }
      }

      ColumnLayout {
        anchors.fill: parent
        spacing: 0

        Item {
          Layout.fillWidth: true
          Layout.preferredHeight: Metrics.TARGET + 12

          Chrome.AppBar {
            anchors.fill: parent
            visible: root.page === "list"
            title: root.folderLabel
            subtitle: root.syncing ? "Checking for mail…"
                    : root.syncError ? "Not up to date"
                    : root.unseen > 0 ? root.unseen + " unread" : ""
            foreground: root.ink
            dim: root.dim
            bodySize: root.bodySize

            leading: Chrome.IconButton {
              colours: root.colours
              names: [root.iconDir + "actions/open-menu-symbolic.svg", "open-menu-symbolic"]
              color: root.ink
              tooltip: "Folders"
              onClicked: {
                root.page = "folders"
                if (root.folders.length === 0 || !root.foldersBusy) root.refreshFolders()
              }
            }

            trailing: Chrome.IconButton {
              colours: root.colours
              names: [root.iconDir + "actions/view-refresh-symbolic.svg", "view-refresh-symbolic"]
              color: root.ink
              tooltip: "Check for mail"
              spinning: root.syncing
              onClicked: root.refresh(false)
            }
          }

          Chrome.AppBar {
            anchors.fill: parent
            visible: root.page === "folders"
            title: "Folders"
            subtitle: root.account ? root.account.email : ""
            foreground: root.ink
            dim: root.dim
            bodySize: root.bodySize

            leading: Chrome.BackButton {
              colours: root.colours
              color: root.ink
              onClicked: root.back()
            }

            trailing: Chrome.IconButton {
              colours: root.colours
              names: [root.iconDir + "actions/view-refresh-symbolic.svg", "view-refresh-symbolic"]
              color: root.ink
              tooltip: "Refresh folders"
              spinning: root.foldersBusy
              onClicked: root.refreshFolders()
            }
          }

          Chrome.AppBar {
            anchors.fill: parent
            visible: root.page === "message"
            title: root.folderLabel
            foreground: root.ink
            dim: root.dim
            bodySize: root.bodySize

            leading: Chrome.BackButton {
              colours: root.colours
              color: root.ink
              onClicked: root.back()
            }

            trailing: [
              Chrome.IconButton {
                readonly property bool starred: !!root.shownRow && Mailbox.has(root.shownRow, Mailbox.FLAGGED)
                colours: root.colours
                names: starred ? [root.iconDir + "status/starred-symbolic.svg", "starred-symbolic"]
                               : [root.iconDir + "status/non-starred-symbolic.svg", "non-starred-symbolic"]
                color: starred ? root.yellow : root.ink
                tooltip: starred ? "Remove the star" : "Star"
                onClicked: root.setFlag([root.openRow.uid], "flagged", !starred)
              },
              Chrome.IconButton {
                colours: root.colours
                names: [root.iconDir + "places/user-trash-symbolic.svg", "user-trash-symbolic"]
                color: root.ink
                tooltip: "Delete"
                onClicked: {
                  if (!root.remove(root.openRow)) root.say("Tap again to delete it for good")
                }
              },
              Chrome.IconButton {
                colours: root.colours
                names: [root.iconDir + "actions/view-more-symbolic.svg", "view-more-symbolic"]
                color: root.ink
                tooltip: "More"
                onClicked: root.messageMenu = true
              }
            ]
          }

          Chrome.AppBar {
            anchors.fill: parent
            visible: root.page === "compose"
            title: Compose.title(root.compose)
            foreground: root.ink
            dim: root.dim
            bodySize: root.bodySize

            leading: Chrome.BackButton {
              colours: root.colours
              color: root.ink
              onClicked: root.back()
            }

            trailing: [
              Chrome.IconButton {
                colours: root.colours
                names: [root.iconDir + "places/user-trash-symbolic.svg", "user-trash-symbolic"]
                color: root.discardArmed ? root.red : root.ink
                tooltip: "Throw away"
                onClicked: root.discardCompose()
              },
              Chrome.Button {
                anchors.verticalCenter: parent.verticalCenter
                colours: root.colours
                kind: "filled"
                text: "Send"
                pad: 16
                implicitHeight: Metrics.PILL
                bodySize: root.bodySize
                onClicked: root.send()
              }
            ]
          }

          Chrome.AppBar {
            anchors.fill: parent
            visible: root.page === "setup"
            title: root.editingAccount ? "Account" : "Mail"
            subtitle: root.editingAccount ? "" : "Sign in"
            foreground: root.ink
            dim: root.dim
            bodySize: root.bodySize

            leading: Chrome.BackButton {
              visible: root.account !== null
              colours: root.colours
              color: root.ink
              onClicked: root.back()
            }
          }
        }

        Item {
          Layout.fillWidth: true
          Layout.fillHeight: true

          // ========== a folder ==========

          Loader {
            id: listPage
            anchors.fill: parent
            active: root.everShown && root.account !== null
            visible: root.page === "list"

            sourceComponent: Component {
              Item {

                Chrome.EmptyState {
                  anchors.left: parent.left
                  anchors.right: parent.right
                  anchors.top: parent.top
                  anchors.margins: Metrics.GUTTER
                  anchors.topMargin: 40
                  visible: root.boxLoaded && root.rows.length === 0 && root.extras.length === 0
                  colours: root.colours
                  bodySize: root.bodySize
                  names: root.syncError
                         ? [root.iconDir + "status/network-offline-symbolic.svg", "network-offline-symbolic"]
                         : [root.iconDir + "status/mail-read-symbolic.svg", "mail-read-symbolic"]
                  title: root.syncError ? "Could not check for mail"
                       : root.syncing || root.box.at === 0 ? "Checking for mail"
                       : "Nothing in " + root.folderLabel
                  detail: root.syncError || (root.syncing || root.box.at === 0 ? "" : "New messages show up here.")
                }

                Chrome.ListFrame {
                  id: listFrame
                  anchors.left: parent.left
                  anchors.right: parent.right
                  anchors.top: parent.top
                  anchors.margins: Metrics.GUTTER
                  anchors.topMargin: 4
                  // Stops short of the pencil in the corner, so it never sits on a row.
                  height: Math.min(parent.height - Metrics.GUTTER - Metrics.FAB - 16 - Metrics.GAP,
                                   mailList.contentHeight + listFrame.pad * 2)
                  visible: root.rows.length > 0 || root.extras.length > 0
                  colours: root.colours

                  ListView {
                    id: mailList
                    anchors.fill: parent
                    boundsBehavior: Flickable.StopAtBounds
                    model: root.rows

                    // Unsent, then drafts: the two things in the Inbox that are
                    // waiting on the person holding the phone rather than a server.
                    header: Column {
                      width: ListView.view ? ListView.view.width : 0

                      Repeater {
                        model: root.extras

                        delegate: Chrome.ListRow {
                          id: extraRow
                          required property var modelData
                          readonly property bool failed: extraRow.modelData.kind === "outbox"
                                                         && extraRow.modelData.item.status === "failed"
                          width: parent ? parent.width : 0
                          minHeight: 60
                          radius: listFrame.innerRadius
                          colours: root.colours
                          bodySize: root.bodySize
                          tint: extraRow.failed ? root.red : "transparent"
                          title: Compose.summary(extraRow.modelData.kind === "outbox"
                                                 ? extraRow.modelData.item.draft : extraRow.modelData.item)
                          subtitle: extraRow.modelData.kind === "draft" ? "Draft"
                                  : extraRow.failed ? "Not sent · " + extraRow.modelData.item.error
                                  : "Sending…"
                          subtitleColour: extraRow.failed ? root.red : root.dim
                          onClicked: root.openExtra(extraRow.modelData)
                          onHeld: { root.armed = false; root.menuExtra = extraRow.modelData }

                          leading: Item {
                            width: 40
                            height: 40

                            Chrome.Icon {
                              anchors.centerIn: parent
                              slot: 24
                              size: Metrics.ICON_INK
                              color: extraRow.failed ? root.red : root.dim
                              names: extraRow.modelData.kind === "draft"
                                     ? [root.iconDir + "actions/document-edit-symbolic.svg", "document-edit-symbolic"]
                                     : [root.iconDir + "actions/mail-send-symbolic.svg", "mail-send-symbolic"]
                            }
                          }
                        }
                      }
                    }

                    delegate: Chrome.ListRow {
                      id: mailRow
                      required property var modelData
                      readonly property var row: mailRow.modelData
                      readonly property bool unread: !Mailbox.has(mailRow.row, Mailbox.SEEN)
                      readonly property bool outgoing: root.folderRole === "sent" || root.folderRole === "drafts"
                      readonly property var person: mailRow.outgoing ? (mailRow.row.to[0] || null) : mailRow.row.from
                      readonly property string who: mailRow.outgoing
                                                    ? "To " + (Address.label(mailRow.person) || "nobody")
                                                    : (Address.label(mailRow.person) || "Unknown sender")

                      width: ListView.view.width
                      minHeight: 78
                      radius: listFrame.innerRadius
                      colours: root.colours
                      bodySize: root.bodySize
                      onClicked: root.openMessage(mailRow.row)
                      onHeld: { root.armed = false; root.menuRow = mailRow.row }

                      leading: Rectangle {
                        width: 40
                        height: 40
                        radius: Metrics.round(root.colours, 40)
                        color: mailRow.unread ? Theme.tint(root.colours, root.accent, "raised")
                                              : Theme.surface(root.colours, "raised")

                        Chrome.TypedText {
                          anchors.centerIn: parent
                          role: "subtitle"
                          text: Address.initial(mailRow.person)
                          color: root.ink
                          bodySize: root.bodySize
                        }
                      }

                      centre: ColumnLayout {
                        anchors.left: parent.left
                        anchors.right: parent.right
                        spacing: 1

                        RowLayout {
                          Layout.fillWidth: true
                          spacing: 4

                          Chrome.TypedText {
                            Layout.fillWidth: true
                            role: "body"
                            text: mailRow.who
                            color: root.ink
                            font.weight: mailRow.unread ? Font.DemiBold : Font.Normal
                            bodySize: root.bodySize
                            elide: Text.ElideRight
                            maximumLineCount: 1
                          }

                          Chrome.Icon {
                            visible: Mailbox.has(mailRow.row, Mailbox.FLAGGED)
                            slot: 16
                            size: 14
                            color: root.yellow
                            names: [root.iconDir + "status/starred-symbolic.svg", "starred-symbolic"]
                          }

                          Chrome.Icon {
                            visible: mailRow.row.attachment
                            slot: 16
                            size: 14
                            color: root.dim
                            names: [root.iconDir + "status/mail-attachment-symbolic.svg", "mail-attachment-symbolic"]
                          }

                          Chrome.TypedText {
                            role: "caption"
                            text: Mailbox.when(mailRow.row.at, root.now)
                            color: mailRow.unread ? root.accent : root.dim
                            bodySize: root.bodySize
                          }
                        }

                        Chrome.TypedText {
                          Layout.fillWidth: true
                          role: "caption"
                          text: mailRow.row.subject || "No subject"
                          color: root.ink
                          font.weight: mailRow.unread ? Font.DemiBold : Font.Normal
                          bodySize: root.bodySize
                          elide: Text.ElideRight
                          maximumLineCount: 1
                        }

                        Chrome.TypedText {
                          Layout.fillWidth: true
                          visible: mailRow.row.preview.length > 0
                          role: "caption"
                          text: mailRow.row.preview
                          color: root.dim
                          bodySize: root.bodySize
                          elide: Text.ElideRight
                          maximumLineCount: 1
                        }
                      }
                    }

                    footer: Item {
                      width: ListView.view ? ListView.view.width : 0
                      height: root.box.more ? Metrics.TARGET + 12 : 0
                      visible: root.box.more

                      Chrome.Button {
                        anchors.centerIn: parent
                        colours: root.colours
                        kind: "plain"
                        text: root.loadingOlder ? "Fetching older messages…" : "Older messages"
                        enabled: !root.loadingOlder
                        bodySize: root.bodySize
                        onClicked: root.refresh(true)
                      }
                    }
                  }
                }
              }
            }
          }

          // ========== folders ==========

          Loader {
            id: foldersPage
            anchors.fill: parent
            active: root.page === "folders"

            sourceComponent: Component {
              Flickable {
                id: foldersFlick
                clip: true
                boundsBehavior: Flickable.StopAtBounds
                contentHeight: foldersColumn.implicitHeight + Metrics.GUTTER * 2

                ColumnLayout {
                  id: foldersColumn
                  x: Metrics.GUTTER
                  y: 4
                  width: foldersFlick.width - Metrics.GUTTER * 2
                  spacing: Metrics.GUTTER

                  Chrome.EmptyState {
                    Layout.fillWidth: true
                    visible: root.folders.length === 0
                    colours: root.colours
                    bodySize: root.bodySize
                    names: [root.iconDir + "places/folder-symbolic.svg", "folder-symbolic"]
                    title: root.foldersBusy ? "Asking for the folders" : "No folders yet"
                    detail: root.foldersBusy ? "" : "Tap refresh to ask the server again."
                  }

                  Chrome.Group {
                    id: folderGroup
                    Layout.fillWidth: true
                    visible: root.folders.length > 0
                    colours: root.colours

                    Repeater {
                      model: root.showing && root.page === "folders" ? root.folders : []

                      delegate: Chrome.ListRow {
                        id: folderRow
                        required property var modelData
                        Layout.fillWidth: true
                        minHeight: 52
                        radius: folderGroup.innerRadius
                        colours: root.colours
                        bodySize: root.bodySize
                        selected: folderRow.modelData.name === root.folder
                        title: folderRow.modelData.label
                        subtitle: folderRow.modelData.parent
                        titleWeight: folderRow.modelData.unseen > 0 ? Font.DemiBold : Font.Normal
                        onClicked: root.openFolder(folderRow.modelData.name)

                        leading: Item {
                          width: 32
                          height: 32

                          Chrome.Icon {
                            anchors.centerIn: parent
                            slot: 28
                            size: Metrics.ICON_INK
                            color: folderRow.selected ? root.accent : root.dim
                            names: [Store.icon(folderRow.modelData.role)]
                          }
                        }

                        // Unread in Junk and Trash is not waiting for anybody, so
                        // it is counted without the accent.
                        trailing: Rectangle {
                          id: badge
                          readonly property bool quiet: folderRow.modelData.role === "junk"
                                                        || folderRow.modelData.role === "trash"
                          visible: folderRow.modelData.unseen > 0
                          width: Math.max(22, count.implicitWidth + 12)
                          height: 22
                          radius: 11
                          color: badge.quiet ? Theme.surface(root.colours, "raised") : root.accent

                          Text {
                            id: count
                            anchors.centerIn: parent
                            text: String(folderRow.modelData.unseen)
                            color: badge.quiet ? root.ink : Theme.inkOn(root.colours, root.accent)
                            font.family: Metrics.FONT
                            font.weight: Font.DemiBold
                            font.pixelSize: Metrics.typeSize(root.bodySize, "overline")
                          }
                        }
                      }
                    }
                  }

                  Chrome.Section {
                    Layout.fillWidth: true
                    visible: root.account !== null
                    colours: root.colours
                    bodySize: root.bodySize
                    title: "Account"

                    Chrome.TypedText {
                      Layout.fillWidth: true
                      role: "body"
                      text: root.account ? (root.account.name || root.account.email) : ""
                      color: root.ink
                      bodySize: root.bodySize
                      elide: Text.ElideRight
                      maximumLineCount: 1
                    }

                    Chrome.TypedText {
                      Layout.fillWidth: true
                      Layout.topMargin: -6
                      visible: !!root.account && root.account.name.length > 0
                      role: "caption"
                      text: root.account ? root.account.email : ""
                      color: root.dim
                      bodySize: root.bodySize
                      elide: Text.ElideRight
                      maximumLineCount: 1
                    }

                    RowLayout {
                      Layout.fillWidth: true
                      spacing: Metrics.GAP

                      Chrome.Button {
                        Layout.fillWidth: true
                        colours: root.colours
                        kind: "tonal"
                        text: "Settings"
                        bodySize: root.bodySize
                        onClicked: root.startSetup(true)
                      }

                      Chrome.Button {
                        Layout.fillWidth: true
                        colours: root.colours
                        kind: "tonal"
                        destructive: true
                        text: root.forgetArmed ? "Tap to confirm" : "Sign out"
                        bodySize: root.bodySize
                        onClicked: root.forget()
                      }
                    }

                    Chrome.TypedText {
                      Layout.fillWidth: true
                      visible: root.forgetArmed
                      role: "caption"
                      text: "Signing out removes the account, its password and every message kept on this phone. The mail on the server is not touched."
                      color: root.dim
                      bodySize: root.bodySize
                      wrapMode: Text.WordWrap
                    }
                  }
                }
              }
            }
          }

          // ========== a message ==========

          Loader {
            id: messagePage
            anchors.fill: parent
            active: root.page === "message" && root.openRow !== null

            sourceComponent: Component {
              Item {

                Flickable {
                  id: messageFlick
                  anchors.left: parent.left
                  anchors.right: parent.right
                  anchors.top: parent.top
                  anchors.bottom: replyBar.top
                  clip: true
                  boundsBehavior: Flickable.StopAtBounds
                  contentHeight: messageColumn.implicitHeight + Metrics.GUTTER

                  ColumnLayout {
                    id: messageColumn
                    x: Metrics.GUTTER
                    y: 4
                    width: messageFlick.width - Metrics.GUTTER * 2
                    spacing: Metrics.GAP

                    Chrome.Section {
                      Layout.fillWidth: true
                      colours: root.colours
                      bodySize: root.bodySize
                      role: "subtitle"
                      title: root.shownRow ? (root.body ? root.body.subject : root.shownRow.subject) || "No subject" : ""

                      RowLayout {
                        Layout.fillWidth: true
                        spacing: 10

                        Rectangle {
                          Layout.preferredWidth: 40
                          Layout.preferredHeight: 40
                          Layout.alignment: Qt.AlignTop
                          radius: Metrics.round(root.colours, 40)
                          color: Theme.surface(root.colours, "raised")

                          Chrome.TypedText {
                            anchors.centerIn: parent
                            role: "subtitle"
                            text: root.shownRow ? Address.initial(root.shownRow.from) : ""
                            color: root.ink
                            bodySize: root.bodySize
                          }
                        }

                        ColumnLayout {
                          Layout.fillWidth: true
                          spacing: 0

                          Chrome.TypedText {
                            Layout.fillWidth: true
                            role: "body"
                            text: root.shownRow ? (Address.label(root.shownRow.from) || "Unknown sender") : ""
                            color: root.ink
                            font.weight: Font.DemiBold
                            bodySize: root.bodySize
                            elide: Text.ElideRight
                            maximumLineCount: 1
                          }

                          Chrome.TypedText {
                            Layout.fillWidth: true
                            visible: !!root.shownRow && root.shownRow.from.name.length > 0
                            role: "caption"
                            text: root.shownRow ? root.shownRow.from.email : ""
                            color: root.dim
                            bodySize: root.bodySize
                            elide: Text.ElideRight
                            maximumLineCount: 1
                          }
                        }

                        Chrome.TypedText {
                          Layout.alignment: Qt.AlignTop
                          role: "caption"
                          text: root.shownRow ? Mailbox.stamp(root.shownRow.date || root.shownRow.at, root.now) : ""
                          color: root.dim
                          bodySize: root.bodySize
                        }
                      }

                      Chrome.TypedText {
                        Layout.fillWidth: true
                        visible: text.length > 0
                        role: "caption"
                        text: {
                          if (!root.body) return ""
                          var to = root.body.to.map(Address.label).join(", ")
                          var cc = root.body.cc.map(Address.label).join(", ")
                          var out = to ? "To " + to : ""
                          if (cc) out += (out ? "\nCc " : "Cc ") + cc
                          return out
                        }
                        color: root.dim
                        bodySize: root.bodySize
                        maximumLineCount: 4
                        elide: Text.ElideRight
                      }

                      // The attachments are under the text, which on a long
                      // message is a long way down. This says they are there and
                      // goes to them.
                      Item {
                        Layout.fillWidth: true
                        visible: !!root.body && root.body.attachments.length > 0
                        implicitHeight: filesLine.implicitHeight

                        RowLayout {
                          id: filesLine
                          anchors.left: parent.left
                          anchors.right: parent.right
                          spacing: 4

                          Chrome.Icon {
                            slot: 18
                            size: 14
                            color: root.accent
                            names: [root.iconDir + "status/mail-attachment-symbolic.svg", "mail-attachment-symbolic"]
                          }

                          Chrome.TypedText {
                            Layout.fillWidth: true
                            role: "caption"
                            text: {
                              if (!root.body) return ""
                              var files = root.body.attachments
                              var total = 0
                              for (var i = 0; i < files.length; i++) total += files[i].size
                              return (files.length === 1 ? files[0].name : files.length + " attachments")
                                     + " · " + Mailbox.size(total)
                            }
                            color: root.accent
                            bodySize: root.bodySize
                            elide: Text.ElideMiddle
                            maximumLineCount: 1
                          }
                        }

                        MouseArea {
                          anchors.fill: parent
                          anchors.margins: -8
                          onClicked: messageFlick.contentY = Math.max(0, Math.min(
                            messageFlick.contentHeight - messageFlick.height, filesSection.y + messageColumn.y))
                        }
                      }
                    }

                    Chrome.Card {
                      Layout.fillWidth: true
                      colours: root.colours

                      Text {
                        Layout.fillWidth: true
                        visible: root.body !== null
                        // StyledText, and every tag in it moarchy-mail's own: links
                        // are "#n" into body.links, and nothing loads a picture.
                        textFormat: Text.StyledText
                        wrapMode: Text.WrapAtWordBoundaryOrAnywhere
                        text: root.bodyMarkup
                        color: root.ink
                        linkColor: root.accent
                        font.family: Metrics.FONT
                        font.pixelSize: Metrics.typeSize(root.bodySize, "body")
                        lineHeight: 1.1
                        onLinkActivated: function (link) { root.followLink(link) }
                      }

                      Chrome.TypedText {
                        Layout.fillWidth: true
                        visible: root.body !== null && !root.bodyMarkup.length
                        role: "body"
                        text: "This message has no text in it."
                        color: root.dim
                        bodySize: root.bodySize
                      }

                      Chrome.TypedText {
                        Layout.fillWidth: true
                        visible: root.body === null && root.bodyLoading
                        role: "body"
                        text: root.shownRow && root.shownRow.preview ? root.shownRow.preview + "…" : "Downloading…"
                        color: root.dim
                        bodySize: root.bodySize
                      }

                      Chrome.TypedText {
                        Layout.fillWidth: true
                        visible: root.body === null && !root.bodyLoading && root.bodyError.length > 0
                        role: "body"
                        text: root.bodyError
                        color: root.ink
                        bodySize: root.bodySize
                      }

                      Chrome.Button {
                        visible: root.body === null && !root.bodyLoading && root.bodyError.length > 0 && !root.offline
                        colours: root.colours
                        kind: "tonal"
                        text: "Try again"
                        bodySize: root.bodySize
                        onClicked: root.fetchBody()
                      }

                      Chrome.TypedText {
                        Layout.fillWidth: true
                        visible: !!root.body && (root.body.pictures > 0 || root.body.truncated)
                        role: "caption"
                        text: !root.body ? ""
                            : root.body.truncated ? "The rest of this message is too long to show here."
                            : root.body.pictures === 1 ? "1 picture is not shown."
                            : root.body.pictures + " pictures are not shown."
                        color: root.dim
                        bodySize: root.bodySize
                      }
                    }

                    Chrome.Section {
                      id: filesSection
                      Layout.fillWidth: true
                      visible: !!root.body && root.body.attachments.length > 0
                      colours: root.colours
                      bodySize: root.bodySize
                      title: "Attachments"
                      pad: Metrics.GROUP_PAD
                      cardSpacing: 0
                      radius: Metrics.radius(root.colours, Metrics.RADIUS_LG)

                      Repeater {
                        model: root.body ? root.body.attachments : []

                        delegate: Chrome.ListRow {
                          id: fileRow
                          required property var modelData
                          Layout.fillWidth: true
                          radius: filesSection.innerRadius
                          colours: root.colours
                          bodySize: root.bodySize
                          title: fileRow.modelData.name
                          subtitle: Mailbox.size(fileRow.modelData.size)
                          onClicked: root.saveAttachment(fileRow.modelData)

                          leading: Item {
                            width: 32
                            height: 32

                            Chrome.Icon {
                              anchors.centerIn: parent
                              slot: 28
                              size: Metrics.ICON_INK
                              color: root.dim
                              names: [root.iconDir + "status/mail-attachment-symbolic.svg", "mail-attachment-symbolic"]
                            }
                          }

                          trailing: Chrome.Icon {
                            slot: 28
                            size: Metrics.ICON_INK
                            color: root.ink
                            names: [root.iconDir + "places/folder-download-symbolic.svg", "folder-download-symbolic"]
                          }
                        }
                      }
                    }
                  }
                }

                RowLayout {
                  id: replyBar
                  anchors.left: parent.left
                  anchors.right: parent.right
                  anchors.bottom: parent.bottom
                  anchors.leftMargin: Metrics.GUTTER
                  anchors.rightMargin: Metrics.GUTTER
                  anchors.bottomMargin: Metrics.GAP
                  height: root.body ? implicitHeight : 0
                  visible: root.body !== null
                  spacing: Metrics.GAP

                  Chrome.Button {
                    Layout.fillWidth: true
                    colours: root.colours
                    kind: "filled"
                    text: "Reply"
                    pad: 12
                    bodySize: root.bodySize
                    onClicked: root.reply(false)
                  }

                  Chrome.Button {
                    Layout.fillWidth: true
                    visible: root.canReplyAll
                    colours: root.colours
                    kind: "tonal"
                    text: "Reply all"
                    pad: 12
                    bodySize: root.bodySize
                    onClicked: root.reply(true)
                  }

                  Chrome.Button {
                    Layout.fillWidth: true
                    colours: root.colours
                    kind: "tonal"
                    text: "Forward"
                    pad: 12
                    bodySize: root.bodySize
                    onClicked: root.forward()
                  }
                }
              }
            }
          }

          // ========== writing ==========

          Loader {
            id: composePage
            anchors.fill: parent
            active: root.page === "compose"

            sourceComponent: Component {
              ComposeForm {}
            }
          }

          // ========== signing in ==========

          Loader {
            id: setupPage
            anchors.fill: parent
            active: root.page === "setup"

            sourceComponent: Component {
              SetupForm {}
            }
          }

        }

        Item {
          Layout.fillWidth: true
          Layout.preferredHeight: root.shellFurniture
        }
      }

      Chrome.Fab {
        colours: root.colours
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.rightMargin: 16
        anchors.bottomMargin: 16 + root.shellFurniture
        visible: root.page === "list" && root.account !== null
        accent: root.accent
        foreground: Theme.inkOn(root.colours, root.accent)
        names: [root.iconDir + "actions/mail-message-new-symbolic.svg", "list-add-symbolic"]
        tooltip: "Write a message"
        onClicked: root.startCompose(Compose.blank(Date.now()), "list")
      }

      // A message in the list, held.
      Loader {
        anchors.fill: parent
        z: 100
        active: root.menuRow !== null

        sourceComponent: Component {
          Chrome.ContextMenu {
            open: true
            placement: "center"
            colours: root.colours
            background: root.background
            foreground: root.ink
            danger: root.red
            bodySize: root.bodySize
            onDismissed: root.closeMenus()

            Chrome.MenuItem {
              readonly property bool unread: !!root.menuShown && !Mailbox.has(root.menuShown, Mailbox.SEEN)
              colours: root.colours
              names: unread ? [root.iconDir + "status/mail-read-symbolic.svg"] : [root.iconDir + "status/mail-unread-symbolic.svg"]
              text: unread ? "Mark as read" : "Mark as unread"
              foreground: root.ink
              bodySize: root.bodySize
              onClicked: {
                var row = root.menuRow
                root.closeMenus()
                root.setFlag([row.uid], "seen", unread)
              }
            }

            Chrome.MenuItem {
              readonly property bool starred: !!root.menuShown && Mailbox.has(root.menuShown, Mailbox.FLAGGED)
              colours: root.colours
              names: [root.iconDir + (starred ? "status/non-starred-symbolic.svg" : "status/starred-symbolic.svg")]
              text: starred ? "Remove the star" : "Star"
              foreground: root.ink
              bodySize: root.bodySize
              onClicked: {
                var row = root.menuRow
                root.closeMenus()
                root.setFlag([row.uid], "flagged", !starred)
              }
            }

            Chrome.MenuItem {
              visible: root.archiveFolder !== "" && root.folder !== root.archiveFolder
              colours: root.colours
              names: [root.iconDir + "places/folder-documents-symbolic.svg"]
              text: "Archive"
              foreground: root.ink
              bodySize: root.bodySize
              onClicked: {
                var row = root.menuRow
                root.closeMenus()
                root.moveTo([row.uid], root.archiveFolder, "Archived")
              }
            }

            Chrome.MenuItem {
              visible: root.junkFolder !== ""
              colours: root.colours
              names: [root.iconDir + "actions/mail-mark-junk-symbolic.svg"]
              text: root.folder === root.junkFolder ? "Not junk" : "Junk"
              foreground: root.ink
              bodySize: root.bodySize
              onClicked: {
                var row = root.menuRow
                var target = root.folder === root.junkFolder ? "INBOX" : root.junkFolder
                root.closeMenus()
                root.moveTo([row.uid], target, root.folder === root.junkFolder ? "Moved to the Inbox" : "Moved to Junk")
              }
            }

            Chrome.MenuItem {
              colours: root.colours
              names: [root.iconDir + "places/user-trash-symbolic.svg"]
              text: root.armed ? "Tap again to delete for good"
                  : root.trashFolder && root.folder !== root.trashFolder ? "Delete" : "Delete for good"
              destructive: true
              danger: root.red
              foreground: root.ink
              bodySize: root.bodySize
              onClicked: {
                var row = root.menuRow
                if (root.remove(row)) root.closeMenus()
              }
            }
          }
        }
      }

      // A draft or an unsent message, held.
      Loader {
        anchors.fill: parent
        z: 100
        active: root.menuExtra !== null

        sourceComponent: Component {
          Chrome.ContextMenu {
            open: true
            placement: "center"
            colours: root.colours
            background: root.background
            foreground: root.ink
            danger: root.red
            bodySize: root.bodySize
            onDismissed: root.closeMenus()

            Chrome.MenuItem {
              colours: root.colours
              names: [root.iconDir + "actions/document-edit-symbolic.svg"]
              text: "Open"
              foreground: root.ink
              bodySize: root.bodySize
              onClicked: {
                var extra = root.menuExtra
                root.closeMenus()
                root.openExtra(extra)
              }
            }

            Chrome.MenuItem {
              colours: root.colours
              names: [root.iconDir + "places/user-trash-symbolic.svg"]
              text: root.armed ? "Tap again to throw it away" : "Throw away"
              destructive: true
              danger: root.red
              foreground: root.ink
              bodySize: root.bodySize
              onClicked: {
                if (!root.armed) { root.armed = true; return }
                var extra = root.menuExtra
                root.closeMenus()
                if (extra.kind === "draft") root.drafts = Store.withoutId(root.drafts, extra.item.id)
                else root.outbox = Store.withoutId(root.outbox, extra.item.id)
                root.saveState()
              }
            }
          }
        }
      }

      // The message's own menu.
      Loader {
        anchors.fill: parent
        z: 100
        active: root.messageMenu

        sourceComponent: Component {
          Chrome.ContextMenu {
            open: true
            colours: root.colours
            background: root.background
            foreground: root.ink
            danger: root.red
            bodySize: root.bodySize
            onDismissed: root.closeMenus()

            Chrome.MenuItem {
              colours: root.colours
              names: [root.iconDir + "status/mail-unread-symbolic.svg"]
              text: "Mark as unread"
              foreground: root.ink
              bodySize: root.bodySize
              onClicked: {
                var row = root.openRow
                root.closeMenus()
                root.setFlag([row.uid], "seen", false)
                root.closeMessage()
              }
            }

            Chrome.MenuItem {
              visible: root.archiveFolder !== "" && root.folder !== root.archiveFolder
              colours: root.colours
              names: [root.iconDir + "places/folder-documents-symbolic.svg"]
              text: "Archive"
              foreground: root.ink
              bodySize: root.bodySize
              onClicked: {
                var row = root.openRow
                root.closeMenus()
                root.moveTo([row.uid], root.archiveFolder, "Archived")
              }
            }

            Chrome.MenuItem {
              visible: root.junkFolder !== "" && root.folder !== root.junkFolder
              colours: root.colours
              names: [root.iconDir + "actions/mail-mark-junk-symbolic.svg"]
              text: "Junk"
              foreground: root.ink
              bodySize: root.bodySize
              onClicked: {
                var row = root.openRow
                root.closeMenus()
                root.moveTo([row.uid], root.junkFolder, "Moved to Junk")
              }
            }

            Chrome.MenuItem {
              visible: root.body !== null
              colours: root.colours
              names: [root.iconDir + "actions/edit-copy-symbolic.svg"]
              text: "Copy the text"
              foreground: root.ink
              bodySize: root.bodySize
              onClicked: {
                root.closeMenus()
                root.copyText(root.body.text, "Copied")
              }
            }
          }
        }
      }

      // A link, before it is opened. The words of a link and where it goes
      // are two different things in mail, and this is where they are shown
      // side by side.
      Loader {
        anchors.fill: parent
        z: 100
        active: root.linkHref.length > 0

        sourceComponent: Component {
          Chrome.ContextMenu {
            open: true
            placement: "center"
            menuWidth: Math.min(320, parent.width - 32)
            colours: root.colours
            background: root.background
            foreground: root.ink
            danger: root.red
            bodySize: root.bodySize
            onDismissed: root.closeMenus()

            Chrome.TypedText {
              width: parent.width
              leftPadding: 8
              rightPadding: 8
              topPadding: 4
              bottomPadding: 6
              role: "caption"
              text: root.linkHref
              color: root.dim
              bodySize: root.bodySize
              wrapMode: Text.WrapAnywhere
              maximumLineCount: 4
              elide: Text.ElideRight
            }

            Chrome.MenuItem {
              colours: root.colours
              names: [root.iconDir + "actions/send-to-symbolic.svg"]
              text: "Open link"
              foreground: root.ink
              bodySize: root.bodySize
              onClicked: {
                var href = root.linkHref
                root.closeMenus()
                Quickshell.execDetached(["xdg-open", href])
              }
            }

            Chrome.MenuItem {
              colours: root.colours
              names: [root.iconDir + "actions/edit-copy-symbolic.svg"]
              text: "Copy link"
              foreground: root.ink
              bodySize: root.bodySize
              onClicked: {
                var href = root.linkHref
                root.closeMenus()
                root.copyText(href, "Link copied")
              }
            }
          }
        }
      }

      Chrome.Toast {
        id: toast
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        anchors.bottomMargin: 72 + root.shellFurniture
        z: 60
        colours: root.colours
        bodySize: root.bodySize
      }
    }
  }
}
