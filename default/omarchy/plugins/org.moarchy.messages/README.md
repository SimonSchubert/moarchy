# Messages, in the shell

Text messages, by the person they are with.

This replaces Chatty on moarchy, and like Phone it replaces Chatty's daemon
too. The shell keeps the plugin loaded, and a sleeping `gdbus monitor` hears
ModemManager say a text arrived. The text is written to `messages.json` first
and deleted from the modem after, which is Chatty's rule and the one that
loses nothing: a text is never only in the place that forgets it. A text
still arriving in parts is left alone until the last part is in.

Three screens: **conversations** (unread in bold, with a count), **a
conversation** (newest at the bottom, a field for the next one; a text that
did not go says so and is sent again with a tap), and **new message** (a name
from Contacts, or a number).

## How it reaches the modem

`Modem.js` is the same file Phone carries.

| what | how |
| --- | --- |
| hearing a text | `gdbus monitor --system --dest org.freedesktop.ModemManager1` |
| reading texts | `mmcli -m any --messaging-list-sms`, then `mmcli -s <sms> -J` for each |
| sending | the text on stdin to `mmcli --messaging-create-sms-with-text=/dev/stdin`, then `--send`, then delete |
| a new text | `fbcli -E message-new-sms`, and a line in the shade through `omarchy-notification-send` |

The text goes in on stdin because mmcli's `text='…'` option has no escaping,
so a message with both kinds of quote in it cannot be said that way at all.
ModemManager picks the encoding and splits long texts itself.

## Install on the phone

```sh
plugins/org.moarchy.messages/install-on-device.sh
```

This also stops and masks `sm.puri.Chatty-daemon`: Chatty takes every text off
the modem and deletes it, so while it runs nothing arrives here. `systemctl
--user unmask sm.puri.Chatty-daemon.service` undoes it. Chatty's own history
stays where it was, in `~/.local/share/chatty/`; it is not imported.

Then tap **Messages** in the drawer, or:

```sh
omarchy-shell shell toggle org.moarchy.messages
qs ipc call messages compose "+44 7700 900412"
```

## Run it without the shell

```sh
plugins/org.moarchy.messages/run-local.sh
```

Standalone, it only listens while its window is open.

Texts are kept in `~/.local/share/moarchy-messages/messages.json` (or
`$MOARCHY_MESSAGES_DIR`). Names come from Contacts' file, read and never
written.

## What it does not do

- No MMS: no pictures, no group texts.
- No delivery reports, no read receipts, no typing indicators. It is SMS.
- No search, no archive, no blocking.
- One line to type in. A long text is still sent whole.

Each of those is a screen. This app has three.
