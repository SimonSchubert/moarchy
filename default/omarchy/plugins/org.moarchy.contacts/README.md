# Contacts, in the shell

A name, a number, an email, and a note. One file. No accounts.

This one is not a port. Calendar in this repository already says why
Evolution's data server is the price of contacts-with-accounts; this is the
other half of that argument — an address book that fits in a plugin the shell
already holds, so summoning it is `visible = true` rather than four seconds of
starting a process.

Two screens: the list (searchable, lettered), and the editor.

## Install on the phone

```sh
plugins/org.moarchy.contacts/install-on-device.sh
```

Then tap **Contacts** in the drawer, or:

```sh
omarchy-shell shell toggle org.moarchy.contacts
```

## Run it without the shell

```sh
plugins/org.moarchy.contacts/run-local.sh
```

Contacts live in `~/.local/share/moarchy-contacts/contacts.json`, or
`$MOARCHY_CONTACTS_DIR` if set.

## What it does not do

- No sync, no CardDAV, no Google, no vCard import.
- No photos, no groups, no favourites.
- Nobody is dialled from here — it is a book, not a phone.

Each of those is a row that would need a screen. This app has two.
