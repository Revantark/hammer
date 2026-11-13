#!/bin/bash
# Creates a stable local code-signing identity so macOS permissions (Accessibility) survive rebuilds.
# Uses an existing "Apple Development" identity if you have one. Idempotent.
set -euo pipefail
NAME="Hammer Local Signing"

if security find-identity -p codesigning | grep -q "Apple Development"; then
    security find-identity -p codesigning | grep "Apple Development" | head -1 | sed -E 's/.*"(.*)"/\1/'
    exit 0
fi
if security find-identity -p codesigning | grep -q "\"$NAME\""; then
    echo "$NAME"
    exit 0
fi

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
cat > "$TMP/cert.cnf" <<CNF
[req]
distinguished_name = dn
x509_extensions = ext
prompt = no
[dn]
CN = $NAME
[ext]
keyUsage = critical, digitalSignature
extendedKeyUsage = critical, codeSigning
basicConstraints = critical, CA:false
CNF
openssl req -x509 -newkey rsa:2048 -nodes -days 3650 -keyout "$TMP/key.pem" -out "$TMP/cert.pem" -config "$TMP/cert.cnf" 2>/dev/null
PASS="hammer-$RANDOM$RANDOM"
LEGACY=""
openssl version | grep -q "^OpenSSL 3" && LEGACY="-legacy"
openssl pkcs12 -export $LEGACY -inkey "$TMP/key.pem" -in "$TMP/cert.pem" -name "$NAME" -out "$TMP/id.p12" -passout "pass:$PASS"
security import "$TMP/id.p12" -k "$HOME/Library/Keychains/login.keychain-db" -P "$PASS" -T /usr/bin/codesign >/dev/null
echo "$NAME"
