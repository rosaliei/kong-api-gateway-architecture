# Kong API Gateway on AWS EKS — Research & Demos

This repo explores different ways to deploy Kong Ingress Controller on AWS EKS for a fictional banking platform with three domains: **retail-banking**, **payments**, and **GRC (governance, risk & compliance)**. Each folder is a standalone, deployable demo that answers a specific architectural question.

For a full side-by-side comparison of Solutions 1–3, see [Comparison.md](Comparison.md).

---

## The Problem

All three domains need to be reachable from the internet through a single hostname (`finance.kst-devops.com`), while being independently managed by separate teams. The demos explore how to wire that up — and how to add authentication and authorization on top.

---

## Demo Index

### Baseline — Distributed Architecture

**Folder:** `Kong-Api-Gateway-Research/Kong-Distributed-Architecture`

No global gateway. Each domain runs its own Kong Ingress Controller (LoadBalancer), each with its own public ELB and subdomain. Teams are completely independent.

```
Internet
  ├─► retail-banking.kst-devops.com  → retail-banking-kic (LoadBalancer)
  ├─► payments.kst-devops.com        → payments-kic       (LoadBalancer)
  └─► grc.kst-devops.com             → grc-kic            (LoadBalancer)
```

**Use when:** Teams are fully autonomous and there is no need for a shared entry point, centralized auth, or cross-domain policies.

---

### Baseline — Centralized Architecture

**Folder:** `Kong-Api-Gateway-Research/Kong-Centralized-Architecture`

A single Kong gateway handles all three domains. All HTTPRoutes live in one namespace under one controller. Simple, but does not scale as teams grow.

```
Internet
  └─► finance.kst-devops.com → single-kic (LoadBalancer)
        ├─► /retail-banking/*
        ├─► /payments/*
        └─► /grc/*
```

**Use when:** Small team, low complexity, no need for per-domain policy isolation.

---

### Solution 1 — Global Gateway with ReferenceGrant

**Folder:** `Kong-Api-Gateway-Research/Kong-Solution-1`

Introduces a **global Kong gateway** (LoadBalancer) in front of three domain-specific gateways (also LoadBalancer). The global HTTPRoute references backend services across namespaces using the Gateway API `ReferenceGrant` resource — the domain team must explicitly grant permission.

```
Internet
  └─► finance.kst-devops.com → global-kic (LoadBalancer)
        ├─► /retail-banking/* → retail-banking-kic (LoadBalancer) ← via ReferenceGrant
        ├─► /payments/*       → payments-kic       (LoadBalancer) ← via ReferenceGrant
        └─► /grc/*            → grc-kic            (LoadBalancer) ← via ReferenceGrant
```

Domain gateways still have public ELBs — direct subdomain access remains possible.

**Key resource:** `2-referencegrants.yaml`

**Use when:** Domain teams need to control who can reach their services. Gateway API purist approach.

---

### Solution 2 — Global Gateway with ExternalName Services

**Folder:** `Kong-Api-Gateway-Research/Kong-Solution-2`

Same two-tier layout as Solution 1, but instead of ReferenceGrant, `ExternalName` services in `global-api-gateway-ns` act as in-namespace DNS aliases pointing to downstream ClusterIP addresses. No cross-namespace backend refs, no ReferenceGrant.

```
Internet
  └─► finance.kst-devops.com → global-kic (LoadBalancer)
        └─► ExternalName services (global-api-gateway-ns)
              └─► *.retail-banking-kic.svc.cluster.local (LoadBalancer, still public)
```

Direct subdomain access still works — domain gateways remain LoadBalancer.

**Key resource:** `2-downstream-proxy-services.yaml`

**Use when:** A central platform team owns all routing config and does not want to coordinate with downstream teams for ReferenceGrants.

---

### Solution 3 — Global Gateway as Single Entry Point (ClusterIP domains)

**Folder:** `Kong-Api-Gateway-Research/Kong-Solution-3`

Same as Solution 2 but domain gateways are deployed as **ClusterIP** — no public ELB, no external IP. The global gateway is the only way in. Direct subdomain access is removed entirely.

```
Internet
  └─► finance.kst-devops.com → global-kic (LoadBalancer) ← only public ELB
        └─► ExternalName services (global-api-gateway-ns)
              └─► *.retail-banking-kic.svc.cluster.local (ClusterIP, internal only)
```

```bash
helm install retail-banking-kic kong/ingress \
  --set gateway.proxy.type=ClusterIP   # no public IP
```

**Use when:** Regulated industries (banking, healthcare) that require all external traffic to pass through a single auditable entry point. Aligns with PCI-DSS and SOC2 network segmentation requirements.

---

### FinGate-RBAC — Global JWT + Role-Based ACL

**Folder:** `Kong-Api-Gateway-Research/Kong-Global JWT+RBAC-Architecture`

Builds on Solution 3 and adds **authentication** (JWT plugin, RS256) and **authorization** (ACL plugin, role-based groups) at the global gateway layer. This is the most complete demo in the repo.

```
Internet
  └─► finance.kst-devops.com → global-kic
        ├─► JWT plugin    — rejects requests with no token or invalid signature (401)
        ├─► ACL plugin    — rejects consumers in the wrong group (403)
        │
        ├─► /retail-banking/*  (anyone-acl)  → admin ✓  user ✓
        ├─► /payments/*        (admin-acl)   → admin ✓  user ✗ 403
        └─► /grc/*             (admin-acl)   → admin ✓  user ✗ 403
```

| Consumer | `/retail-banking` | `/payments` | `/grc` |
|----------|:-----------------:|:-----------:|:------:|
| `admin`  | 200               | 200         | 200    |
| `user`   | 200               | 403         | 403    |
| no token | 401               | 401         | 401    |

See [Kong-Global JWT+RBAC-Architecture/caveats.md](Kong-Api-Gateway-Research/Kong-Global%20JWT%2BRBAC-Architecture/caveats.md) for important limitations of this test setup vs. a real Keycloak integration.

---

## Progression

```
Distributed           — no global gateway, teams fully independent
Centralized           — one gateway, all routes in one place
Solution 1            — global + domain gateways, ReferenceGrant wiring
Solution 2            — global + domain gateways, ExternalName wiring (simpler)
Solution 3            — Solution 2 + ClusterIP domains (single entry point)
FinGate-RBAC          — Solution 3 + JWT authentication + ACL authorization
```

Each step builds on the previous. For a production banking system: **Solution 3 + FinGate-RBAC** is the target state.

---

## Domains

| Domain | Services |
|--------|----------|
| retail-banking | customer-profile, account, statement |
| payments | transfer, payment-gateway, fx |
| grc | fraud, audit, sanction |
