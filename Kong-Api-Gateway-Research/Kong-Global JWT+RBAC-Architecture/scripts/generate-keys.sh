#!/usr/bin/env bash
# Generates separate RSA-2048 keypairs for admin and user consumers.
# Private keys: sign JWTs (keep secret, never commit).
# Public keys: loaded into Kong via k8s secrets for signature verification.
set -euo pipefail

KEYS_DIR="$(cd "$(dirname "$0")/.." && pwd)/keys"
mkdir -p "$KEYS_DIR"

generate_keypair() {
  local name="$1"
  echo "Generating RSA-2048 keypair for: $name"
  openssl genrsa -out "${KEYS_DIR}/${name}-private.pem" 2048 2>/dev/null
  openssl rsa -in "${KEYS_DIR}/${name}-private.pem" \
              -pubout \
              -out "${KEYS_DIR}/${name}-public.pem" 2>/dev/null
  echo "  Private key: keys/${name}-private.pem  (DO NOT COMMIT)"
  echo "  Public key:  keys/${name}-public.pem   (goes into k8s secret)"
}

generate_keypair "admin"
generate_keypair "user"

echo ""
echo "Done. Apply k8s secrets (namespace: global-api-gateway-ns):"
echo ""
echo "  kubectl create secret generic admin-jwt -n global-api-gateway-ns \\"
echo "    --from-literal=kongCredType=jwt \\"
echo "    --from-literal=key=admin-issuer \\"
echo "    --from-literal=algorithm=RS256 \\"
echo "    --from-literal=rsa_public_key=\"\$(cat keys/admin-public.pem)\" \\"
echo "    --dry-run=client -o yaml \\"
echo "    | kubectl label --local -f - konghq.com/credential=jwt -o yaml \\"
echo "    | kubectl apply -f -"
echo ""
echo "  kubectl create secret generic user-jwt -n global-api-gateway-ns \\"
echo "    --from-literal=kongCredType=jwt \\"
echo "    --from-literal=key=user-issuer \\"
echo "    --from-literal=algorithm=RS256 \\"
echo "    --from-literal=rsa_public_key=\"\$(cat keys/user-public.pem)\" \\"
echo "    --dry-run=client -o yaml \\"
echo "    | kubectl label --local -f - konghq.com/credential=jwt -o yaml \\"
echo "    | kubectl apply -f -"
