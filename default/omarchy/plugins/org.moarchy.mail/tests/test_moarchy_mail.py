"""bin/moarchy-mail, read in pieces and then run against a real server.

The pieces are the parts of mail that go wrong quietly: a folder name in
modified UTF-7, a FETCH response split at its literals, a charset that lied, a
newsletter's hidden preheader, a paragraph sent format=flowed. None of them
needs a network, and all of them run anywhere Python does.

The second half needs a server, and gets a real one: tests/e2e.sh starts
Dovecot in the moarchy-qml container, and these run the command the way the
app runs it -- a verb, JSON on stdin, JSON on stdout -- against it, with an SMTP
server in a thread here that keeps what it is sent. Without MOARCHY_MAIL_IMAP_PORT
that half is skipped, not failed.

    docker run --rm --platform linux/arm64 -v "$PWD:/src" -w /src moarchy-qml \
        plugins/org.moarchy.mail/tests/e2e.sh
"""

from __future__ import annotations

import base64
import imaplib
import importlib.machinery
import importlib.util
import json
import os
import socketserver
import subprocess
import tempfile
import threading
import sys
import time
import unittest
from email import policy
from email.message import EmailMessage
from email.parser import BytesParser
from pathlib import Path

HERE = Path(__file__).resolve().parent
# Loading bin/moarchy-mail as a module would leave a __pycache__ in bin/,
# and everything in bin/ is copied into moarchy's snapshot and the package.
sys.dont_write_bytecode = True
HELPER = HERE.parent / "bin" / "moarchy-mail"

_loader = importlib.machinery.SourceFileLoader("moarchy_mail", str(HELPER))
_spec = importlib.util.spec_from_loader("moarchy_mail", _loader)
mm = importlib.util.module_from_spec(_spec)
_loader.exec_module(mm)

NBSP = chr(0xA0)
ZWNJ = chr(0x200C)
CGJ = chr(0x034F)


class Utf7(unittest.TestCase):
    def test_round_trip(self):
        for name in (
            "INBOX",
            "Entwürfe",
            "Reisen ✈ 2026",
            "A&B",
            "日本語",
            "[Gmail]/Sent Mail",
        ):
            self.assertEqual(mm.utf7_decode(mm.utf7_encode(name)), name)

    def test_known_wire_forms(self):
        # RFC 3501's own example, and the ampersand rule.
        self.assertEqual(
            mm.utf7_encode("~peter/mail/台北/日本語"), "~peter/mail/&U,BTFw-/&ZeVnLIqe-"
        )
        self.assertEqual(mm.utf7_encode("A&B"), "A&-B")

    def test_quoted_argument(self):
        self.assertEqual(mm.mailbox('Say "hi"'), '"Say \\"hi\\""')


class Sets(unittest.TestCase):
    def test_ranges(self):
        self.assertEqual(mm.uid_set([5, 1, 2, 3, 9, 10, 12]), "1:3,5,9:10,12")
        self.assertEqual(mm.uid_set([7]), "7")


class Responses(unittest.TestCase):
    def test_fetch_split_at_literals(self):
        # What imaplib really returns for two items with literals and one without.
        data = [
            (
                b"1 (UID 41 FLAGS (\\Seen \\Answered) BODY[HEADER.FIELDS (FROM SUBJECT)] {35}",
                b"From: a@b.example\r\nSubject: Hi\r\n\r\n",
            ),
            (b" BODY[TEXT]<0> {5}", b"hello"),
            b")",
            b'2 (UID 42 FLAGS () INTERNALDATE "17-Jul-2026 02:44:25 -0700")',
        ]
        items = mm.fetched(data)
        self.assertEqual(len(items), 2)
        self.assertEqual(items[0]["UID"], "41")
        self.assertEqual(items[0]["FLAGS"], ["\\Seen", "\\Answered"])
        self.assertEqual(
            mm.pick(items[0], "BODY[HEADER"),
            b"From: a@b.example\r\nSubject: Hi\r\n\r\n",
        )
        self.assertEqual(mm.pick(items[0], "BODY[TEXT]"), b"hello")
        self.assertEqual(items[1]["FLAGS"], [])
        self.assertGreater(mm.internal_date(items[1]["INTERNALDATE"]), 0)

    def test_nil_and_quoted(self):
        node = mm.tree(mm.tokens([b'(\\Noselect) NIL "a \\"b\\""']))
        self.assertEqual(node, [["\\Noselect"], None, b'a "b"'])


class Folders(unittest.TestCase):
    class Fake:
        def __init__(self, lines):
            self.lines = lines

        def list(self, *_args):
            return "OK", self.lines

    def test_roles_by_flag_by_name_and_under_inbox(self):
        folders = mm.list_folders(
            self.Fake(
                [
                    b'(\\HasChildren) "." INBOX',
                    b'(\\HasNoChildren) "." INBOX.Sent',
                    b'(\\HasNoChildren) "." INBOX.Trash',
                    b'(\\HasNoChildren) "." INBOX.Projects.Sent',
                    b'(\\Noselect \\HasChildren) "/" "[Gmail]"',
                    b'(\\HasNoChildren \\Junk) "/" "[Gmail]/Spam"',
                    (b'(\\HasNoChildren) "/" {11}', b"Reisen &Jwg-"),
                    b"",
                ]
            )
        )
        roles = {f["name"]: f["role"] for f in folders}
        self.assertEqual(roles["INBOX"], "inbox")
        self.assertEqual(roles["INBOX.Sent"], "sent")
        self.assertEqual(roles["INBOX.Trash"], "trash")
        self.assertEqual(roles["INBOX.Projects.Sent"], "")
        self.assertEqual(roles["[Gmail]/Spam"], "junk")
        self.assertNotIn("[Gmail]", roles)
        self.assertIn("Reisen ✈", roles)
        spam = next(f for f in folders if f["name"] == "[Gmail]/Spam")
        self.assertEqual((spam["label"], spam["parent"]), ("Spam", ""))
        self.assertEqual(folders[0]["name"], "INBOX")


class Drawing(unittest.TestCase):
    def test_plain_escapes_and_links(self):
        runs = mm.Runs()
        mm.plain_runs(
            "a <b> & c https://example.org/x?a=1&b=2. and ada@example.org", runs
        )
        markup = runs.markup()
        self.assertIn("&lt;b&gt; &amp; c", markup)
        self.assertNotIn("<b>", markup)
        self.assertIn('<a href="#0">https://example.org/x?a=1&amp;b=2</a>.', markup)
        self.assertEqual(
            runs.links, ["https://example.org/x?a=1&b=2", "mailto:ada@example.org"]
        )

    def test_quotes_are_coloured(self):
        runs = mm.Runs()
        mm.plain_runs("Yes.\n\n> Are you coming?", runs)
        self.assertIn(
            f'<font color="{mm.QUOTE_INK}">&gt; Are you coming?</font>', runs.markup()
        )
        self.assertEqual(runs.plain(), "Yes.\n\n> Are you coming?")

    def test_html_keeps_words_and_drops_the_rest(self):
        source = (
            "<html><head><title>T</title><style>p{color:red}</style></head><body>"
            f'<div style="display:none;max-height:0">Preheader{CGJ}{ZWNJ}{CGJ}</div>'
            "<table><tr><td><h1>Big news</h1></td></tr>"
            '<tr><td><p>Read it <a href="https://example.org/a?x=1&amp;y=2">here</a>'
            f'<img src="https://tracker.example/p.gif">.{NBSP}</p>'
            '<p><a href="javascript:alert(1)">bad</a></p>'
            "<script>alert(2)</script><ul><li>one</li><li>two</li></ul></td></tr></table>"
            "</body></html>"
        )
        runs = mm.Runs()
        pictures = mm.html_runs(source, runs)
        text = runs.plain()
        self.assertEqual(pictures, 1)
        self.assertNotIn("Preheader", text)
        self.assertNotIn("alert", text)
        self.assertNotIn("color:red", text)
        self.assertIn("Big news", text)
        self.assertIn("• one\n• two", text)
        markup = runs.markup()
        self.assertIn("<b>Big news</b>", markup)
        self.assertIn('<a href="#0">here</a>', markup)
        self.assertNotIn("img", markup)
        self.assertNotIn("javascript", markup)
        self.assertEqual(runs.links, ["https://example.org/a?x=1&y=2"])

    def test_budget(self):
        runs = mm.Runs(budget=10)
        runs.text("0123456789abcdef")
        self.assertTrue(runs.truncated)
        self.assertEqual(runs.plain(), "0123456789")

    def test_unflow(self):
        flowed = "This is a long \nparagraph that was \nwrapped.\n> quoted \n> on two\n-- \nsig"
        self.assertEqual(
            mm.unflow(flowed, False),
            "This is a long paragraph that was wrapped.\n> quoted on two\n-- \nsig",
        )


def sample(
    subject="Hello",
    text="Plain body",
    sender="Ada Okonkwo <ada@example.org>",
    **headers,
):
    msg = EmailMessage()
    msg["From"] = sender
    msg["To"] = "Me <me@example.test>"
    msg["Subject"] = subject
    msg["Date"] = "Wed, 16 Sep 2026 09:30:00 +0200"
    msg["Message-ID"] = headers.pop("message_id", "<m1@example.org>")
    for key, value in headers.items():
        msg[key.replace("_", "-")] = value
    msg.set_content(text)
    return msg


class Messages(unittest.TestCase):
    def test_latin1_that_is_really_windows_1252(self):
        raw = (
            b"From: x@example.org\r\nSubject: =?iso-8859-1?q?Gr=FC=DFe?=\r\n"
            b"Content-Type: text/plain; charset=iso-8859-1\r\n"
            b"Content-Transfer-Encoding: 8bit\r\n\r\n"
            b"Gr\xfc\xdfe \x93quoted\x94\r\n"
        )
        parsed = mm.parse_message(raw)
        self.assertEqual(parsed["subject"], "Grüße")
        self.assertEqual(parsed["text"].strip(), "Grüße “quoted”")

    def test_raw_utf8_header_without_encoding(self):
        raw = "From: Jürgen <j@example.org>\r\nSubject: Übung macht den Meister\r\n\r\nhi\r\n".encode()
        parsed = mm.parse_message(raw)
        self.assertEqual(parsed["subject"], "Übung macht den Meister")
        self.assertEqual(parsed["from"], [{"name": "Jürgen", "email": "j@example.org"}])
        json.dumps(parsed)

    def test_attachments_and_inline_images(self):
        msg = sample(text="See attached")
        msg.add_alternative(
            '<p>See attached <img src="cid:logo@x"></p>', subtype="html"
        )
        html_part = msg.get_payload()[1]
        html_part.add_related(b"PNGDATA", "image", "png", cid="<logo@x>")
        msg.add_attachment(
            b"%PDF-1.4 fake",
            maintype="application",
            subtype="pdf",
            filename="Invoice 2026.pdf",
        )
        parsed = mm.parse_message(msg.as_bytes())
        self.assertEqual(
            [a["name"] for a in parsed["attachments"]], ["Invoice 2026.pdf"]
        )
        self.assertEqual(parsed["attachments"][0]["size"], len(b"%PDF-1.4 fake"))
        self.assertEqual(parsed["text"].strip(), "See attached")

    def test_preview_from_a_cut_body(self):
        body = ("Lunch is at one. " * 40).encode()
        encoded = base64.encodebytes(body)
        raw = (
            b"From: a@example.org\r\nSubject: s\r\nContent-Type: multipart/alternative; boundary=XX\r\n\r\n"
            b"--XX\r\nContent-Type: text/plain; charset=utf-8\r\nContent-Transfer-Encoding: base64\r\n\r\n"
            + encoded
            + b"\r\n--XX\r\nContent-Type: text/html\r\n\r\n<p>x</p>\r\n--XX--\r\n"
        )
        cut = raw[:260]
        row = mm.header_row(
            {
                "UID": "5",
                "FLAGS": ["\\Seen"],
                "BODY[HEADER.FIELDS (FROM SUBJECT CONTENT-TYPE)]": cut.split(
                    b"\r\n\r\n", 1
                )[0]
                + b"\r\n\r\n",
                "BODY[TEXT]<0>": cut.split(b"\r\n\r\n", 1)[1],
            }
        )
        self.assertTrue(row["preview"].startswith("Lunch is at one."))
        self.assertEqual(row["uid"], 5)

    def test_preview_drops_quotes(self):
        msg = BytesParser(policy=policy.default).parsebytes(
            sample(
                text="Sounds good\n\n> On Tuesday you wrote:\n> old stuff"
            ).as_bytes()
        )
        self.assertEqual(mm.preview_of(msg), "Sounds good")


class Sending(unittest.TestCase):
    account = {
        "name": "Me Myself",
        "email": "me@example.test",
        "username": "me",
        "imap": {"host": "h", "port": 1, "security": "none"},
        "smtp": {"host": "h", "port": 1, "security": "none"},
    }

    def test_headers(self):
        msg = mm.build_message(
            self.account,
            {
                "to": "Ada Okonkwo <ada@example.org>, bob@example.org",
                "cc": "",
                "bcc": "secret@example.org",
                "subject": "Grüße\nInjected: yes",
                "text": "Hallo – wie geht’s?",
                "inReplyTo": "<m1@example.org>",
                "references": "<m0@example.org> <m1@example.org>",
            },
        )
        raw = msg.as_bytes()
        self.assertIn(b"To: Ada Okonkwo <ada@example.org>, bob@example.org", raw)
        self.assertNotIn(b"\nInjected:", raw)
        self.assertIn(b"In-Reply-To: <m1@example.org>", raw)
        again = BytesParser(policy=policy.default).parsebytes(raw)
        self.assertEqual(str(again["subject"]), "Grüße Injected: yes")
        self.assertEqual(again.get_content().strip(), "Hallo – wie geht’s?")

    def test_bad_addresses_are_refused(self):
        for typed in ("ada", "ada@", "<>", "a b@example.org"):
            with self.assertRaises(mm.MailError, msg=typed):
                mm.build_message(self.account, {"to": typed, "text": "x"})
        with self.assertRaises(mm.MailError):
            mm.build_message(self.account, {"to": "", "text": "x"})


class Setup(unittest.TestCase):
    def test_autoconfig_document(self):
        document = b"""<clientConfig version="1.1"><emailProvider id="example.org">
          <incomingServer type="pop3"><hostname>pop.example.org</hostname><port>995</port>
            <socketType>SSL</socketType><username>%EMAILADDRESS%</username></incomingServer>
          <incomingServer type="imap"><hostname>imap.example.org</hostname><port>143</port>
            <socketType>STARTTLS</socketType><username>%EMAILLOCALPART%</username></incomingServer>
          <incomingServer type="imap"><hostname>imap.example.org</hostname><port>993</port>
            <socketType>SSL</socketType><username>%EMAILLOCALPART%</username></incomingServer>
          <outgoingServer type="smtp"><hostname>smtp.example.org</hostname><port>587</port>
            <socketType>STARTTLS</socketType><username>%EMAILADDRESS%</username></outgoingServer>
        </emailProvider></clientConfig>"""
        found = mm.autoconfig_servers(document, "ada@example.org")
        self.assertEqual(
            found["imap"], {"host": "imap.example.org", "port": 993, "security": "tls"}
        )
        self.assertEqual(
            found["smtp"],
            {"host": "smtp.example.org", "port": 587, "security": "starttls"},
        )
        self.assertEqual(found["username"], "ada")

    def test_safe_names(self):
        self.assertEqual(mm.safe_name("../../.bashrc"), "_.._.bashrc")
        self.assertEqual(mm.safe_name("   "), "attachment")
        with tempfile.TemporaryDirectory() as d:
            (Path(d) / "a.pdf").write_bytes(b"")
            self.assertEqual(mm.free_path(Path(d), "a.pdf").name, "a (2).pdf")


# --- against a server ---------------------------------------------------------------


class _Sink(socketserver.StreamRequestHandler):
    """Enough of SMTP to be sent mail by smtplib, and to refuse some of it."""

    def reply(self, line: str) -> None:
        self.wfile.write(line.encode() + b"\r\n")

    def handle(self):
        server = self.server
        self.reply("220 sink ready")
        authed = False
        rcpts: list[str] = []
        while True:
            line = self.rfile.readline()
            if not line:
                return
            command = line.decode().strip()
            verb = command.split(" ", 1)[0].upper()
            if verb == "EHLO":
                self.reply("250-sink")
                self.reply("250-8BITMIME")
                self.reply("250 AUTH PLAIN")
            elif verb == "AUTH":
                blob = base64.b64decode(command.split(" ")[2])
                _, user, password = blob.decode("utf-8").split(chr(0))
                authed = (user, password) == server.credentials
                self.reply("235 ok" if authed else "535 5.7.8 Authentication failed")
            elif verb == "MAIL":
                rcpts = []
                self.reply("250 ok" if authed else "530 auth first")
            elif verb == "RCPT":
                who = command.split(":", 1)[1].strip().strip("<>")
                if who.endswith("@refused.test"):
                    self.reply("550 no such user")
                else:
                    rcpts.append(who)
                    self.reply("250 ok")
            elif verb == "DATA":
                self.reply("354 go on")
                data = bytearray()
                while True:
                    chunk = self.rfile.readline()
                    if chunk in (b".\r\n", b".\n", b""):
                        break
                    data += chunk[1:] if chunk.startswith(b"..") else chunk
                server.received.append((list(rcpts), bytes(data)))
                self.reply("250 queued")
            elif verb == "QUIT":
                self.reply("221 bye")
                return
            else:
                self.reply("250 ok")


@unittest.skipUnless(
    os.environ.get("MOARCHY_MAIL_IMAP_PORT"), "no server: run tests/e2e.sh"
)
class AgainstDovecot(unittest.TestCase):
    user = os.environ.get("MOARCHY_MAIL_USER", "ada")
    password = os.environ.get("MOARCHY_MAIL_PASSWORD", "secret pass")

    @classmethod
    def setUpClass(cls):
        cls.sink = socketserver.ThreadingTCPServer(("127.0.0.1", 0), _Sink)
        cls.sink.daemon_threads = True
        cls.sink.received = []
        cls.sink.credentials = (cls.user, cls.password)
        threading.Thread(target=cls.sink.serve_forever, daemon=True).start()
        cls.dir = tempfile.mkdtemp(prefix="moarchy-mail-")
        cls.downloads = tempfile.mkdtemp(prefix="downloads-")
        cls.port = int(os.environ["MOARCHY_MAIL_IMAP_PORT"])
        cls.seed()

    @classmethod
    def tearDownClass(cls):
        cls.sink.shutdown()

    @classmethod
    def seed(cls):
        conn = imaplib.IMAP4("127.0.0.1", cls.port)
        conn.login(cls.user, cls.password)
        conn.create(mm.mailbox("Reisen ✈"))
        plain = sample(
            subject="Sunday lunch", text="Lunch is at 1.\n\n> Are you coming?"
        )
        rich = sample(
            subject="Your weekly digest",
            sender="News <news@example.org>",
            message_id="<m2@example.org>",
        )
        rich.set_content(
            '<p>Hello <a href="https://example.org/r">read more</a></p>', subtype="html"
        )
        attached = sample(
            subject="Invoice", text="Attached.", message_id="<m3@example.org>"
        )
        attached.add_attachment(
            b"%PDF-1.4 fake",
            maintype="application",
            subtype="pdf",
            filename="Invoice.pdf",
        )
        for msg, flags in ((plain, ""), (rich, "(\\Seen)"), (attached, "")):
            typ, _ = conn.append("INBOX", flags or None, time.time(), msg.as_bytes())
            assert typ == "OK", typ
        for n in range(3):
            conn.append(
                mm.mailbox("Reisen ✈"),
                None,
                time.time(),
                sample(
                    subject=f"Trip {n}", message_id=f"<t{n}@example.org>"
                ).as_bytes(),
            )
        conn.logout()

    def run_verb(self, verb: str, request: dict | None = None, **env) -> dict:
        environment = dict(
            os.environ, MOARCHY_MAIL_DIR=self.dir, XDG_CONFIG_HOME=self.dir, **env
        )
        done = subprocess.run(
            [str(HELPER), verb],
            input=json.dumps(request or {}).encode(),
            capture_output=True,
            env=environment,
            timeout=60,
            check=False,
        )
        answer = json.loads(done.stdout.decode())
        self.assertEqual(done.returncode == 0, answer["ok"], done.stderr.decode())
        return answer

    def account(self, **changes) -> dict:
        request = {
            "name": "Ada Okonkwo",
            "email": "ada@example.test",
            "username": self.user,
            "password": self.password,
            "imap": {"host": "127.0.0.1", "port": self.port, "security": "none"},
            "smtp": {
                "host": "127.0.0.1",
                "port": self.sink.server_address[1],
                "security": "none",
            },
        }
        request.update(changes)
        return request

    def test_1_setup_refuses_a_wrong_password(self):
        answer = self.run_verb("setup", self.account(password="nope"))
        self.assertEqual(answer["kind"], "auth")
        self.assertFalse((Path(self.dir) / "account.json").exists())

    def test_1_setup_says_a_closed_port_is_closed(self):
        answer = self.run_verb(
            "setup",
            self.account(imap={"host": "127.0.0.1", "port": 1, "security": "none"}),
        )
        self.assertEqual(answer["kind"], "network")
        self.assertIn("refused", answer["error"])

    def test_1_setup_checks_certificates(self):
        tls_port = os.environ.get("MOARCHY_MAIL_IMAPS_PORT")
        if not tls_port:
            self.skipTest("no TLS listener")
        imap = {"host": "localhost", "port": int(tls_port), "security": "tls"}
        answer = self.run_verb(
            "setup", self.account(imap=imap), SSL_CERT_FILE="/nonexistent"
        )
        self.assertEqual(answer["kind"], "tls")

    def test_2_setup_and_folders(self):
        answer = self.run_verb("setup", self.account())
        self.assertTrue(answer["ok"], answer)
        for name in ("account.json", "password"):
            mode = (Path(self.dir) / name).stat().st_mode & 0o777
            self.assertEqual(mode, 0o600, name)
        self.assertNotIn(
            "password", json.loads((Path(self.dir) / "account.json").read_text())
        )

        tls_port = os.environ.get("MOARCHY_MAIL_IMAPS_PORT")
        if tls_port:
            # The same account over TLS, with the test's own CA trusted: the
            # handshake and the hostname check both happen for real.
            imap = {"host": "localhost", "port": int(tls_port), "security": "tls"}
            answer = self.run_verb(
                "setup",
                self.account(imap=imap),
                SSL_CERT_FILE=os.environ["MOARCHY_MAIL_CA"],
            )
            self.assertTrue(answer["ok"], answer)
            answer = self.run_verb("setup", self.account())
            self.assertTrue(answer["ok"], answer)

        folders = self.run_verb("folders")["folders"]
        by_name = {f["name"]: f for f in folders}
        self.assertEqual(folders[0]["name"], "INBOX")
        self.assertEqual(by_name["INBOX"]["unseen"], 2)
        self.assertEqual(by_name["Sent"]["role"], "sent")
        self.assertEqual(by_name["Trash"]["role"], "trash")
        self.assertEqual(by_name["Reisen ✈"]["total"], 3)

    def test_3_sync_body_flag_move(self):
        self.run_verb("setup", self.account())
        first = self.run_verb(
            "sync", {"folder": "INBOX", "uidvalidity": 0, "uids": [], "limit": 50}
        )
        self.assertTrue(first["reset"])
        self.assertEqual(len(first["rows"]), 3)
        rows = {r["subject"]: r for r in first["rows"]}
        self.assertEqual(rows["Sunday lunch"]["preview"], "Lunch is at 1.")
        self.assertEqual(
            rows["Sunday lunch"]["from"],
            {"name": "Ada Okonkwo", "email": "ada@example.org"},
        )
        self.assertIn("\\Seen", rows["Your weekly digest"]["flags"])
        self.assertTrue(rows["Invoice"]["attachment"])

        # Nothing new: rows only for what the app did not have.
        again = self.run_verb(
            "sync",
            {
                "folder": "INBOX",
                "uidvalidity": first["uidvalidity"],
                "uids": [r["uid"] for r in first["rows"]],
            },
        )
        self.assertFalse(again["reset"])
        self.assertEqual(again["rows"], [])
        self.assertEqual(len(again["present"]), 3)

        # A small window, then older.
        window = self.run_verb(
            "sync", {"folder": "INBOX", "uidvalidity": 0, "uids": [], "limit": 2}
        )
        self.assertEqual(len(window["rows"]), 2)
        self.assertTrue(window["more"])
        older = self.run_verb(
            "sync",
            {
                "folder": "INBOX",
                "uidvalidity": window["uidvalidity"],
                "uids": [r["uid"] for r in window["rows"]],
                "limit": 2,
                "older": True,
            },
        )
        self.assertEqual(len(older["rows"]), 1)
        self.assertFalse(older["more"])

        invoice = rows["Invoice"]
        body = self.run_verb(
            "body",
            {
                "folder": "INBOX",
                "uidvalidity": first["uidvalidity"],
                "uid": invoice["uid"],
            },
        )
        self.assertEqual(body["attachments"][0]["name"], "Invoice.pdf")
        cached = mm.body_path("INBOX", first["uidvalidity"], invoice["uid"], ".json")
        self.assertTrue(Path(self.dir, cached.relative_to(mm.data_dir())).exists())
        # Fetching a body does not mark it read: the app does that on purpose.
        flags = self.run_verb(
            "sync",
            {
                "folder": "INBOX",
                "uidvalidity": first["uidvalidity"],
                "uids": [r["uid"] for r in first["rows"]],
            },
        )["present"]
        self.assertNotIn("\\Seen", dict((u, f) for u, f in flags)[invoice["uid"]])

        saved = self.run_verb(
            "attachment",
            {
                "folder": "INBOX",
                "uidvalidity": first["uidvalidity"],
                "uid": invoice["uid"],
                "index": body["attachments"][0]["index"],
                "dir": self.downloads,
            },
        )
        self.assertEqual(Path(saved["path"]).read_bytes(), b"%PDF-1.4 fake")

        self.run_verb(
            "flag",
            {
                "folder": "INBOX",
                "uids": [invoice["uid"]],
                "add": ["\\Seen", "\\Flagged"],
            },
        )
        present = dict(
            (u, f)
            for u, f in self.run_verb(
                "sync",
                {
                    "folder": "INBOX",
                    "uidvalidity": first["uidvalidity"],
                    "uids": [invoice["uid"]],
                },
            )["present"]
        )
        self.assertIn("\\Flagged", present[invoice["uid"]])
        self.assertIn("\\Seen", present[invoice["uid"]])

        rich = rows["Your weekly digest"]
        self.run_verb("move", {"folder": "INBOX", "uids": [rich["uid"]], "to": "Trash"})
        after = self.run_verb(
            "sync",
            {
                "folder": "INBOX",
                "uidvalidity": first["uidvalidity"],
                "uids": [r["uid"] for r in first["rows"]],
            },
        )
        self.assertNotIn(rich["uid"], [u for u, _ in after["present"]])
        trash = self.run_verb("sync", {"folder": "Trash", "uidvalidity": 0, "uids": []})
        self.assertEqual([r["subject"] for r in trash["rows"]], ["Your weekly digest"])
        self.run_verb("delete", {"folder": "Trash", "uids": [trash["rows"][0]["uid"]]})
        self.assertEqual(
            self.run_verb("sync", {"folder": "Trash", "uidvalidity": 0, "uids": []})[
                "exists"
            ],
            0,
        )

        travel = self.run_verb(
            "sync", {"folder": "Reisen ✈", "uidvalidity": 0, "uids": []}
        )
        self.assertEqual(
            sorted(r["subject"] for r in travel["rows"]), ["Trip 0", "Trip 1", "Trip 2"]
        )

    def test_4_peek_and_send(self):
        self.run_verb("setup", self.account())
        baseline = self.run_verb("peek", {"uidvalidity": 0, "since": 0})
        self.assertEqual(baseline["rows"], [])
        conn = imaplib.IMAP4("127.0.0.1", self.port)
        conn.login(self.user, self.password)
        conn.append(
            "INBOX",
            None,
            time.time(),
            sample(
                subject="Keys are under the mat", message_id="<k@example.org>"
            ).as_bytes(),
        )
        conn.logout()
        news = self.run_verb(
            "peek",
            {"uidvalidity": baseline["uidvalidity"], "since": baseline["uidnext"]},
        )
        self.assertEqual(
            [r["subject"] for r in news["rows"]], ["Keys are under the mat"]
        )
        quiet = self.run_verb(
            "peek", {"uidvalidity": news["uidvalidity"], "since": news["uidnext"]}
        )
        self.assertEqual(quiet["rows"], [])

        inbox = self.run_verb("sync", {"folder": "INBOX", "uidvalidity": 0, "uids": []})
        invoice = next(r for r in inbox["rows"] if r["subject"] == "Invoice")
        body = self.run_verb(
            "body",
            {
                "folder": "INBOX",
                "uidvalidity": inbox["uidvalidity"],
                "uid": invoice["uid"],
            },
        )
        sent = self.run_verb(
            "send",
            {
                "to": "Jonas Weber <jonas@example.org>",
                "bcc": "me@example.test",
                "subject": "Fwd: Invoice",
                "text": "Für dich – see below.",
                "sent": "Sent",
                "forward": {
                    "folder": "INBOX",
                    "uidvalidity": inbox["uidvalidity"],
                    "uid": invoice["uid"],
                    "indexes": [a["index"] for a in body["attachments"]],
                },
            },
        )
        self.assertTrue(sent["ok"], sent)
        self.assertEqual(sent["savedTo"], "Sent")
        self.assertEqual(sent["warning"], "")
        rcpts, data = self.sink.received[-1]
        self.assertEqual(sorted(rcpts), ["jonas@example.org", "me@example.test"])
        self.assertNotIn(b"Bcc:", data)
        delivered = BytesParser(policy=policy.default).parsebytes(data)
        self.assertEqual(
            delivered.get_body(("plain",)).get_content().strip(),
            "Für dich – see below.",
        )
        self.assertEqual(
            [p.get_filename() for p in delivered.iter_attachments()], ["Invoice.pdf"]
        )

        kept = self.run_verb("sync", {"folder": "Sent", "uidvalidity": 0, "uids": []})
        self.assertEqual([r["subject"] for r in kept["rows"]], ["Fwd: Invoice"])
        self.assertIn("\\Seen", kept["rows"][0]["flags"])
        marked = dict(
            (u, f)
            for u, f in self.run_verb(
                "sync",
                {
                    "folder": "INBOX",
                    "uidvalidity": inbox["uidvalidity"],
                    "uids": [invoice["uid"]],
                },
            )["present"]
        )
        self.assertIn("$Forwarded", marked[invoice["uid"]])

        refused = self.run_verb(
            "send", {"to": "nobody@refused.test", "subject": "x", "text": "x"}
        )
        self.assertEqual(refused["kind"], "refused")
        self.assertIn("nobody@refused.test", refused["error"])

    def test_5_forget(self):
        self.run_verb("setup", self.account())
        self.run_verb("forget")
        self.assertEqual(list(Path(self.dir).iterdir()), [])
        self.assertEqual(self.run_verb("folders")["kind"], "config")


if __name__ == "__main__":
    unittest.main()
