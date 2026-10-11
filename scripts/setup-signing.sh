#!/usr/bin/env bash
# Creates a self-signed code-signing identity in the login keychain so that
# rebuilt copies of DeskSwipe keep the same code signature identity, and
# macOS keeps the Accessibility permission across rebuilds.
#
# Local only: the certificate is not trusted by anyone else and grants no
# extra privileges. Remove it any time with Keychain Access (search for the
# name below); build.sh then falls back to ad-hoc signing.
set -euo pipefail

NAME="DeskSwipe Local Signing"
KEYCHAIN="$HOME/Library/Keychains/login.keychain-db"

if security find-certificate -c "$NAME" "$KEYCHAIN" >/dev/null 2>&1; then
    echo "\"$NAME\" already exists in the login keychain. Nothing to do."
    exit 0
fi

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
PASS="$(openssl rand -hex 16)"

cat > "$WORK/cert.cnf" <<CNF
[req]
distinguished_name = dn
x509_extensions = ext
prompt = no
[dn]
CN = $NAME
[ext]
basicConstraints = critical, CA:false
keyUsage = critical, digitalSignature
extendedKeyUsage = critical, codeSigning
CNF

openssl req -x509 -newkey rsa:2048 -nodes -days 3650 \
    -config "$WORK/cert.cnf" -keyout "$WORK/key.pem" -out "$WORK/cert.pem" 2>/dev/null
openssl pkcs12 -export -inkey "$WORK/key.pem" -in "$WORK/cert.pem" \
    -name "$NAME" -out "$WORK/identity.p12" -passout "pass:$PASS"

# -T lets codesign use the key without a keychain prompt.
security import "$WORK/identity.p12" -k "$KEYCHAIN" -P "$PASS" -T /usr/bin/codesign >/dev/null

echo "Created \"$NAME\" in the login keychain."
echo "Run ./build.sh; macOS will ask for Accessibility once more, then keep it across rebuilds."
