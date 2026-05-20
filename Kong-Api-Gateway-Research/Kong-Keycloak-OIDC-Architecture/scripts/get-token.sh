#!/usr/bin/env bash
# Fetches a Keycloak JWT through the Kong /auth route using client_credentials grant.
#
# Usage:
#   bash scripts/get-token.sh admin          # token for admin-client
#   bash scripts/get-token.sh user           # token for user-client
#   KONG_HOST=finance.kst-devops.com bash scripts/get-token.sh admin
#
# Output: prints the raw JWT to stdout so it can be captured:
#   TOKEN=$(bash scripts/get-token.sh admin)
set -euo pipefail

ROLE="${1:-admin}"
KONG_HOST="${KONG_HOST:-ae101372d75884ebcb3928c69b7405db-1934850503.ap-southeast-1.elb.amazonaws.com}"
KC_REALM="fingate"
TOKEN_URL="http://${KONG_HOST}/auth/realms/${KC_REALM}/protocol/openid-connect/token"

case "$ROLE" in
  admin)
    CLIENT_ID="admin-client"
    CLIENT_SECRET="admin-client-secret-2024"
    ;;
  user)
    CLIENT_ID="user-client"
    CLIENT_SECRET="user-client-secret-2024"
    ;;
  *)
    echo "Usage: $0 admin|user" >&2
    exit 1
    ;;
esac

# client_credentials grant — Keycloak issues a JWT with azp=<CLIENT_ID>
# Kong's jwt plugin reads azp to look up the matching KongConsumer.
RESPONSE=$(curl -sf \
  -d "client_id=${CLIENT_ID}" \
  -d "client_secret=${CLIENT_SECRET}" \
  -d "grant_type=client_credentials" \
  -H "Host: finance.kst-devops.com" \
  "$TOKEN_URL")

JWT=$(echo "$RESPONSE" | jq -r '.access_token')

if [[ -z "$JWT" || "$JWT" == "null" ]]; then
  echo "ERROR: failed to obtain token from Keycloak" >&2
  echo "$RESPONSE" >&2
  exit 1
fi

echo "$JWT"
