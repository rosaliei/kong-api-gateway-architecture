# Global API Gateway — Solution Comparison

A full comparison of the three solutions for the global API gateway layer.
Intended for DevOps engineers and Software Engineers onboarding to this architecture.

---

## Table of Contents

1. [High-Level Architecture](#1-high-level-architecture)
2. [Core Concept — What Problem Are We Solving](#2-core-concept--what-problem-are-we-solving)
3. [Key Concepts](#3-key-concepts)
4. [Solution Overview](#4-solution-overview)
5. [Full Comparison Table](#5-full-comparison-table)
6. [Adding a New Domain](#6-adding-a-new-domain)
7. [Internal Communication in Solution 3](#7-internal-communication-in-solution-3)
8. [DevOps Considerations](#8-devops-considerations)
9. [Software Engineering Considerations](#9-software-engineering-considerations)
10. [Real-World Use Cases](#10-real-world-use-cases)
11. [Recommendation](#11-recommendation)

---

## 1. High-Level Architecture

```
                        Internet
                            │
                            ▼
              ┌─────────────────────────┐
              │   Kong API Gateway      │
              │   (Global / External)   │
              │   finance.hellocloud.xyz│
              └────────────┬────────────┘
                           │
          ┌────────────────┼─────────────────┐
          │                │                 │
          ▼                ▼                 ▼
  ┌──────────────┐ ┌──────────────┐ ┌──────────────┐
  │ Kong Gateway │ │ Kong Gateway │ │ Kong Gateway │
  │   (Domain)   │ │   (Domain)   │ │   (Domain)   │
  └──────┬───────┘ └──────┬───────┘ └──────┬───────┘
         │                │                │
         ▼                ▼                ▼
   retail-banking      payments        governance &
                                       compliance
```

The global gateway sits in front of all domain-specific gateways.
Each domain gateway manages its own services internally.

---

## 2. Core Concept — What Problem Are We Solving

All three solutions answer the same question:

> How does the global HTTPRoute (in `global-api-gateway-ns`) reach backend services
> that live in different namespaces (`retail-banking-kic`, `payments-kic`, `grc-kic`)?

By default, Kubernetes Gateway API blocks cross-namespace backend references.
Each solution solves this differently.

---

## 3. Key Concepts

### Forward Proxy vs Reverse Proxy

| | Forward Proxy | Reverse Proxy |
|---|---|---|
| Represents | Client | Server |
| Hides | Client from server | Server from client |
| Configured by | Client or network | Server owner |
| Examples | Squid, corporate VPN | Nginx, Kong, AWS ALB |

Kong in this repo acts as a **reverse proxy** — clients hit `finance.hellocloud.xyz`
and Kong routes to the appropriate backend without the client knowing the topology.

### Kubernetes Service Types

| Type | Accessible From | Used In |
|---|---|---|
| `ClusterIP` | Inside cluster only | Domain gateways (Solution 3), app services |
| `NodePort` | Node IP + port | Rarely used in production |
| `LoadBalancer` | Anywhere (provisions AWS ELB) | Global gateway, domain gateways (Solutions 1 & 2) |
| `ExternalName` | Inside cluster (DNS alias) | `global-api-gateway-ns` (Solutions 2 & 3) |

### .local DNS vs ELB

Every Kubernetes Service gets an internal DNS name regardless of its type:

```
<service-name>.<namespace>.svc.cluster.local
```

This always resolves to the **ClusterIP** — never the ELB.
A LoadBalancer service has both:

```
retail-banking-kic-gateway-proxy
  ├── ClusterIP : 10.100.49.26          ← what .local DNS resolves to (internal)
  └── ELB       : a65b...amazonaws.com  ← public endpoint (external)
```

```
┌─────────────────────────────────────────────────────────────────┐
│                        EKS Cluster                              │
│                                                                 │
│   ┌──────────────────────────────────────────────────────┐     │
│   │         retail-banking-kic-gateway-proxy Service      │     │
│   │                                                       │     │
│   │   ClusterIP : 10.100.49.26                            │     │
│   │   DNS       : retail-banking-kic-gateway-proxy        │     │
│   │               .retail-banking-kic.svc.cluster.local   │     │
│   │   NodePort  : 31999                                   │     │
│   └─────────────────────────┬─────────────────────────────┘     │
│                             │                                   │
│                             ▼                                   │
│                 ┌───────────────────────┐                       │
│                 │  retail-banking Pods  │                       │
│                 │  (Kong proxy)         │                       │
│                 └───────────────────────┘                       │
│                          ▲                        ▲             │
│              internal    │                        │  external   │
│              (.local DNS)│                        │  (ELB)      │
│                          │                        │             │
│              ┌───────────┘                        │             │
│              │                                    │             │
│   ┌──────────────────┐              ┌─────────────────────┐    │
│   │   global-kic     │              │     AWS ELB         │    │
│   │   (ExternalName  │              │  a65b...amazonaws   │    │
│   │    → .local)     │              │                     │    │
│   └──────────────────┘              └─────────────────────┘    │
└─────────────────────────────────────────────────────────────────┘
          ▲                                      ▲
          │ internal traffic                     │ external traffic
          │ (Solutions 2 & 3)                    │ (direct subdomain)
          │                                      │
  ┌───────────────┐                    ┌─────────────────────┐
  │  global Kong  │                    │   Internet Client   │
  │  (ExternalName│                    │   browser / curl    │
  │   via .local) │                    └─────────────────────┘
  └───────────────┘
```

**Two paths, same destination:**

```
PATH 1 — Internal (.local)
─────────────────────────────────────────────────────────
global-kic
  └─► ExternalName service (global-api-gateway-ns)
        └─► DNS: retail-banking-kic-gateway-proxy
                  .retail-banking-kic.svc.cluster.local
              └─► ClusterIP: 10.100.49.26
                    └─► retail-banking Kong pods ✓

PATH 2 — External (ELB)
─────────────────────────────────────────────────────────
Internet client
  └─► ELB: a65b...elb.amazonaws.com
        └─► NodePort: 31999 (on EC2 node)
              └─► retail-banking Kong pods ✓
```

### global-api-gateway-ns

This namespace serves three purposes:

1. **Label-based trust** — the global Gateway's `allowedRoutes` selector only accepts
   HTTPRoutes from namespaces labelled `kubernetes.io/metadata.name: global-api-gateway-ns`
2. **Cross-namespace permission anchor** — ReferenceGrants (Solution 1) or ExternalName
   services (Solutions 2 & 3) are tied to this namespace
3. **HTTPRoute home** — the global `HTTPRoute` object lives here

The namespace holds no pods or app services — only routing resources.

---

## 4. Solution Overview

### Solution 1 — ReferenceGrant

The global HTTPRoute references backend services **directly across namespaces**.
Requires a `ReferenceGrant` in each downstream namespace to permit this.

```
global-httproute (global-api-gateway-ns)
  └─► backendRef: retail-banking-kic-gateway-proxy
                  namespace: retail-banking-kic     ← cross-namespace
        ← permitted by ReferenceGrant in retail-banking-kic
```

### Solution 2 — ExternalName Services

`ExternalName` services in `global-api-gateway-ns` act as local DNS aliases
pointing to downstream services. The HTTPRoute only references local services —
no cross-namespace backend refs, no ReferenceGrant needed.

```
global-httproute (global-api-gateway-ns)
  └─► backendRef: retail-banking-kic-gateway-proxy
                  namespace: global-api-gateway-ns   ← same namespace
        └─► ExternalName → retail-banking-kic-gateway-proxy
                            .retail-banking-kic.svc.cluster.local
```

### Solution 3 — ClusterIP + Single Entry Point

Same as Solution 2, but domain gateways are deployed as `ClusterIP` instead
of `LoadBalancer`. They have no public ELB — the global gateway is the only
way in from the internet.

```
helm upgrade retail-banking-kic kong/ingress \
  --set gateway.proxy.type=ClusterIP    ← no public IP
```

```
Before Solution 3 (LoadBalancer):       After Solution 3 (ClusterIP):

Internet ──► ELB ──► pods   ✓          Internet ──► ELB ──► ✗ (removed)
global-kic ──► .local ──► pods ✓       global-kic ──► .local ──► pods ✓
```

---

## 5. Full Comparison Table

### Architecture

| | Solution 1 | Solution 2 | Solution 3 |
|---|---|---|---|
| Cross-namespace mechanism | `ReferenceGrant` | `ExternalName` Services | `ExternalName` Services |
| Domain gateway type | LoadBalancer | LoadBalancer | **ClusterIP** |
| Single entry point enforced | No | No | **Yes** |
| Extra resources per new domain | 1 ReferenceGrant | 1 ExternalName Service | 1 ExternalName Service |
| Who owns glue resource | Downstream team | Global gateway team | Global gateway team |

### Routing

| | Solution 1 | Solution 2 | Solution 3 |
|---|---|---|---|
| Global path routing | Yes | Yes | Yes |
| Direct subdomain access | Yes | Yes | **No** |
| URLRewrite (path + host) | Yes | Yes | Yes |
| Number of Kong hops | 2 | 2 | 2 (unavoidable) |

### Security

| | Solution 1 | Solution 2 | Solution 3 |
|---|---|---|---|
| Gateway API native compliance | Yes (strict) | Workaround | Workaround |
| Domain gateway bypass possible | Yes (via subdomain) | Yes (via subdomain) | **No** |
| Centralized policy enforcement | Partial | Partial | **Full** |
| Cross-namespace access control | Via ReferenceGrant | Implicit via ExternalName | Implicit via ExternalName |
| TLS termination complexity | Per gateway (N certs) | Per gateway (N certs) | Global only (1 cert) |

### Operations

| | Solution 1 | Solution 2 | Solution 3 |
|---|---|---|---|
| Number of ELBs | 1 global + N domain | 1 global + N domain | **1 global only** |
| DNS records needed | 1 global + N domain | 1 global + N domain | **1 global only** |
| Helm upgrade risk | Low | Low | **High** (must always set ClusterIP) |
| Deploy order sensitivity | Medium | Medium | Medium |
| Local dev complexity | Low (hit domain directly) | Low (hit domain directly) | **High** (must run full stack) |

### Cost & Scale

| | Solution 1 | Solution 2 | Solution 3 |
|---|---|---|---|
| ELB cost at scale | High (1 per domain) | High (1 per domain) | **Low (1 total)** |
| Observability surface | Multiple gateways | Multiple gateways | **Single gateway** |
| Config ownership as teams grow | Distributed | Centralized | Centralized |
| HTTPRoute file contention | Shared file | Shared file | Shared file |

---

## 6. Adding a New Domain

Using `wealth-management` as an example.

### App-level (same for all solutions)

| Step | Resource |
|---|---|
| Helm install | `helm install wealth-management-kic kong/ingress ...` |
| GatewayClass | New controller name |
| Gateway | In `wealth-management-kic`, scoped to `wealth-management-ns` |
| Namespaces | `wealth-management-kic` and `wealth-management-ns` |
| HTTPRoute | In `wealth-management-ns`, hostname `wealth-management.domain.xyz` |
| Service + Deployment | App workloads |

### Global gateway wiring

**Solution 1 — add 2 things:**

```yaml
# 1. ReferenceGrant in wealth-management-kic
apiVersion: gateway.networking.k8s.io/v1beta1
kind: ReferenceGrant
metadata:
  name: allow-global-gateway
  namespace: wealth-management-kic
spec:
  from:
  - group: gateway.networking.k8s.io
    kind: HTTPRoute
    namespace: global-api-gateway-ns
  to:
  - group: ""
    kind: Service

# 2. New rule in 3-global-httproute.yaml
- matches:
  - path:
      type: PathPrefix
      value: /wealth-management
  filters:
  - type: URLRewrite
    urlRewrite:
      hostname: wealth-management.domain.xyz
      path:
        replacePrefixMatch: /
  backendRefs:
  - name: wealth-management-kic-gateway-proxy
    namespace: wealth-management-kic
    port: 80
```

**Solution 2 & 3 — add 2 things:**

```yaml
# 1. ExternalName Service in global-api-gateway-ns
apiVersion: v1
kind: Service
metadata:
  name: wealth-management-kic-gateway-proxy
  namespace: global-api-gateway-ns
spec:
  type: ExternalName
  externalName: wealth-management-kic-gateway-proxy.wealth-management-kic.svc.cluster.local
  ports:
  - name: http
    port: 80
    protocol: TCP

# 2. New rule in 3-global-httproute.yaml
- matches:
  - path:
      type: PathPrefix
      value: /wealth-management
  filters:
  - type: URLRewrite
    urlRewrite:
      hostname: wealth-management.domain.xyz
      path:
        type: ReplacePrefixMatch
        replacePrefixMatch: /
  backendRefs:
  - name: wealth-management-kic-gateway-proxy
    port: 80
```

### Complexity per new domain

| | Solution 1 | Solution 2 | Solution 3 |
|---|---|---|---|
| App-level work | Same | Same | Same (+ must set ClusterIP) |
| Global gateway change | Append 1 rule | Append 1 rule | Append 1 rule |
| Glue resource | ReferenceGrant (downstream ns) | ExternalName (global ns) | ExternalName (global ns) |
| Who does the wiring | Downstream team | Global gateway team | Global gateway team |

All solutions require **manual** addition of a new path rule — there is no automation.

---

## 7. Internal Communication in Solution 3

Domain gateways are ClusterIP — no public IP — but they still exist inside the cluster.
Apps communicate via:

### Option A — Direct Kubernetes DNS (bypass all gateways)

```
customer-profile-svc
  → transfer-svc.payments-ns.svc.cluster.local
```

- Lowest latency
- No gateway policies applied
- Tight coupling (caller knows internal service name)
- Used for intra-domain calls (already in codebase)

### Option B — Via domain gateway ClusterIP (recommended for cross-domain)

```
customer-profile-svc
  → payments-kic-gateway-proxy.payments-kic.svc.cluster.local
```

- Domain-level policies applied (auth, rate limiting)
- Loose coupling — caller only knows gateway address
- Payments team controls what is exposed via their HTTPRoute

### Option C — Via global gateway

```
customer-profile-svc
  → global-kic-gateway-proxy.global-kic.svc.cluster.local/payments
```

- Full global policies applied
- Most latency (2 hops)
- Most observable and centralized

### Comparison

| | Option A (Direct DNS) | Option B (Domain Gateway) | Option C (Global Gateway) |
|---|---|---|---|
| Latency | Lowest | Low | Highest |
| Policy enforcement | None | Domain-level | Global + domain |
| Coupling | Tight | Loose | Loosest |
| Observability | None | Per domain | Centralized |
| Downstream team controls access | No | Yes | Partial |

**Recommendation:** Use Option A for intra-domain calls, Option B for cross-domain calls.

---

## 8. DevOps Considerations

### Certificate Management (TLS)

All solutions currently use HTTP. In production:

| | Solution 1 & 2 | Solution 3 |
|---|---|---|
| TLS termination points | Global gateway + each domain gateway | Global gateway only |
| Certs to manage | 1 per domain + 1 global | 1 global only |
| Cert rotation ownership | Split across teams | Global team owns all |

### Deployment Order Dependency

Resources must be applied in sequence:

```
helm install (KIC)
  → GatewayClass
  → Gateway + Namespace
  → ReferenceGrant / ExternalName
  → HTTPRoute
```

If the HTTPRoute is applied before the downstream gateway is ready, traffic silently fails.
CI/CD pipelines must encode this dependency.

### Health Checks & Circuit Breaking

With two Kong hops, if a domain gateway is unhealthy:
- The global gateway may not detect it immediately
- Returns 502 without a meaningful fallback
- Kong `circuit-breaker` plugin should be configured at the global layer

### Helm Upgrade Risk (Solution 3 specific)

Upgrading a domain KIC without `--set gateway.proxy.type=ClusterIP`
accidentally re-exposes it as a LoadBalancer, breaking the security model.

Enforce via committed Helm values files — never ad-hoc commands:

```yaml
# values-retail-banking.yaml
gateway:
  proxy:
    type: ClusterIP
```

### DNS Management

| | Solution 1 & 2 | Solution 3 |
|---|---|---|
| DNS records | 1 global + N domain | 1 global only |
| Risk | Domain ELBs can change DNS on redeploy | Single record to manage |

### Identifying ELBs in AWS

```bash
# Map Kubernetes services to ELB DNS names
kubectl get svc -A -o custom-columns=\
'NAMESPACE:.metadata.namespace,\
NAME:.metadata.name,\
TYPE:.spec.type,\
EXTERNAL-IP:.status.loadBalancer.ingress[0].hostname' \
| grep LoadBalancer
```

AWS auto-tags ELBs with:
```
kubernetes.io/cluster/<cluster-name>  = owned
kubernetes.io/namespace               = retail-banking-kic
kubernetes.io/service-name            = kong-proxy
```

Add custom tags at helm install time for easier identification:
```bash
helm install retail-banking-kic kong/ingress \
  --set proxy.annotations."service\.beta\.kubernetes\.io/aws-load-balancer-additional-resource-tags"="domain=retail-banking,env=prod"
```

---

## 9. Software Engineering Considerations

### Path Collision Risk

All domain teams share the same path namespace on `finance.hellocloud.xyz`.
Two teams could accidentally register the same path prefix with no enforcement preventing it.
Requires a governance process or path registry.

### URLRewrite Side Effects

The global HTTPRoute strips the path prefix and rewrites the Host header:

```
Client sends:    GET /retail-banking/customers   Host: finance.hellocloud.xyz
Downstream gets: GET /customers                  Host: retail-banking.nyanlintun.xyz
```

Any service that builds self-referencing URLs (redirects, HATEOAS links) using the
incoming Host or path will produce broken URLs unless the app accounts for this rewrite.

> **Known issue:** The global HTTPRoute rewrites the Host to `retail-banking.hellocloud.xyz`
> but the downstream HTTPRoute (`1-retail-banking/2-customer-profile-httproute.yaml`) listens
> on `retail-banking.nyanlintun.xyz`. These must match or downstream routing will silently fail.
> Ensure the `urlRewrite.hostname` in the global HTTPRoute matches the `hostnames` field in
> every downstream HTTPRoute.

### Local Development

| | Solution 1 & 2 | Solution 3 |
|---|---|---|
| Hit domain gateway directly | Yes (has public ELB) | No (ClusterIP only) |
| Local dev options | Mock global layer or use dev cluster | Must run full stack locally or use shared dev cluster |

### Error Attribution

When a 502/504 occurs, it could be the global gateway or the domain gateway.
Without structured logging and trace propagation (`X-Request-ID` passed through both hops),
debugging is difficult.
Ensure correlation IDs are forwarded at both Kong layers.

### API Versioning

Decide ownership before teams start building:

- Versioning at the global HTTPRoute level → affects all consumers, global team owns it
- Versioning at the domain HTTPRoute level → transparent to global layer, domain team owns it

### Single Point of Failure

All solutions funnel external traffic through the global gateway.
If it goes down, all domains are unreachable.
Global KIC should run with multiple replicas and pod disruption budgets.

---

## 10. Real-World Use Cases

| Solution | Who uses it | Why |
|---|---|---|
| Solution 1 | Large enterprises with mature GitOps, team-owned namespaces | Domain teams independently control who can access their services via ReferenceGrant |
| Solution 2 | Startups, mid-size companies, platform-team-owned routing | Central SRE team owns all routing config without needing downstream team approval |
| Solution 3 | Banks, fintechs, healthcare, regulated industries | Regulators require all external traffic through a single auditable entry point |

**This repo's context (banking)** aligns most closely with Solution 3:
- GRC domain exists for compliance requirements
- Single entry point aligns with PCI-DSS and SOC2 network segmentation requirements
- ClusterIP on domain gateways follows principle of least privilege

Solutions 1 and 2 are better suited as intermediate steps during development
or migration before graduating to Solution 3 for production.

---

## 11. Recommendation

```
Development / Migration path:

  Solution 1 ──► Solution 2 ──► Solution 3
  (learn Gateway  (simplify      (harden for
   API properly)   ownership)     production)
```

For a banking system in production: **Solution 3**.

For a platform team that needs to move fast without cross-team coordination: **Solution 2**.

For organizations where downstream teams must retain control over who accesses their services: **Solution 1**.
