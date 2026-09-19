# Phone, in the shell

A keypad, the calls that happened, and the one happening now.

This replaces GNOME Calls on moarchy, and the part of Calls that mattered was
never its window. It was `calls-daemon`, the process that listened for a ring
while nothing was open. Here the plugin does that itself: the shell keeps it
loaded, and a `gdbus monitor` it starts a few seconds after the shell sleeps
on the system bus until ModemManager says something about a call.

Three tabs: **Keypad**, **Recents** (missed calls in red, a dot on the tab
until they have been looked at) and **Contacts** (everybody in Contacts' file
with a number, one tap from a call). When a call is up, the call screen
covers all three: Answer and Decline while it rings, then Mute, Keypad (tones,
for a menu that wants a digit), Speaker and End.

## How it reaches the modem

Through processes, because Quickshell has no D-Bus module. `Modem.js` has the
detail and the reasons. In short:

| what | how |
| --- | --- |
| hearing a call | `gdbus monitor --system --dest org.freedesktop.ModemManager1`, one line per signal |
| reading calls | `mmcli -m any --voice-list-calls`, then `mmcli -o <call> -J` for each |
| dialling | `mmcli -m any --voice-create-call=number=…`, then `--start` |
| answer, hang up, tones | `mmcli -o <call> --accept`, `--hangup`, `--send-dtmf=` |
| second call | `mmcli -m any --voice-hangup-and-accept` |
| earpiece, speaker, mute | callaudiod over `busctl --user` (`SelectMode`, `EnableSpeaker`, `MuteMic`) |
| ringing | `fbcli -E phone-incoming-call`, so the phone's feedback profile decides between a tone, a buzz and nothing |
| a locked screen | `moarchy-screen unlock`, and `lock` again when the call is over |

ModemManager keeps a call until somebody deletes it, so a call that has ended
is written to the log and then deleted, as GNOME Calls does.

## Install on the phone

```sh
plugins/org.moarchy.phone/install-on-device.sh
```

This also stops and masks `calls-daemon`, because GNOME Calls would otherwise
ring as well and answer from its own window. `systemctl --user unmask
calls-daemon.service` undoes it.

Then tap **Phone** in the drawer, or:

```sh
omarchy-shell shell toggle org.moarchy.phone
qs ipc call phone dial "+44 7700 900412"    # puts a number on the keypad
```

## Run it without the shell

```sh
plugins/org.moarchy.phone/run-local.sh
```

Standalone, it only listens while its window is open.

The log is `~/.local/share/moarchy-phone/calls.json` (or `$MOARCHY_PHONE_DIR`).
Names come from `~/.local/share/moarchy-contacts/contacts.json`, which this
reads and never writes.

## What it does not do

- No hold, no merge, no conference. A second call can be turned away, or taken
  by ending the first.
- No USSD (`*100#` dials as a number and the network decides).
- No proximity sensor: the screen stays on against your ear.
- No voicemail screen, no blocking, no favourites.
- No SIM PIN; that is `moarchy.sim`.

Each of those is a screen. This app has four.
