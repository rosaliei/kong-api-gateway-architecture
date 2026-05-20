# Step 2c — Keycloak Realm Setup via Admin UI

Manual UI alternative to `scripts/setup-keycloak.sh`. Use this when you want to
inspect what the script does, or when REST API access is blocked.

Outcome: a `fingate` realm with two clients (`admin-client`, `user-client`) and
the realm RS256 public key copied out for use in the Kong JWT Secrets.

---

## Prerequisites

- Keycloak deployment from `03-keycloak-deployment.yaml` is running
- `kubectl` access to `keycloak-ns`

```bash
kubectl rollout status deployment/keycloak -n keycloak-ns
```

---

## 2c.1 — Port-forward and open the Admin Console

```bash
kubectl port-forward -n keycloak-ns svc/keycloak 8090:8080
```

Open `http://localhost:8090/auth` in your browser → **Administration Console**.

| Field    | Value               | Source                                   |
|----------|---------------------|------------------------------------------|
| Username | `admin`             | `KEYCLOAK_ADMIN` env in `03-keycloak-deployment.yaml` |
| Password | `Admin@FinGate2024` | `keycloak-admin-secret` in the same file |

---

## 2c.2 — Create the `fingate` realm

Maps to `setup-keycloak.sh` lines 54–64.

1. Top-left realm dropdown (shows **master**) → **Create Realm**
2. Set:
   - **Realm name**: `fingate`
   - **Enabled**: On
3. Click **Create**
4. Open **Realm settings** → **General** tab
   - **Display name**: `FinGate` → **Save**
5. **Tokens** tab
   - **Access Token Lifespan**: `1 Hours` (3600 s) → **Save**

---

## 2c.3 — Create `admin-client`

Maps to `setup-keycloak.sh` lines 67–80.

1. Left menu → **Clients** → **Create client**
2. **General Settings**
   - Client type: `OpenID Connect`
   - Client ID: `admin-client`
   - **Next**
3. **Capability config**
   - Client authentication: **On**   *(= `publicClient: false`)*
   - Authentication flow: tick **Standard flow**, **Direct access grants**, **Service accounts roles**
   - **Next** → **Save**
4. Open the client → **Credentials** tab
   - Client Authenticator: `Client Id and Secret`
   - Paste secret: `admin-client-secret-2024` → **Save**

> The secret must match the value used by `scripts/get-token.sh` and the test suite.

---

## 2c.4 — Create `user-client`

Maps to `setup-keycloak.sh` lines 83–96. Repeat 2c.3 with:

- Client ID: `user-client`
- Secret: `user-client-secret-2024`

---

## 2c.5 — Copy the realm RS256 public key

Maps to `setup-keycloak.sh` lines 98–105.

1. Left menu → **Realm settings** → **Keys** tab
2. Find the row where **Algorithm** = `RS256`, **Type** = `RSA`, **Use** = `SIG`
3. Click **Public key** → copy the base64 string shown in the dialog

That string is the raw value the script gets from
`GET /realms/fingate` → `.public_key`. Kong requires it wrapped in PEM headers:

```text
-----BEGIN PUBLIC KEY-----
<paste the copied key, line-wrapped at 64 chars>
-----END PUBLIC KEY-----
```

Quick wrap on the CLI:

```bash
RAW_KEY="<paste here>"
REALM_PUBLIC_KEY="-----BEGIN PUBLIC KEY-----
$(echo "$RAW_KEY" | fold -w 64)
-----END PUBLIC KEY-----"
```

---

## 2c.6 — Register the key as Kong JWT Secrets

Maps to `setup-keycloak.sh` lines 115–135. These are **Kubernetes Secrets**, not
Keycloak objects — they must be created via `kubectl` regardless of which path
you took above.

```bash
kubectl create secret generic admin-jwt \
  --namespace global-api-gateway-ns \
  --from-literal=kongCredType=jwt \
  --from-literal=key=admin-client \
  --from-literal=algorithm=RS256 \
  --from-literal=rsa_public_key="${REALM_PUBLIC_KEY}" \
  --dry-run=client -o yaml \
  | kubectl label --local -f - konghq.com/credential=jwt -o yaml \
  | kubectl apply -f -

kubectl create secret generic user-jwt \
  --namespace global-api-gateway-ns \
  --from-literal=kongCredType=jwt \
  --from-literal=key=user-client \
  --from-literal=algorithm=RS256 \
  --from-literal=rsa_public_key="${REALM_PUBLIC_KEY}" \
  --dry-run=client -o yaml \
  | kubectl label --local -f - konghq.com/credential=jwt -o yaml \
  | kubectl apply -f -
```

Why these field values matter:

| Field             | Value          | Purpose |
|-------------------|----------------|---------|
| `key`             | `admin-client` / `user-client` | Must match the `azp` claim in the JWT (Keycloak client ID). The `jwt` plugin uses `key_claim_name=azp` to find the matching consumer. |
| `algorithm`       | `RS256`        | Must match the realm key algorithm from 2c.5. |
| `rsa_public_key`  | PEM-wrapped key | What Kong uses to verify the JWT signature. |
| label `konghq.com/credential=jwt` | — | Tells the Kong ingress controller this secret is a consumer credential. |

---

## 2c.7 — Verify

```bash
kubectl get secrets -n global-api-gateway-ns admin-jwt user-jwt \
  -o custom-columns=NAME:.metadata.name,TYPE:.type,LABELS:.metadata.labels
```

Expected:

```text
NAME        TYPE     LABELS
admin-jwt   Opaque   map[konghq.com/credential:jwt]
user-jwt    Opaque   map[konghq.com/credential:jwt]
```

Smoke-test a token (after Step 7 HTTPRoutes are applied):

```bash
curl -sf -d "client_id=admin-client" \
        -d "client_secret=admin-client-secret-2024" \
        -d "grant_type=client_credentials" \
        http://localhost:8090/auth/realms/fingate/protocol/openid-connect/token \
  | jq -r '.access_token' | cut -d. -f2 | base64 -d 2>/dev/null | jq '{iss,azp}'
```

Expected:

```json
{
  "iss": "http://localhost:8090/auth/realms/fingate",
  "azp": "admin-client"
}
```

---

## Next

Continue with **Step 6 — Apply KongConsumers** in the main README. The
KongConsumer `key` values (`admin-client`, `user-client`) bind to the JWT
secrets created here via the `azp` claim.
