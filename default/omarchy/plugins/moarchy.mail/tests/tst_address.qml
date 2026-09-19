import QtQuick
import QtTest
import "../Address.js" as Address

TestCase {
  name: "Address"

  function test_a_typed_line_back_into_people() {
    var r = Address.parseList('"Weber, Jonas" <jonas@example.com>; ada@example.org, Mum <mum@example.org>,')
    compare(r.bad, [])
    compare(r.people.length, 3)
    compare(r.people[0], { name: "Weber, Jonas", email: "jonas@example.com" })
    compare(r.people[1], { name: "", email: "ada@example.org" })
    compare(r.people[2].name, "Mum")
  }

  function test_what_is_not_an_address_is_named() {
    var r = Address.parseList("ada@example.org, jonas, bob@")
    compare(r.bad, ["jonas", "bob@"])
  }

  function test_formatting_quotes_what_needs_it() {
    compare(Address.format({ name: "Weber, Jonas", email: "j@example.com" }), '"Weber, Jonas" <j@example.com>')
    compare(Address.format({ name: "Ada Okonkwo", email: "a@example.org" }), "Ada Okonkwo <a@example.org>")
    compare(Address.format({ name: "", email: "a@example.org" }), "a@example.org")
    var back = Address.parseList(Address.format({ name: 'Say "hi"', email: "s@example.org" }))
    compare(back.people[0].name, 'Say "hi"')
  }

  function test_initials() {
    compare(Address.initial({ name: "\"ada\"", email: "" }), "A")
    compare(Address.initial({ name: "", email: "jonas@example.com" }), "J")
    compare(Address.initial({ name: "Ölmühle", email: "" }), "Ö")
    compare(Address.initial(null), "?")
  }

  function test_suggestions_match_the_word_being_typed() {
    var book = Address.people({ contacts: [
      { name: "Hannah Lindqvist", email: "hannah@example.net" },
      { name: "Jonas Weber", email: "jonas@example.com" },
      { name: "No Address", phone: "+44" },
      { name: "Two", email: "one@example.org, two@example.org" }
    ] })
    compare(book.length, 4)
    compare(Address.matching(book, "Hannah Lindqvist <hannah@example.net>, we").map(function (p) { return p.email }),
            ["jonas@example.com"])
    compare(Address.matching(book, "lind").length, 1)
    // Somebody already on the line is not offered again.
    compare(Address.matching(book, "jonas@example.com, jo").length, 0)
    compare(Address.matching(book, "").length, 0)
  }

  function test_picking_replaces_only_the_last_word() {
    compare(Address.replaceLastToken("ada@example.org, jo", { name: "Jonas Weber", email: "jonas@example.com" }),
            "ada@example.org, Jonas Weber <jonas@example.com>, ")
    compare(Address.replaceLastToken("jo", { name: "", email: "jonas@example.com" }), "jonas@example.com, ")
  }

  function test_reply_goes_to_reply_to_and_never_to_me() {
    var body = {
      from: [{ name: "List", email: "list@example.org" }],
      replyTo: [{ name: "", email: "answers@example.org" }],
      to: [{ name: "Ada", email: "ADA@example.org" }, { name: "Jonas", email: "jonas@example.com" }],
      cc: [{ name: "Jonas again", email: "jonas@example.com" }, { name: "Carla", email: "carla@example.net" }]
    }
    compare(Address.replyTo(body, "ada@example.org").map(function (p) { return p.email }), ["answers@example.org"])
    var all = Address.replyAll(body, "ada@example.org")
    compare(all.to.map(function (p) { return p.email }), ["answers@example.org"])
    compare(all.cc.map(function (p) { return p.email }), ["jonas@example.com", "carla@example.net"])
  }

  function test_replying_to_my_own_message_goes_to_whom_i_sent_it() {
    var body = { from: [{ name: "Ada", email: "ada@example.org" }], replyTo: [],
                 to: [{ name: "Jonas", email: "jonas@example.com" }], cc: [] }
    compare(Address.replyTo(body, "ada@example.org").map(function (p) { return p.email }), ["jonas@example.com"])
  }
}
