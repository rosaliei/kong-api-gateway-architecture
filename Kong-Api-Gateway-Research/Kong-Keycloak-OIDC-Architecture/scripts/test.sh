#!/usr/bin/env bash
# End-to-end test suite for Kong-Keycloak-OIDC-Architecture on EKS.
#
# Prerequisites:
#   - Keycloak running and setup-keycloak.sh completed
#   - Kong global gateway LoadBalancer reachable
#   - jq installed
#
# Usage:
#   export KONG_HOST=$(kubectl get svc global-kic-gateway-proxy -n global-kic \
#     -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')
#   bash scripts/test.sh
set -euo pipefail

KONG_HOST="${KONG_HOST:-finance.kst-devops.com}"
KONG_URL="http://finance.kst-devops.com"

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; NC='\033[0m'
PASS=0; FAIL=0

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

status() { curl -s -o /dev/null -w "%{http_code}" -H "Host: finance.kst-devops.com" "$@"; }

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  Kong-Keycloak-OIDC-Architecture — EKS test suite"
echo "  Kong URL: ${KONG_URL}"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# ── Step 1: Keycloak reachable through Kong ────────────────────────────────────
echo ""
echo -e "${BLUE}[1/4] Keycloak access through Kong /auth route${NC}"

KC_STATUS=$(curl -s -o /dev/null -w "%{http_code}" \
  -H "Host: finance.kst-devops.com" \
  "${KONG_URL}/auth/realms/fingate")
assert "/auth/realms/fingate reachable (Keycloak behind Kong)" "200" "$KC_STATUS"

# ── Step 2: Fetch tokens from Keycloak through Kong ───────────────────────────
echo ""
echo -e "${BLUE}[2/4] Token acquisition through Kong → Keycloak${NC}"

echo -e "${YELLOW}Fetching admin token (admin-client via Kong /auth)...${NC}"
ADMIN_TOKEN=$(bash "$(dirname "$0")/get-token.sh" admin)
echo "  admin token (first 40 chars): ${ADMIN_TOKEN:0:40}..."

echo -e "${YELLOW}Fetching user token (user-client via Kong /auth)...${NC}"
USER_TOKEN=$(bash "$(dirname "$0")/get-token.sh" user)
echo "  user token (first 40 chars): ${USER_TOKEN:0:40}..."

# ── Step 3: No token → 401 on all API routes ──────────────────────────────────
echo ""
echo -e "${BLUE}[3/4] Unauthenticated requests → 401${NC}"

assert "/retail-banking  no token → 401" "401" \
  "$(status "${KONG_URL}/retail-banking")"

assert "/payments        no token → 401" "401" \
  "$(status "${KONG_URL}/payments")"

assert "/grc             no token → 401" "401" \
  "$(status "${KONG_URL}/grc")"

# ── Step 4: Admin token → 200 on all domains ──────────────────────────────────
echo ""
echo -e "${BLUE}[4/4] RBAC enforcement with Keycloak tokens${NC}"

assert "/retail-banking  admin token → 200" "200" \
  "$(status "${KONG_URL}/retail-banking" -H "Authorization: Bearer ${ADMIN_TOKEN}")"

assert "/payments        admin token → 200" "200" \
  "$(status "${KONG_URL}/payments" -H "Authorization: Bearer ${ADMIN_TOKEN}")"

assert "/grc             admin token → 200" "200" \
  "$(status "${KONG_URL}/grc" -H "Authorization: Bearer ${ADMIN_TOKEN}")"

assert "/retail-banking  user token → 200" "200" \
  "$(status "${KONG_URL}/retail-banking" -H "Authorization: Bearer ${USER_TOKEN}")"

assert "/payments        user token → 403" "403" \
  "$(status "${KONG_URL}/payments" -H "Authorization: Bearer ${USER_TOKEN}")"

assert "/grc             user token → 403" "403" \
  "$(status "${KONG_URL}/grc" -H "Authorization: Bearer ${USER_TOKEN}")"

# ── Summary ───────────────────────────────────────────────────────────────────
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
TOTAL=$((PASS + FAIL))
echo -e "Results: ${GREEN}${PASS} passed${NC}, ${RED}${FAIL} failed${NC} of ${TOTAL} tests"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
[[ $FAIL -eq 0 ]] && exit 0 || exit 1
