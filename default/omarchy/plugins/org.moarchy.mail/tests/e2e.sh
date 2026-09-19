#!/bin/bash
# moarchy-mail against a real IMAP server, in the moarchy-qml container.
#
#   docker run --rm --platform linux/arm64 -v "$PWD:/src" -w /src moarchy-qml \
#       plugins/org.moarchy.mail/tests/e2e.sh
#
# Dovecot is installed here rather than in docker/Dockerfile.qml, because
# nothing else needs a mail server and the image is every plugin's. It listens
# twice: plain on 1143, for the conversations, and TLS on 1993 with a
# certificate from a CA made on the spot -- so the test can trust that CA for
# one run and not for another, and see both the handshake and the refusal.
#
# SMTP is not Dovecot's. test_moarchy_mail.py runs a small server of its own,
# which keeps every message it accepts for the test to read back.
set -euo pipefail
cd "$(dirname "$0")"

if ! command -v dovecot >/dev/null; then
  pacman -Sy --noconfirm --needed dovecot openssl >/dev/null
fi

W=$(mktemp -d)
# Dovecot's auth process runs as dovecot and reads the users file from here.
chmod 755 "$W"
useradd -M mailer 2>/dev/null || true
mkdir -p "$W/run" "$W/mail"
chown mailer:mailer "$W/mail"

# Python's default context verifies strictly (VERIFY_X509_STRICT since 3.13),
# so the CA says it is one and the server certificate says what it is for --
# a bare `req -x509` is refused with "CA cert does not include key usage".
openssl req -x509 -newkey rsa:2048 -nodes -days 1 -subj "/CN=moarchy test CA" \
  -addext "basicConstraints=critical,CA:TRUE" -addext "keyUsage=critical,keyCertSign,cRLSign" \
  -keyout "$W/ca.key" -out "$W/ca.pem" >/dev/null 2>&1
openssl req -newkey rsa:2048 -nodes -subj "/CN=localhost" \
  -keyout "$W/server.key" -out "$W/server.csr" >/dev/null 2>&1
printf '%s\n' "subjectAltName=DNS:localhost" "keyUsage=critical,digitalSignature,keyEncipherment" \
  "extendedKeyUsage=serverAuth" "authorityKeyIdentifier=keyid" >"$W/san.ext"
openssl x509 -req -in "$W/server.csr" -CA "$W/ca.pem" -CAkey "$W/ca.key" -CAcreateserial \
  -days 1 -extfile "$W/san.ext" -out "$W/server.pem" >/dev/null 2>&1
chmod 644 "$W/server.key"

printf 'ada:{PLAIN}secret pass::::::\n' >"$W/users"

cat >"$W/dovecot.conf" <<CONF
dovecot_config_version = 2.4.0
dovecot_storage_version = 2.4.0
protocols = imap
listen = 127.0.0.1
base_dir = $W/run
log_path = $W/dovecot.log
auth_allow_cleartext = yes
ssl = yes
ssl_server_cert_file = $W/server.pem
ssl_server_key_file = $W/server.key
mail_driver = maildir
mail_path = ~/Maildir
mail_uid = mailer
mail_gid = mailer
first_valid_uid = 1
passdb passwd-file {
  passwd_file_path = $W/users
}
userdb static {
  fields {
    home = $W/mail/%{user}
  }
}
service imap-login {
  inet_listener imap {
    port = 1143
  }
  inet_listener imaps {
    port = 1993
    ssl = yes
  }
}
namespace inbox {
  inbox = yes
  separator = /
  mailbox Sent {
    special_use = "\\\\Sent"
    auto = create
  }
  mailbox Trash {
    special_use = "\\\\Trash"
    auto = create
  }
  mailbox Drafts {
    special_use = "\\\\Drafts"
    auto = create
  }
}
CONF

dovecot -c "$W/dovecot.conf"
trap 'doveadm -c "$W/dovecot.conf" stop >/dev/null 2>&1 || true; rm -rf "$W"' EXIT
for _ in $(seq 40); do
  (exec 3<>/dev/tcp/127.0.0.1/1143) 2>/dev/null && break
  sleep 0.25
done

MOARCHY_MAIL_IMAP_PORT=1143 MOARCHY_MAIL_IMAPS_PORT=1993 MOARCHY_MAIL_CA="$W/ca.pem" \
  python3 -m unittest -v test_moarchy_mail 2>&1 || { tail -20 "$W/dovecot.log"; exit 1; }
