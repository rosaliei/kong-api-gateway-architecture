# FinGate-RBAC — Manual Test Guide
### Kong Finance Gateway: Global JWT + Role-Based ACL on AWS EKS

## Prerequisites

```bash
# Set Kong host (get from LoadBalancer)
export KONG_HOST=$(kubectl get svc global-kic-gateway-proxy -n global-kic \
  -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')

echo $KONG_HOST   # verify it is set
```

---

## Step 2 — Generate Tokens

```bash
ADMIN_TOKEN=$(bash scripts/generate-token.sh admin)
USER_TOKEN=$(bash scripts/generate-token.sh user)
```

What is inside each token (decoded payload):

```
admin token:  { "iss": "admin-issuer", "sub": "admin-subject", exp: now+1h }
user token:   { "iss": "user-issuer",  "sub": "user-subject",  exp: now+1h }
```

Kong matches `iss` value against the `key` field in the JWT k8s secret
to identify which consumer is making the request.

---

## Step 3 — How Kong Checks the Request

```
Client sends:   Authorization: Bearer <JWT>
                Host: finance.kst-devops.com

Kong does:
  1. JWT Plugin   → decode token → verify RS256 signature using public key in k8s secret
                  → read "iss" claim → identify consumer (admin or user)
  2. ACL Plugin   → lookup consumer's group from ACL secret
                  → compare group against plugin allow list for this route
  3. Decision     → allow (200) or deny (401 / 403)
```

---

## Step 4 — Curl Tests

### No token — expect 401 on all routes

```bash
curl -s -o /dev/null -w "%{http_code}" \
  -H "Host: finance.kst-devops.com" \
  http://$KONG_HOST/retail-banking
# → 401

curl -s -o /dev/null -w "%{http_code}" \
  -H "Host: finance.kst-devops.com" \
  http://$KONG_HOST/payments
# → 401

curl -s -o /dev/null -w "%{http_code}" \
  -H "Host: finance.kst-devops.com" \
  http://$KONG_HOST/grc
# → 401
```

---

### Admin token — expect 200 on all routes

```bash
curl -s -o /dev/null -w "%{http_code}" \
  -H "Host: finance.kst-devops.com" \
  -H "Authorization: Bearer $ADMIN_TOKEN" \
  http://$KONG_HOST/retail-banking
# → 200

curl -s -o /dev/null -w "%{http_code}" \
  -H "Host: finance.kst-devops.com" \
  -H "Authorization: Bearer $ADMIN_TOKEN" \
  http://$KONG_HOST/payments
# → 200

curl -s -o /dev/null -w "%{http_code}" \
  -H "Host: finance.kst-devops.com" \
  -H "Authorization: Bearer $ADMIN_TOKEN" \
  http://$KONG_HOST/grc
# → 200
```

---

### User token — expect 200 on retail-banking, 403 on payments and grc

```bash
curl -s -o /dev/null -w "%{http_code}" \
  -H "Host: finance.kst-devops.com" \
  -H "Authorization: Bearer $USER_TOKEN" \
  http://$KONG_HOST/retail-banking
# → 200

curl -s -o /dev/null -w "%{http_code}" \
  -H "Host: finance.kst-devops.com" \
  -H "Authorization: Bearer $USER_TOKEN" \
  http://$KONG_HOST/payments
# → 403

curl -s -o /dev/null -w "%{http_code}" \
  -H "Host: finance.kst-devops.com" \
  -H "Authorization: Bearer $USER_TOKEN" \
  http://$KONG_HOST/grc
# → 403
```

---

## Step 5 — Expected Results Summary

| Consumer | Token | /retail-banking | /payments | /grc |
|----------|-------|-----------------|-----------|------|
| none     | none  | 401             | 401       | 401  |
| admin    | RS256 | 200             | 200       | 200  |
| user     | RS256 | 200             | 403       | 403  |

---

## Step 6 — Run Full Automated Test Suite

```bash
bash scripts/test.sh
# Expected: Results: 9 passed, 0 failed of 9 tests
```

---

## Quick Reference — Headers Kong Looks At

| Header | Purpose | Example |
|--------|---------|---------|
| `Host` | routes request to correct HTTPRoute listener | `finance.kst-devops.com` |
| `Authorization` | carries the JWT for identity + ACL check | `Bearer eyJ...` |

No other headers are required. Kong reads everything it needs from these two.
