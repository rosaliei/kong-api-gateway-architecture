#!/usr/bin/env bash
# End-to-end tests for Kong-Solution-6 on EKS.
# Set KONG_HOST to the global Kong LB hostname before running:
#   export KONG_HOST=<global-kic-lb-hostname>
#   bash scripts/test.sh
set -euo pipefail

KONG_HOST="${KONG_HOST:-finance.kst-devops.com}"
KONG_URL="http://${KONG_HOST}"

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'
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
echo "  Kong-Solution-6 — EKS end-to-end tests"
echo "  Kong URL: ${KONG_URL}"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

echo -e "${YELLOW}Generating JWTs...${NC}"
ADMIN_TOKEN=$(bash "$(dirname "$0")/generate-token.sh" admin)
USER_TOKEN=$(bash "$(dirname "$0")/generate-token.sh" user)
echo "Admin and user tokens ready."
echo ""

# ── No token → 401 on all domains ─────────────────────────────────────────────
assert "/retail-banking  no token → 401" "401" \
  "$(status "${KONG_URL}/retail-banking")"

assert "/payments        no token → 401" "401" \
  "$(status "${KONG_URL}/payments")"

assert "/grc             no token → 401" "401" \
  "$(status "${KONG_URL}/grc")"

# ── Admin token → 200 on all domains ──────────────────────────────────────────
assert "/retail-banking  admin token → 200" "200" \
  "$(status "${KONG_URL}/retail-banking" -H "Authorization: Bearer ${ADMIN_TOKEN}")"

assert "/payments        admin token → 200" "200" \
  "$(status "${KONG_URL}/payments" -H "Authorization: Bearer ${ADMIN_TOKEN}")"

assert "/grc             admin token → 200" "200" \
  "$(status "${KONG_URL}/grc" -H "Authorization: Bearer ${ADMIN_TOKEN}")"

# ── User token → 200 on retail-banking, 403 on payments and grc ───────────────
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
