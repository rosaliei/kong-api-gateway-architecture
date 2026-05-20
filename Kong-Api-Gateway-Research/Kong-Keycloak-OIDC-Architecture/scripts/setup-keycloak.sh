#!/usr/bin/env bash
# Sets up the Keycloak realm, clients, and Kong JWT credentials.
#
# What it does:
#   1. Port-forwards to Keycloak through kubectl (or uses KEYCLOAK_URL if set)
#   2. Creates realm "fingate"
#   3. Creates clients: admin-client (admin access) and user-client (user access)
#   4. Fetches the realm RS256 public key from Keycloak's JWKS endpoint
#   5. Creates Kong JWT Secrets in global-api-gateway-ns for each client
#
# Prerequisites:
#   - kubectl configured against the target EKS cluster
#   - Keycloak pod running in keycloak-ns
#   - jq installed
#
# Usage:
#   bash scripts/setup-keycloak.sh
set -euo pipefail

KC_ADMIN_USER="admin"
KC_ADMIN_PASS="Admin@FinGate2024"  # must match keycloak-admin-secret in 03-keycloak-deployment.yaml
KC_REALM="fingate"
KC_NS="keycloak-ns"
KONG_NS="global-api-gateway-ns"

# ── Resolve Keycloak URL ───────────────────────────────────────────────────────
if [[ -z "${KEYCLOAK_URL:-}" ]]; then
  echo "No KEYCLOAK_URL set — starting kubectl port-forward on localhost:8090 ..."
  kubectl port-forward -n "$KC_NS" svc/keycloak 8090:8080 &
  PF_PID=$!
  trap "kill $PF_PID 2>/dev/null || true" EXIT
  sleep 4
  KC_URL="http://localhost:8090/auth"
else
  KC_URL="${KEYCLOAK_URL}/auth"
fi

echo "Keycloak URL: $KC_URL"

# ── Get admin access token ─────────────────────────────────────────────────────
echo ""
echo ">>> Authenticating as Keycloak admin ..."
ADMIN_TOKEN=$(curl -sf \
  -d "client_id=admin-cli" \
  -d "username=${KC_ADMIN_USER}" \
  -d "password=${KC_ADMIN_PASS}" \
  -d "grant_type=password" \
  "${KC_URL}/realms/master/protocol/openid-connect/token" \
  | jq -r '.access_token')

KC_HDR="Authorization: Bearer ${ADMIN_TOKEN}"

# ── Create realm ───────────────────────────────────────────────────────────────
echo ">>> Creating realm: ${KC_REALM} ..."
curl -sf -o /dev/null \
  -H "$KC_HDR" \
  -H "Content-Type: application/json" \
  -X POST "${KC_URL}/admin/realms" \
  -d "{
    \"realm\": \"${KC_REALM}\",
    \"enabled\": true,
    \"displayName\": \"FinGate\",
    \"accessTokenLifespan\": 3600
  }" || echo "  (realm may already exist — continuing)"

# ── Create admin-client ────────────────────────────────────────────────────────
echo ">>> Creating client: admin-client ..."
curl -sf -o /dev/null \
  -H "$KC_HDR" \
  -H "Content-Type: application/json" \
  -X POST "${KC_URL}/admin/realms/${KC_REALM}/clients" \
  -d '{
    "clientId": "admin-client",
    "enabled": true,
    "protocol": "openid-connect",
    "publicClient": false,
    "serviceAccountsEnabled": true,
    "directAccessGrantsEnabled": true,
    "secret": "admin-client-secret-2024"
  }' || echo "  (admin-client may already exist — continuing)"

# ── Create user-client ─────────────────────────────────────────────────────────
echo ">>> Creating client: user-client ..."
curl -sf -o /dev/null \
  -H "$KC_HDR" \
  -H "Content-Type: application/json" \
  -X POST "${KC_URL}/admin/realms/${KC_REALM}/clients" \
  -d '{
    "clientId": "user-client",
    "enabled": true,
    "protocol": "openid-connect",
    "publicClient": false,
    "serviceAccountsEnabled": true,
    "directAccessGrantsEnabled": true,
    "secret": "user-client-secret-2024"
  }' || echo "  (user-client may already exist — continuing)"

# ── Fetch realm RS256 public key ───────────────────────────────────────────────
echo ">>> Fetching realm RS256 public key ..."
RAW_KEY=$(curl -sf "${KC_URL}/realms/${KC_REALM}" | jq -r '.public_key')

# Keycloak returns the key without PEM headers — wrap it for Kong.
REALM_PUBLIC_KEY="-----BEGIN PUBLIC KEY-----
$(echo "$RAW_KEY" | fold -w 64)
-----END PUBLIC KEY-----"

echo ""
echo "Realm public key (first 60 chars): ${RAW_KEY:0:60}..."

# ── Create Kong JWT Secrets ────────────────────────────────────────────────────
# Both consumers share the same Keycloak realm signing key.
# Kong's jwt plugin uses key_claim_name=azp to distinguish consumers by client_id.

echo ""
echo ">>> Creating Kong JWT Secret: admin-jwt (key=admin-client) ..."
kubectl create secret generic admin-jwt \
  --namespace "$KONG_NS" \
  --from-literal=kongCredType=jwt \
  --from-literal=key=admin-client \
  --from-literal=algorithm=RS256 \
  --from-literal=rsa_public_key="${REALM_PUBLIC_KEY}" \
  --dry-run=client -o yaml \
  | kubectl label --local -f - konghq.com/credential=jwt -o yaml \
  | kubectl apply -f -

echo ">>> Creating Kong JWT Secret: user-jwt (key=user-client) ..."
kubectl create secret generic user-jwt \
  --namespace "$KONG_NS" \
  --from-literal=kongCredType=jwt \
  --from-literal=key=user-client \
  --from-literal=algorithm=RS256 \
  --from-literal=rsa_public_key="${REALM_PUBLIC_KEY}" \
  --dry-run=client -o yaml \
  | kubectl label --local -f - konghq.com/credential=jwt -o yaml \
  | kubectl apply -f -

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  Keycloak setup complete."
echo ""
echo "  Realm:         fingate"
echo "  Admin client:  admin-client  /  secret: admin-client-secret-2024"
echo "  User client:   user-client   /  secret: user-client-secret-2024"
echo ""
echo "  Next: run scripts/get-token.sh admin|user to get a Keycloak JWT"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
