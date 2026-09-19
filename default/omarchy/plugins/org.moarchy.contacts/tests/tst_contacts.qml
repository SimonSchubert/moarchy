import QtQuick
import QtTest
import "../Contacts.js" as Contacts
import "../Store.js" as Store

TestCase {
  name: "Contacts"

  function test_a_contact_goes_out_and_comes_back() {
    var c = Contacts.blank(1)
    c.name = "Ada Lovelace"
    c.phone = "+441234"
    c.email = "ada@example.com"
    c.note = "Analytical Engine"

    var back = Store.parse(JSON.parse(Store.serialize([c], [])))
    compare(back.contacts.length, 1)
    var got = back.contacts[0]
    compare(got.name, "Ada Lovelace")
    compare(got.phone, "+441234")
    compare(got.email, "ada@example.com")
    compare(got.note, "Analytical Engine")
    compare(got.id, c.id)
  }

  function test_what_is_empty_is_left_out_of_the_file() {
    var c = Contacts.blank(1)
    c.name = "Grace"
    var row = JSON.parse(Store.serialize([c], [])).contacts[0]
    compare(row.name, "Grace")
    compare(row.phone, undefined)
    compare(row.email, undefined)
    compare(row.note, undefined)
  }

  function test_the_file_is_written_in_name_order() {
    var b = Contacts.blank(1); b.name = "Zoe"
    var a = Contacts.blank(2); a.name = "Ada"
    var rows = JSON.parse(Store.serialize([b, a], [])).contacts
    compare(rows[0].name, "Ada")
    compare(rows[1].name, "Zoe")
  }

  function test_strays_are_kept() {
    var c = Contacts.blank(1); c.name = "Ada"
    var stray = { weird: true }
    var back = Store.parse(JSON.parse(Store.serialize([c], [stray])))
    compare(back.contacts.length, 1)
    compare(back.strays.length, 1)
    compare(back.strays[0].weird, true)
  }

  function test_search_matches_any_field() {
    var c = Contacts.blank(1)
    c.name = "Ada"
    c.phone = "+441234"
    c.email = "ada@example.com"
    verify(Contacts.matches(c, "ada"))
    verify(Contacts.matches(c, "1234"))
    verify(Contacts.matches(c, "EXAMPLE"))
    verify(!Contacts.matches(c, "grace"))
  }

  function test_sections_group_by_letter() {
    var a = Contacts.blank(1); a.name = "Ada"
    var b = Contacts.blank(2); b.name = "Alan"
    var z = Contacts.blank(3); z.name = "Zoe"
    var n = Contacts.blank(4); n.phone = "999"
    var list = [z, a, n, b]
    list.sort(Contacts.byName)
    var groups = Contacts.sections(list)
    compare(groups.length, 3)
    compare(groups[0].letter, "#")
    compare(groups[0].contacts.length, 1)
    compare(groups[1].letter, "A")
    compare(groups[1].contacts.length, 2)
    compare(groups[2].letter, "Z")
  }

  function test_empty_row_is_not_a_contact() {
    compare(Contacts.normalise({ name: "  " }, 1), null)
    compare(Contacts.normalise({ phone: "+1" }, 1).phone, "+1")
  }
}
