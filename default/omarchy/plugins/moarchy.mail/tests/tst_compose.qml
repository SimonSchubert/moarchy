import QtQuick
import QtTest
import "../Compose.js" as Compose
import "../Store.js" as Store
import "../Helper.js" as Helper

TestCase {
  name: "Compose"

  readonly property var body: ({
    uid: 231, uidvalidity: 99,
    subject: "Train tickets",
    from: [{ name: "Hannah Lindqvist", email: "hannah@example.net" }],
    to: [{ name: "Ada", email: "ada@example.org" }],
    cc: [{ name: "Jonas Weber", email: "jonas@example.com" }],
    replyTo: [],
    date: new Date(2026, 8, 16, 9, 30).getTime(),
    messageId: "<m2@example.net>",
    references: "<m1@example.net>",
    text: "Tickets attached.\n\n> Shall we go?",
    attachments: [{ index: 3, name: "tickets.pdf", type: "application/pdf", size: 10 }]
  })

  function test_subjects_are_not_prefixed_twice() {
    compare(Compose.reSubject("Hello"), "Re: Hello")
    compare(Compose.reSubject("RE: Hello"), "RE: Hello")
    compare(Compose.reSubject("AW: Hallo"), "AW: Hallo")
    compare(Compose.fwdSubject("Fw: x"), "Fw: x")
    compare(Compose.fwdSubject("x"), "Fwd: x")
  }

  function test_a_reply() {
    var d = Compose.reply(body, "INBOX", "ada@example.org", false, 1000)
    compare(d.to, "Hannah Lindqvist <hannah@example.net>")
    compare(d.cc, "")
    compare(d.subject, "Re: Train tickets")
    compare(d.inReplyTo, "<m2@example.net>")
    compare(d.references, "<m1@example.net> <m2@example.net>")
    compare(d.answered, { folder: "INBOX", uid: 231 })
    compare(d.text, "\n\nOn Wed 16 Sep 2026 at 09:30, Hannah Lindqvist wrote:\n> Tickets attached.\n> \n>> Shall we go?")
    verify(Compose.untouched(d))
    verify(!Compose.untouched(Compose.withFields(d, { text: "Yes!" + d.text })))
  }

  function test_reply_all_keeps_cc_and_leaves_me_out() {
    var d = Compose.reply(body, "INBOX", "ada@example.org", true, 1000)
    compare(d.to, "Hannah Lindqvist <hannah@example.net>")
    compare(d.cc, "Jonas Weber <jonas@example.com>")
    compare(d.mode, "replyAll")
  }

  function test_a_forward_takes_the_attachments_with_it() {
    var d = Compose.forward(body, "INBOX", 1000)
    compare(d.subject, "Fwd: Train tickets")
    compare(d.forward, { folder: "INBOX", uid: 231, uidvalidity: 99, indexes: [3] })
    compare(d.attachments, ["tickets.pdf"])
    verify(d.text.indexOf("From: Hannah Lindqvist <hannah@example.net>") > 0)
    compare(d.to, "")
  }

  function test_mailto() {
    var d = Compose.fromMailto("mailto:ada@example.org,bob@example.org?cc=c%40example.org&subject=Hi%20there&body=Line%201%0D%0ALine+2", 5)
    compare(d.to, "ada@example.org,bob@example.org")
    compare(d.cc, "c@example.org")
    compare(d.subject, "Hi there")
    compare(d.text, "Line 1\nLine+2")
    compare(Compose.fromMailto("https://example.org", 5), null)
    // A mailto: link with anything in it is kept when Back is pressed.
    verify(!Compose.untouched(d))
  }

  function test_payloads() {
    compare(Compose.parsePayload("mailto:a@example.org", 1).draft.to, "a@example.org")
    compare(Compose.parsePayload('{"returnTo":"moarchy.contacts","to":"a@example.org"}', 1).draft.to, "a@example.org")
    compare(Compose.parsePayload('{"returnTo":"x"}', 1).returnTo, "x")
    compare(Compose.parsePayload("{}", 1).draft, null)
    compare(Compose.parsePayload("not json", 1).draft, null)
  }

  function test_what_cannot_be_sent_is_said() {
    compare(Compose.check(Compose.blank(1)), "Who is it to? Add an address.")
    var bad = Compose.withFields(Compose.blank(1), { to: "ada@example.org, jonas" })
    verify(Compose.check(bad).indexOf("jonas") > 0)
    compare(Compose.check(Compose.withFields(Compose.blank(1), { bcc: "a@example.org" })), "")
  }

  function test_a_draft_survives_the_state_file() {
    var d = Compose.forward(body, "INBOX", 1000)
    var state = Store.emptyState()
    state.drafts = Store.withDraft([], d)
    state.outbox = [{ id: "o1", draft: d, status: "sending", error: "", at: 5 }]
    var back = Store.parseState(JSON.parse(Store.serializeState(state)))
    compare(back.drafts[0].forward, d.forward)
    compare(back.drafts[0].text, d.text)
    // Sending when the file was written means nobody knows if it went.
    compare(back.outbox[0].status, "failed")
    verify(back.outbox[0].error.indexOf("may have gone") > 0)
  }

  function test_folders_belong_to_one_account() {
    var text = Store.serializeFolders([{ name: "INBOX", label: "Inbox", parent: "", role: "inbox", unseen: 2, total: 9 }],
                                      "ada@example.org")
    compare(Store.parseFolders(JSON.parse(text), "ada@example.org").length, 1)
    compare(Store.parseFolders(JSON.parse(text), "jonas@example.com").length, 0)
    compare(Store.label([], "INBOX"), "Inbox")
  }

  function test_helper_answers() {
    compare(Helper.result(0, 'noise\n{"ok": true, "rows": []}\n', "").ok, true)
    compare(Helper.result(127, "", "sh: moarchy-mail: not found").kind, "missing")
    var broken = Helper.result(1, "", "Traceback\nKeyError: 'x'")
    compare(broken.kind, "bug")
    verify(broken.error.indexOf("KeyError") > 0)
    compare(Helper.command("moarchy-mail", "sync"), ["sh", "-c", "exec \"$0\" \"$1\"", "moarchy-mail", "sync"])
  }
}
