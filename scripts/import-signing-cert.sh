#!/bin/bash
# Import the shared release signing identity so local builds keep the same
# code signature as CI builds (and therefore the same Accessibility grant).
# Usage: scripts/import-signing-cert.sh path/to/space-release.p12 <password>
set -euo pipefail

P12="${1:?p12 path}"
PASSWORD="${2:?p12 password}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
KEYCHAIN="${HOME}/Library/Keychains/login.keychain-db"

security import "$P12" -k "$KEYCHAIN" -P "$PASSWORD" -A -T /usr/bin/codesign -T /usr/bin/security
security add-trusted-cert -d -r trustRoot -p codeSign -k "$KEYCHAIN" "$ROOT/signing/space-release.crt"
echo "Imported: SPACE Release Signing. build.sh will pick it up automatically."
