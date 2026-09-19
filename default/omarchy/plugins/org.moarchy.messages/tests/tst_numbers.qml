import QtQuick
import QtTest
import "../Numbers.js" as Numbers

TestCase {
  name: "Numbers"

  function test_a_number_is_the_same_in_both_spellings() {
    verify(Numbers.same("+44 7700 900412", "07700900412"))
    verify(Numbers.same("+49 170 1234567", "0170 123 4567"))
    verify(Numbers.same("+4917012345678", "+49 170 12345678"))
    verify(!Numbers.same("+49 170 1234567", "+49 170 1234568"))
  }

  function test_a_short_number_only_matches_itself() {
    verify(Numbers.same("22000", "22000"))
    verify(!Numbers.same("22000", "122000"))
    verify(!Numbers.same("", ""))
  }

  function test_a_sender_that_is_a_word_is_compared_as_one() {
    verify(Numbers.same("DHL", "dhl"))
    verify(!Numbers.same("DHL", "345"))
    compare(Numbers.key("Vodafone"), "vodafone")
  }

  function test_what_can_be_dialled() {
    compare(Numbers.dialable("+44 (7700) 900-412"), "+447700900412")
    compare(Numbers.dialable("*100#"), "*100#")
    compare(Numbers.dialable("0170.123"), "0170123")
    compare(Numbers.dialable("call me"), "")
    compare(Numbers.dialable("1+1"), "")
    compare(Numbers.dialable("12;reboot"), "")
    compare(Numbers.dialable(""), "")
  }

  function test_names_come_from_the_contacts_file() {
    var data = { schema: 1, contacts: [
      { id: "a", name: "Mum", phone: "+44 7700 900030" },
      { id: "b", name: "Chen Wei", email: "chen@example.cn" },
      { id: "c", name: "Dentist", phone: "+49 30 5550188" },
      { id: "d", phone: "+1 555 0142" },
      "not a contact"
    ] }
    var people = Numbers.people(data)
    compare(people.length, 3)
    compare(people[0].name, "+1 555 0142")
    compare(people[1].name, "Dentist")
    var names = Numbers.index(people)
    compare(Numbers.nameFor(names, "07700900030"), "Mum")
    compare(Numbers.label(names, "030 5550188"), "Dentist")
    compare(Numbers.label(names, "+49 30 9999999"), "+49 30 9999999")
    compare(Numbers.label(names, ""), "Unknown")
  }

  function test_the_contact_list_filters_by_name_or_digits() {
    var people = [{ name: "Mum", phone: "+44 7700 900030" },
                  { name: "Dentist", phone: "+49 30 5550188" }]
    compare(Numbers.matching(people, "den").length, 1)
    compare(Numbers.matching(people, "900 030")[0].name, "Mum")
    compare(Numbers.matching(people, "").length, 2)
  }

  function test_a_missing_file_is_nobody() {
    compare(Numbers.people(null).length, 0)
    compare(Numbers.people({ contacts: "no" }).length, 0)
  }
}
