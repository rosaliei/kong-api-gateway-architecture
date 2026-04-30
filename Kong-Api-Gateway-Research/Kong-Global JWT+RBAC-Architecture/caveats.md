# Caveats — FinGate-RBAC (Kong JWT + ACL)

This setup demonstrates the **concepts** of authentication and authorization at the API gateway layer using Kong's free (OSS/KIC) plugins. Several deliberate simplifications were made to keep this testable without paid licenses. Read these caveats before treating this as a production pattern.

---

## 1. Tokens should come from Keycloak, not a script

In this test, JWTs are minted locally with `scripts/generate-token.sh` using self-generated RSA keypairs. **In a real system, all tokens must be issued by Keycloak (or another trusted Identity Provider).** Keycloak:

- Authenticates the user (username/password, MFA, SSO)
- Signs the token with its own private key (the gateway only holds the public key)
- Embeds standard claims: `sub`, `iss`, `aud`, `exp`, `iat`
- Embeds Keycloak-specific claims: `realm_access.roles`, `resource_access.<client>.roles`, `scope`, `preferred_username`, `email`, `azp`
- Controls token lifetime and refresh

The test scripts bypass all of this — they produce a minimal JWT that Kong accepts for signature verification, but they do not represent what a Keycloak-issued token looks like. The `iss` value (`admin-issuer` / `user-issuer`) is a placeholder, not a real Keycloak realm URL (which would be something like `https://keycloak.example.com/realms/finance`).

---

## 2. Tokens should carry scopes and Keycloak claims

A Keycloak-issued token for a finance gateway would typically include:

```json
{
  "iss": "https://keycloak.example.com/realms/finance",
  "sub": "a1b2c3d4-...",
  "aud": ["finance-api", "account"],
  "scope": "openid profile email finance:read finance:write",
  "realm_access": {
    "roles": ["admin", "offline_access"]
  },
  "resource_access": {
    "finance-api": {
      "roles": ["admin"]
    }
  },
  "preferred_username": "john.doe",
  "email": "john.doe@example.com"
}
```

The tokens in this test carry none of these. They only carry the `iss` claim that Kong uses to look up the matching `KongConsumer`. Scope-based access control and claim-based routing are not demonstrated here.

---

## 3. Some Kong plugins required for this pattern are enterprise-only

The correct production pattern for Keycloak + Kong would use plugins that are **not available in the free Kong OSS / KIC tier**:

| Plugin | Tier | What it does |
|--------|------|--------------|
| `openid-connect` | **Enterprise** | Full OIDC flow — redirects to Keycloak, introspects tokens, maps claims to Kong consumers automatically |
| `jwt-signer` | **Enterprise** | Validates tokens against a JWKS endpoint (Keycloak's public keys), verifies `iss`, `aud`, `exp` |
| `opa` | **Enterprise** | Delegates authorization decisions to Open Policy Agent |
| `ldap-auth-advanced` | **Enterprise** | LDAP/AD group mapping |

**This test uses only free-tier plugins:** `jwt` (static public key, no JWKS endpoint) and `acl` (group membership from a Kubernetes Secret). These are functional but limited:

- The `jwt` plugin cannot hit a JWKS endpoint to fetch Keycloak's rotating public keys — the public key must be stored manually as a Kubernetes Secret and updated by hand on every key rotation.
- The `acl` plugin cannot read roles directly from JWT claims — group membership must be pre-configured in `KongConsumer` credentials, meaning Kong does not dynamically derive roles from what Keycloak puts in the token.

---

## 4. The correct auth/authz split: Keycloak decides, Kong enforces

In a proper implementation the responsibility is split as follows:

```
Client → [Keycloak] → token → [Kong Gateway] → backend
              ↑                      ↑
         AuthN + AuthZ          Token introspection
         (who you are,          (is this token valid?
          what you can do)       not expired? right iss/aud?)
```

- **Keycloak** is the authority for both **authentication** (identity) and **authorization** (what roles/scopes a user has). It issues a signed token containing that decision.
- **Kong** is responsible for **introspecting the token** — verifying the signature, checking expiry, confirming the issuer, and optionally checking the audience. Kong should not make authorization decisions from scratch; it should trust what Keycloak put in the token and enforce it at the gateway layer.
- **In this test**, Kong is doing a simplified version of both: signature verification via the `jwt` plugin, and a static group check via the `acl` plugin. The ACL groups are hardcoded in Kubernetes Secrets, not derived from the token claims Keycloak would provide.

This is enough to demonstrate **what auth and authz look like at the gateway layer**, but it is not how you would wire this up against a real Keycloak deployment.

---

## Summary

| Aspect | This test | Production with Keycloak |
|--------|-----------|--------------------------|
| Token issuer | Local script (`openssl` + `jwt`) | Keycloak realm |
| Token claims | Minimal (`iss` only) | Full OIDC claims + scopes + roles |
| Key distribution | Static PEM in K8s Secret | JWKS endpoint (auto-rotated) |
| Kong plugin | `jwt` (free) | `openid-connect` or `jwt-signer` (enterprise) |
| ACL / roles | Hardcoded in K8s Secret | Derived from Keycloak token claims |
| Introspection | Signature + exp check only | Full token introspection against Keycloak |
| AuthZ decision | Static ACL group | Keycloak decides; Kong enforces |
