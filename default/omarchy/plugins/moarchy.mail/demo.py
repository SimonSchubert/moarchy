#!/usr/bin/env python3
"""An Inbox with a week of mail in it, and the files Mail keeps beside it.

A mail app is only itself with mail in it: an unread row in bold, a star, a
paperclip, a newsletter that is mostly links, a reply with the quote under it.
So this writes what the app and moarchy-mail would have written after a week of
use -- account.json, folders.json, state.json, a folder cache, and the parsed
bodies of two messages -- plus Contacts' file, because addresses are suggested
from there.

The two bodies are not written by hand. They are real messages, built with the
email package and parsed by moarchy-mail's own parse_message, so the screenshot
of a newsletter is what the helper really makes of one.

    MOARCHY_MAIL_DIR=/tmp/m/moarchy-mail plugins/moarchy.mail/demo.py

MOARCHY_MAIL_NOACCOUNT=1 writes nothing but Contacts, for the sign-in screen.
MOARCHY_MAIL_EXTRAS=1 adds a draft and a message that did not send.

Every address is at example.org, example.net or example.com, which RFC 2606
keeps for exactly this.
"""

from __future__ import annotations

import hashlib
import importlib.machinery
import importlib.util
import json
import os
import sys
import time
from email.message import EmailMessage
from pathlib import Path

HERE = Path(__file__).resolve().parent
# Loading bin/moarchy-mail as a module would leave a __pycache__ in bin/,
# and everything in bin/ is copied into moarchy's snapshot and the package.
sys.dont_write_bytecode = True
_loader = importlib.machinery.SourceFileLoader(
    "moarchy_mail", str(HERE / "bin" / "moarchy-mail")
)
_spec = importlib.util.spec_from_loader("moarchy_mail", _loader)
helper = importlib.util.module_from_spec(_spec)
_loader.exec_module(helper)

EMAIL = "ada@example.org"
UIDVALIDITY = 1726000000
MINUTE = 60 * 1000
HOUR = 60 * MINUTE

PEOPLE = [
    ("Hannah Lindqvist", "hannah@example.net"),
    ("Jonas Weber", "jonas@example.com"),
    ("Carla Moreno", "carla@example.net"),
    ("Mum", "mum@example.org"),
    ("Harriet Okafor", "harriet@example.com"),
]

# (uid, hours ago, (name, address), subject, preview, flags, attachment)
ROWS = [
    (
        231,
        0.4,
        ("Hannah Lindqvist", "hannah@example.net"),
        "Train tickets for Saturday",
        "I booked the 9:12 from Hamburg, so we are in Copenhagen by lunch. Tickets are attached, the seat numbers are on page two.",
        [],
        True,
    ),
    (
        230,
        1.3,
        ("Jonas Weber", "jonas@example.com"),
        "Re: Flat viewing on Thursday",
        "The landlord moved it to 18:30. Can you still make it? I can bring the measurements for the sofa.",
        ["\\Flagged"],
        False,
    ),
    (
        229,
        5,
        ("The Allotment Society", "news@allotments.example.org"),
        "September: harvest swap, and a new water butt",
        "Harvest swap on the 21st · Plot 14 is free · Volunteers needed for the compost rota",
        ["\\Seen"],
        False,
    ),
    (
        228,
        22,
        ("Carla Moreno", "carla@example.net"),
        "Book club: next month's pick",
        "It is between Piranesi and The Dispossessed. Vote by Friday, and bring snacks that are not crisps this time.",
        ["\\Seen"],
        False,
    ),
    (
        227,
        30,
        ("Praxis Dr. Keller", "termine@praxis-keller.example.com"),
        "Appointment reminder",
        "Your appointment is on Thursday 24 September at 09:30. Please bring your insurance card.",
        ["\\Seen"],
        False,
    ),
    (
        226,
        50,
        ("Mum", "mum@example.org"),
        "Sunday lunch",
        "Lunch is at one. Your aunt is bringing the good cake, the one with the cherries.",
        ["\\Seen", "\\Answered"],
        False,
    ),
    (
        225,
        75,
        ("Harriet Okafor", "harriet@example.com"),
        "Bouldering photos",
        "Some of these are actually in focus. The one of you on the overhang is my favourite.",
        ["\\Seen"],
        True,
    ),
    (
        224,
        120,
        ("home server", "backup@example.org"),
        "Nightly backup: 3 of 3 volumes",
        "photos 412 GB ok · documents 18 GB ok · mail 2.1 GB ok · took 41 minutes",
        ["\\Seen"],
        False,
    ),
    (
        223,
        170,
        ("Sturmfrei Bikes", "shop@example.com"),
        "Invoice 2026-0815",
        "Thank you for your order. Your invoice for the service on 9 September is attached.",
        ["\\Seen"],
        True,
    ),
]

FOLDERS = [
    ("INBOX", "Inbox", "", "inbox", 2, 231),
    ("Drafts", "Drafts", "", "drafts", 0, 1),
    ("Sent", "Sent", "", "sent", 0, 118),
    ("Archive", "Archive", "", "archive", 0, 1840),
    ("Archive/Receipts", "Receipts", "Archive", "", 0, 62),
    ("Travel", "Travel", "", "", 1, 14),
    ("Junk", "Junk", "", "junk", 3, 3),
    ("Trash", "Trash", "", "trash", 0, 9),
]


def md5(text: str) -> str:
    return hashlib.md5(text.encode("utf-8"), usedforsecurity=False).hexdigest()


def tickets(sent_ms: int) -> bytes:
    msg = EmailMessage()
    msg["From"] = "Hannah Lindqvist <hannah@example.net>"
    msg["To"] = "Ada Okonkwo <ada@example.org>"
    msg["Cc"] = "Jonas Weber <jonas@example.com>"
    msg["Subject"] = "Train tickets for Saturday"
    msg["Date"] = time.strftime(
        "%a, %d %b %Y %H:%M:%S +0000", time.gmtime(sent_ms / 1000)
    )
    msg["Message-ID"] = "<tickets-231@example.net>"
    msg.set_content(
        "Hi Ada,\n\n"
        "I booked the 9:12 from Hamburg, so we are in Copenhagen by lunch. Tickets are "
        "attached, the seat numbers are on page two.\n\n"
        "The flat is five minutes from the station: https://example.net/stay/nyhavn-17 "
        "and check-in is from three.\n\n"
        "Jonas, you said you would book the ferry back?\n\n"
        "Hannah\n\n"
        "> Shall we do the Copenhagen trip after all?\n"
        "> I can take the Friday off.\n"
    )
    msg.add_attachment(
        b"%PDF-1.4 " + b"0" * 182_000,
        maintype="application",
        subtype="pdf",
        filename="Tickets Hamburg-Copenhagen.pdf",
    )
    return msg.as_bytes()


def newsletter(sent_ms: int) -> bytes:
    msg = EmailMessage()
    msg["From"] = "The Allotment Society <news@allotments.example.org>"
    msg["To"] = "ada@example.org"
    msg["Subject"] = "September: harvest swap, and a new water butt"
    msg["Date"] = time.strftime(
        "%a, %d %b %Y %H:%M:%S +0000", time.gmtime(sent_ms / 1000)
    )
    msg["Message-ID"] = "<sept-229@allotments.example.org>"
    msg.set_content(
        """<html><head><style>td{font-family:Georgia}</style></head><body>
        <div style="display:none;max-height:0;overflow:hidden">Harvest swap on the 21st</div>
        <table width="600"><tr><td><img src="https://allotments.example.org/logo.png" alt="logo"></td></tr>
        <tr><td><h1>September at the allotments</h1>
        <p>The <b>harvest swap</b> is on Sunday the 21st, from ten until the courgettes run out.
        Bring what you have too much of and take what you do not.</p>
        <p><img src="https://allotments.example.org/swap.jpg"></p>
        <h2>Plot 14 is free</h2>
        <p>Half a plot by the east gate, with a shed that mostly keeps the rain out.
        <a href="https://allotments.example.org/plots/14?utm_source=newsletter">See the plot</a> or
        <a href="mailto:plots@allotments.example.org">write to the plot secretary</a>.</p>
        <h2>The compost rota</h2>
        <ul><li>Week 38: plots 1 to 6</li><li>Week 39: plots 7 to 12</li><li>Week 40: plots 13 to 18</li></ul>
        <p>Thanks to everyone who helped put up the new water butt.</p>
        <p style="font-size:11px"><a href="https://allotments.example.org/unsubscribe?u=8f2c">Unsubscribe</a></p>
        </td></tr></table></body></html>""",
        subtype="html",
    )
    return msg.as_bytes()


def write(path: Path, data) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    text = (
        data
        if isinstance(data, str)
        else json.dumps(data, indent=1, ensure_ascii=False)
    )
    path.write_text(text, encoding="utf-8")


def main() -> None:
    directory = Path(
        os.environ.get("MOARCHY_MAIL_DIR") or Path.home() / ".local/share/moarchy-mail"
    )
    directory.mkdir(parents=True, exist_ok=True)
    now = int(time.time() * 1000)

    contacts = directory.parent / "moarchy-contacts"
    book = [
        {"id": f"c-demo-{i:02d}", "name": n, "email": e}
        for i, (n, e) in enumerate(PEOPLE)
    ]
    write(contacts / "contacts.json", {"schema": 1, "contacts": book})

    if os.environ.get("MOARCHY_MAIL_NOACCOUNT"):
        return

    write(
        directory / "account.json",
        {
            "schema": 1,
            "name": "Ada Okonkwo",
            "email": EMAIL,
            "username": EMAIL,
            "imap": {"host": "imap.example.org", "port": 993, "security": "tls"},
            "smtp": {"host": "smtp.example.org", "port": 465, "security": "tls"},
        },
    )
    write(
        directory / "folders.json",
        {
            "schema": 1,
            "account": EMAIL,
            "folders": [
                {
                    "name": n,
                    "label": label,
                    "parent": p,
                    "role": r,
                    "unseen": u,
                    "total": t,
                }
                for n, label, p, r, u, t in FOLDERS
            ],
        },
    )

    rows = []
    for uid, ago, (name, address), subject, preview, flags, attachment in ROWS:
        at = now - int(ago * HOUR)
        rows.append(
            {
                "uid": uid,
                "flags": flags,
                "at": at,
                "date": at,
                "from": {"name": name, "email": address},
                "to": [{"name": "Ada Okonkwo", "email": EMAIL}],
                "subject": subject,
                "preview": preview,
                "attachment": attachment,
                "size": 4200,
            }
        )
    write(
        directory / "cache" / (md5(EMAIL + "\n" + "INBOX") + ".json"),
        {
            "schema": 1,
            "folder": "INBOX",
            "uidvalidity": UIDVALIDITY,
            "uidnext": 232,
            "exists": 231,
            "unseen": 2,
            "more": True,
            "at": now,
            "rows": rows,
        },
    )

    bodies = directory / "bodies" / md5("INBOX")
    for uid, raw in (
        (231, tickets(now - int(0.4 * HOUR))),
        (229, newsletter(now - 5 * HOUR)),
    ):
        parsed = helper.parse_message(raw)
        parsed.update(
            {"ok": True, "folder": "INBOX", "uidvalidity": UIDVALIDITY, "uid": uid}
        )
        write(bodies / f"{UIDVALIDITY}-{uid}.json", parsed)

    state = {
        "schema": 1,
        "folder": "INBOX",
        "inbox": {"uidvalidity": UIDVALIDITY, "uidnext": 232, "account": EMAIL},
        "drafts": [],
        "outbox": [],
    }
    if os.environ.get("MOARCHY_MAIL_EXTRAS"):
        state["outbox"].append(
            {
                "id": "o-demo-1",
                "status": "failed",
                "at": now - 20 * MINUTE,
                "error": "The server would not send to jonas@exmaple.com.",
                "draft": {
                    "id": "d-demo-1",
                    "mode": "reply",
                    "to": "Jonas Weber <jonas@exmaple.com>",
                    "subject": "Re: Flat viewing on Thursday",
                    "text": "18:30 works. See you there.",
                },
            }
        )
        state["drafts"].append(
            {
                "id": "d-demo-2",
                "mode": "new",
                "to": "Carla Moreno <carla@example.net>",
                "subject": "Book club",
                "text": "My vote is for The Dispossessed, and I will bring",
                "at": now - 3 * HOUR,
            }
        )
    write(directory / "state.json", state)
    print(directory)


if __name__ == "__main__":
    main()
