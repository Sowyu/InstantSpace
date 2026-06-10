#!/bin/bash
set -euo pipefail

CERT_NAME="${1:-SPACE Local Code Signing}"
KEYCHAIN="${HOME}/Library/Keychains/login.keychain-db"
TMP_DIR="$(mktemp -d)"
P12_PASSWORD="space-local-signing"

cleanup() {
  rm -rf "$TMP_DIR"
}
trap cleanup EXIT

if security find-identity -v -p codesigning | grep -q "\"$CERT_NAME\""; then
  echo "Code-signing identity already exists: $CERT_NAME"
  exit 0
fi

OPENSSL_CONFIG="$TMP_DIR/openssl.cnf"
cat >"$OPENSSL_CONFIG" <<EOF
[req]
distinguished_name = req_distinguished_name
x509_extensions = v3_req
prompt = no

[req_distinguished_name]
CN = $CERT_NAME

[v3_req]
keyUsage = critical, digitalSignature
extendedKeyUsage = codeSigning
basicConstraints = critical, CA:true
subjectKeyIdentifier = hash
EOF

openssl req \
  -new \
  -newkey rsa:2048 \
  -nodes \
  -x509 \
  -days 3650 \
  -config "$OPENSSL_CONFIG" \
  -keyout "$TMP_DIR/cert.key" \
  -out "$TMP_DIR/cert.crt"

openssl pkcs12 \
  -export \
  -legacy \
  -inkey "$TMP_DIR/cert.key" \
  -in "$TMP_DIR/cert.crt" \
  -out "$TMP_DIR/cert.p12" \
  -passout "pass:$P12_PASSWORD"

security import "$TMP_DIR/cert.p12" \
  -k "$KEYCHAIN" \
  -P "$P12_PASSWORD" \
  -A \
  -T /usr/bin/codesign \
  -T /usr/bin/security

security add-trusted-cert \
  -d \
  -r trustRoot \
  -p codeSign \
  -k "$KEYCHAIN" \
  "$TMP_DIR/cert.crt"

echo "Created code-signing identity: $CERT_NAME"
echo "Future builds will use it automatically."
