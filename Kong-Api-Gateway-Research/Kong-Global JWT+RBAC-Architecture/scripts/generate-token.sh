#!/usr/bin/env bash
# Generates a signed RS256 JWT for testing Kong.
# Usage:
#   bash scripts/generate-token.sh admin   → signs with keys/admin-private.pem, iss=admin-issuer
#   bash scripts/generate-token.sh user    → signs with keys/user-private.pem,  iss=user-issuer
#
# Requires: openssl, python3 (stdlib only)
set -euo pipefail

CONSUMER="${1:-admin}"
KEYS_DIR="$(cd "$(dirname "$0")/.." && pwd)/keys"
PRIVATE_KEY="${KEYS_DIR}/${CONSUMER}-private.pem"

if [[ ! -f "$PRIVATE_KEY" ]]; then
  echo "ERROR: ${PRIVATE_KEY} not found. Run scripts/generate-keys.sh first."
  exit 1
fi

python3 - "$CONSUMER" "$PRIVATE_KEY" <<'EOF'
import sys, json, base64, time
from pathlib import Path

consumer = sys.argv[1]
private_key_path = sys.argv[2]

header = {"alg": "RS256", "typ": "JWT"}
payload = {
    "iss": f"{consumer}-issuer",
    "sub": f"{consumer}-subject",
    "iat": int(time.time()),
    "exp": int(time.time()) + 3600,
}

def b64url(data):
    if isinstance(data, dict):
        data = json.dumps(data, separators=(",", ":")).encode()
    return base64.urlsafe_b64encode(data).rstrip(b"=").decode()

signing_input = f"{b64url(header)}.{b64url(payload)}"

import subprocess, tempfile, os
with tempfile.NamedTemporaryFile(mode="w", suffix=".txt", delete=False) as f:
    f.write(signing_input)
    tmp = f.name

try:
    sig_der = subprocess.check_output(
        ["openssl", "dgst", "-sha256", "-sign", private_key_path, tmp]
    )
finally:
    os.unlink(tmp)

sig = base64.urlsafe_b64encode(sig_der).rstrip(b"=").decode()
token = f"{signing_input}.{sig}"
print(token)
EOF
