// The files the app keeps, other than a folder's rows (Mailbox.js has those).
//
//   account.json   moarchy-mail's, read here and never written. No password
//                  in it: that is a file of its own the app never opens.
//   folders.json   the folder list, with the counts from the last time each
//                  was looked at, so the folder page draws before the server
//                  has answered.
//   state.json     the folder last open, where new mail in the Inbox starts
//                  (for notifications), the drafts, and the outbox.
//
// Rows this app cannot read are dropped rather than kept, unlike Contacts:
// everything here is either the server's, and comes back on the next refresh,
// or a draft, and a draft this cannot read is not one it can show.
.pragma library
.import "Compose.js" as Compose

var SCHEMA = 1
var DRAFTS = 20

function str(v) {
  return typeof v === "string" ? v : ""
}

function num(v) {
  var n = Number(v)
  return isFinite(n) ? n : 0
}

// --- account.json ---------------------------------------------------------------

function parseServer(s) {
  if (!s || typeof s !== "object" || !str(s.host)) return null
  var port = Math.floor(num(s.port))
  if (!(port > 0 && port < 65536)) return null
  var security = ["tls", "starttls", "none"].indexOf(s.security) >= 0 ? s.security : "tls"
  return { host: s.host, port: port, security: security }
}

function parseAccount(data) {
  if (!data || typeof data !== "object") return null
  var email = str(data.email)
  var imap = parseServer(data.imap)
  var smtp = parseServer(data.smtp)
  if (email.indexOf("@") < 1 || !imap || !smtp) return null
  return {
    name: str(data.name),
    email: email,
    username: str(data.username) || email,
    imap: imap,
    smtp: smtp
  }
}

function securityLabel(security) {
  return security === "starttls" ? "STARTTLS" : security === "none" ? "No encryption" : "TLS"
}

// --- folders.json ----------------------------------------------------------------

var ROLES = ["inbox", "drafts", "sent", "archive", "flagged", "all", "junk", "trash"]

// `email` is the account the file must be for: folders.json written for
// another account is somebody else's list.
function parseFolders(data, email) {
  var out = []
  if (email && data && typeof data.account === "string" && data.account !== email) return out
  var rows = data && data.folders && data.folders.constructor === Array ? data.folders : []
  var seen = {}
  for (var i = 0; i < rows.length; i++) {
    var f = rows[i]
    if (!f || typeof f !== "object" || !str(f.name) || seen[f.name]) continue
    seen[f.name] = true
    out.push({
      name: f.name,
      label: str(f.label) || f.name,
      parent: str(f.parent),
      role: ROLES.indexOf(f.role) >= 0 ? f.role : "",
      unseen: Math.max(0, Math.floor(num(f.unseen))),
      total: Math.max(0, Math.floor(num(f.total)))
    })
  }
  return out
}

function serializeFolders(folders, email) {
  return JSON.stringify({ schema: SCHEMA, account: str(email), folders: folders }, null, 1)
}

function find(folders, name) {
  for (var i = 0; i < (folders || []).length; i++)
    if (folders[i].name === name) return folders[i]
  return null
}

function label(folders, name) {
  if (name === "INBOX") return "Inbox"
  var f = find(folders, name)
  return f ? f.label : String(name || "")
}

function byRole(folders, role) {
  for (var i = 0; i < (folders || []).length; i++)
    if (folders[i].role === role) return folders[i].name
  return ""
}

function withCounts(folders, name, unseen, total) {
  return (folders || []).map(function (f) {
    if (f.name !== name) return f
    var copy = {}
    for (var k in f) copy[k] = f[k]
    copy.unseen = Math.max(0, Math.floor(num(unseen)))
    copy.total = Math.max(0, Math.floor(num(total)))
    return copy
  })
}

var ICON = "/usr/share/icons/Adwaita/symbolic/"

function icon(role) {
  if (role === "inbox") return ICON + "status/mail-unread-symbolic.svg"
  if (role === "sent") return ICON + "actions/mail-send-symbolic.svg"
  if (role === "drafts") return ICON + "actions/document-edit-symbolic.svg"
  if (role === "trash") return ICON + "places/user-trash-symbolic.svg"
  if (role === "junk") return ICON + "actions/mail-mark-junk-symbolic.svg"
  if (role === "flagged") return ICON + "status/starred-symbolic.svg"
  if (role === "archive" || role === "all") return ICON + "places/folder-documents-symbolic.svg"
  return ICON + "places/folder-symbolic.svg"
}

// --- state.json -------------------------------------------------------------------

function emptyState() {
  return { folder: "INBOX", inbox: { uidvalidity: 0, uidnext: 0, account: "" }, drafts: [], outbox: [] }
}

function parseOutboxItem(o) {
  if (!o || typeof o !== "object" || !str(o.id)) return null
  var draft = Compose.normalise(o.draft)
  if (!draft) return null
  var status = o.status === "failed" ? "failed" : "sending"
  var error = str(o.error)
  // "sending" in a file means the process that was sending it is not running
  // any more, and whether the message went is not known. Said so, rather than
  // sent again on its own: a message sent twice cannot be taken back.
  if (status === "sending") {
    status = "failed"
    error = "Mail stopped while this was being sent, so it may have gone. Check Sent before sending it again."
  }
  return { id: o.id, draft: draft, status: status, error: error, at: num(o.at) }
}

function parseState(data) {
  var state = emptyState()
  if (!data || typeof data !== "object") return state
  if (str(data.folder)) state.folder = data.folder
  if (data.inbox && typeof data.inbox === "object")
    state.inbox = {
      uidvalidity: num(data.inbox.uidvalidity),
      uidnext: num(data.inbox.uidnext),
      account: str(data.inbox.account)
    }
  var drafts = data.drafts && data.drafts.constructor === Array ? data.drafts : []
  for (var i = 0; i < drafts.length && state.drafts.length < DRAFTS; i++) {
    var d = Compose.normalise(drafts[i])
    if (d) state.drafts.push(d)
  }
  var outbox = data.outbox && data.outbox.constructor === Array ? data.outbox : []
  for (var j = 0; j < outbox.length; j++) {
    var o = parseOutboxItem(outbox[j])
    if (o) state.outbox.push(o)
  }
  return state
}

function serializeState(state) {
  return JSON.stringify({
    schema: SCHEMA,
    folder: state.folder,
    inbox: state.inbox,
    drafts: state.drafts,
    outbox: state.outbox
  }, null, 1)
}

function withDraft(drafts, d) {
  var rest = (drafts || []).filter(function (x) { return x.id !== d.id })
  return [d].concat(rest).slice(0, DRAFTS)
}

function withoutId(list, id) {
  return (list || []).filter(function (x) { return x.id !== id })
}

function withStatus(outbox, id, status, error) {
  return (outbox || []).map(function (o) {
    if (o.id !== id) return o
    return { id: o.id, draft: o.draft, status: status, error: str(error), at: o.at }
  })
}
