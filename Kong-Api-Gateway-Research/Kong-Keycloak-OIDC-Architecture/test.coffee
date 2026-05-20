Step 0 — Set your Kong host

export KONG_HOST=ae101372d75884ebcb3928c69b7405db-1934850503.ap-southeast-1.elb.amazonaws.com
Step 1 — Get the ADMIN token

curl -s -X POST \
  -H "Host: finance.kst-devops.com" \
  -d "client_id=admin-client" \
  -d "client_secret=admin-client-secret-2024" \
  -d "grant_type=client_credentials" \
  "http://${KONG_HOST}/auth/realms/fingate/protocol/openid-connect/token" | jq .
Save it into a variable:


ADMIN_TOKEN=$(curl -s -X POST \
  -H "Host: finance.kst-devops.com" \
  -d "client_id=admin-client" \
  -d "client_secret=admin-client-secret-2024" \
  -d "grant_type=client_credentials" \
  "http://${KONG_HOST}/auth/realms/fingate/protocol/openid-connect/token" | jq -r .access_token)

echo "$ADMIN_TOKEN"
Step 2 — Get the USER token

USER_TOKEN=$(curl -s -X POST \
  -H "Host: finance.kst-devops.com" \
  -d "client_id=user-client" \
  -d "client_secret=user-client-secret-2024" \
  -d "grant_type=client_credentials" \
  "http://${KONG_HOST}/auth/realms/fingate/protocol/openid-connect/token" | jq -r .access_token)

echo "$USER_TOKEN"
Step 3 — No token → expect 401

curl -i -H "Host: finance.kst-devops.com" "http://${KONG_HOST}/retail-banking"
curl -i -H "Host: finance.kst-devops.com" "http://${KONG_HOST}/payments"
curl -i -H "Host: finance.kst-devops.com" "http://${KONG_HOST}/grc"
Step 4 — ADMIN token → expect 200 on all three

curl -i -H "Host: finance.kst-devops.com" -H "Authorization: Bearer ${ADMIN_TOKEN}" "http://${KONG_HOST}/retail-banking"
curl -i -H "Host: finance.kst-devops.com" -H "Authorization: Bearer ${ADMIN_TOKEN}" "http://${KONG_HOST}/payments"
curl -i -H "Host: finance.kst-devops.com" -H "Authorization: Bearer ${ADMIN_TOKEN}" "http://${KONG_HOST}/grc"
Step 5 — USER token → 200 on retail-banking, 403 on payments/grc

curl -i -H "Host: finance.kst-devops.com" -H "Authorization: Bearer ${USER_TOKEN}" "http://${KONG_HOST}/retail-banking"
curl -i -H "Host: finance.kst-devops.com" -H "Authorization: Bearer ${USER_TOKEN}" "http://${KONG_HOST}/payments"
curl -i -H "Host: finance.kst-devops.com" -H "Authorization: Bearer ${USER_TOKEN}" "http://${KONG_HOST}/grc"

Expected RBAC matrix
Route	no token	admin	user
/retail-banking	401	200	200
/payments	401	200	403
/grc	401	200	403
