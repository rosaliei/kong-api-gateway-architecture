#!/usr/bin/env bash
# Self-contained Keycloak token fetcher + Kong RBAC test suite.
#
# Combines what was previously split across get-token.sh and test.sh:
#   - get_token admin   → returns admin-client JWT
#   - get_token user    → returns user-client JWT
#   - then runs the full end-to-end test suite using those tokens
#
# Prerequisites:
#   - Keycloak running and setup-keycloak.sh completed
#   - Kong global gateway LoadBalancer reachable
#   - jq, curl installed
#
# Usage:
#   bash scripts/token-and-test.sh                       # run full test suite
#   bash scripts/token-and-test.sh token admin           # print admin JWT only
#   bash scripts/token-and-test.sh token user            # print user JWT only
#   KONG_HOST=finance.kst-devops.com bash scripts/token-and-test.sh
set -euo pipefail

# ── Config ────────────────────────────────────────────────────────────────────
KONG_HOST="${KONG_HOST:-ae101372d75884ebcb3928c69b7405db-1934850503.ap-southeast-1.elb.amazonaws.com}"
HOST_HEADER="${HOST_HEADER:-finance.kst-devops.com}"
KONG_URL="http://${KONG_HOST}"
KC_REALM="fingate"
TOKEN_URL="${KONG_URL}/auth/realms/${KC_REALM}/protocol/openid-connect/token"

ADMIN_CLIENT_ID="admin-client"
ADMIN_CLIENT_SECRET="admin-client-secret-2024"
USER_CLIENT_ID="user-client"
USER_CLIENT_SECRET="user-client-secret-2024"

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; NC='\033[0m'
PASS=0; FAIL=0

# ── Token helper ──────────────────────────────────────────────────────────────
# get_token admin|user  → prints the access_token JWT to stdout.
# Uses client_credentials grant → Keycloak returns access_token only (no id_token).
get_token() {
  local role="${1:-admin}" client_id client_secret response jwt
  case "$role" in
    admin) client_id="$ADMIN_CLIENT_ID"; client_secret="$ADMIN_CLIENT_SECRET" ;;
    user)  client_id="$USER_CLIENT_ID";  client_secret="$USER_CLIENT_SECRET"  ;;
    *) echo "Usage: get_token admin|user" >&2; return 1 ;;
  esac

  response=$(curl -sf \
    -d "client_id=${client_id}" \
    -d "client_secret=${client_secret}" \
    -d "grant_type=client_credentials" \
    -H "Host: ${HOST_HEADER}" \
    "$TOKEN_URL")

  jwt=$(echo "$response" | jq -r '.access_token')
  if [[ -z "$jwt" || "$jwt" == "null" ]]; then
    echo "ERROR: failed to obtain ${role} token" >&2
    echo "$response" >&2
    return 1
  fi
  echo "$jwt"
}

# ── Subcommand: print token only ──────────────────────────────────────────────
if [[ "${1:-}" == "token" ]]; then
  get_token "${2:-admin}"
  exit 0
fi

# ── Test helpers ──────────────────────────────────────────────────────────────
assert() {
  local label="$1" expected="$2" actual="$3"
  if [[ "$actual" == "$expected" ]]; then
    echo -e "${GREEN}PASS${NC} $label (HTTP $actual)"
    ((PASS++)) || true
  else
    echo -e "${RED}FAIL${NC} $label — expected $expected, got $actual"
    ((FAIL++)) || true
  fi
}

status() { curl -s -o /dev/null -w "%{http_code}" -H "Host: ${HOST_HEADER}" "$@"; }

# ── Test suite ────────────────────────────────────────────────────────────────
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  Kong-Keycloak-OIDC-Architecture — EKS test suite"
echo "  Kong URL: ${KONG_URL}"
echo "  Host:     ${HOST_HEADER}"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# [1/4] Keycloak reachable through Kong
echo ""
echo -e "${BLUE}[1/4] Keycloak access through Kong /auth route${NC}"
KC_STATUS=$(status "${KONG_URL}/auth/realms/${KC_REALM}")
assert "/auth/realms/${KC_REALM} reachable (Keycloak behind Kong)" "200" "$KC_STATUS"

# [2/4] Fetch tokens
echo ""
echo -e "${BLUE}[2/4] Token acquisition through Kong → Keycloak${NC}"
echo -e "${YELLOW}Fetching admin token (admin-client)...${NC}"
ADMIN_TOKEN=$(get_token admin)
echo "  admin token (first 40 chars): ${ADMIN_TOKEN:0:40}..."

echo -e "${YELLOW}Fetching user token (user-client)...${NC}"
USER_TOKEN=$(get_token user)
echo "  user token  (first 40 chars): ${USER_TOKEN:0:40}..."

# [3/4] No token → 401
echo ""
echo -e "${BLUE}[3/4] Unauthenticated requests → 401${NC}"
assert "/retail-banking  no token → 401" "401" "$(status "${KONG_URL}/retail-banking")"
assert "/payments        no token → 401" "401" "$(status "${KONG_URL}/payments")"
assert "/grc             no token → 401" "401" "$(status "${KONG_URL}/grc")"

# [4/4] RBAC with tokens
echo ""
echo -e "${BLUE}[4/4] RBAC enforcement with Keycloak tokens${NC}"
assert "/retail-banking  admin token → 200" "200" \
  "$(status "${KONG_URL}/retail-banking" -H "Authorization: Bearer ${ADMIN_TOKEN}")"
assert "/payments        admin token → 200" "200" \
  "$(status "${KONG_URL}/payments"       -H "Authorization: Bearer ${ADMIN_TOKEN}")"
assert "/grc             admin token → 200" "200" \
  "$(status "${KONG_URL}/grc"             -H "Authorization: Bearer ${ADMIN_TOKEN}")"

assert "/retail-banking  user token  → 200" "200" \
  "$(status "${KONG_URL}/retail-banking" -H "Authorization: Bearer ${USER_TOKEN}")"
assert "/payments        user token  → 403" "403" \
  "$(status "${KONG_URL}/payments"       -H "Authorization: Bearer ${USER_TOKEN}")"
assert "/grc             user token  → 403" "403" \
  "$(status "${KONG_URL}/grc"             -H "Authorization: Bearer ${USER_TOKEN}")"

# ── Summary ───────────────────────────────────────────────────────────────────
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
TOTAL=$((PASS + FAIL))
echo -e "Results: ${GREEN}${PASS} passed${NC}, ${RED}${FAIL} failed${NC} of ${TOTAL} tests"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
[[ $FAIL -eq 0 ]] && exit 0 || exit 1
