# ─────────────────────────────────────────────────────────────
#  CAVEATS & WHAT TO FIX — Kong Solution 1
# ─────────────────────────────────────────────────────────────

# PROBLEM: Domain gateways are publicly reachable (bypass risk)
# ─────────────────────────────────────────────────────────────
# When Kong KIC creates a Gateway resource it automatically provisions
# a LoadBalancer-type Service, which causes AWS EKS to spin up a
# Classic Load Balancer (CLB) for EACH domain gateway.
#
# This means you end up with 4 public CLBs:
#
#   Internet
#     │
#     ├──► CLB (global-kong)       → global KIC → domain proxies   ✅ intended path
#     │
#     ├──► CLB (retail-banking-kic) → retail banking apps           ❌ bypasses global GW
#     ├──► CLB (payments-kic)       → payments apps                 ❌ bypasses global GW
#     └──► CLB (grc-kic)            → grc apps                     ❌ bypasses global GW
#
# Anyone who discovers the domain CLB hostname can skip the global
# gateway entirely — bypassing auth, rate limiting, and any policies
# you configured there.

# ─────────────────────────────────────────────────────────────
#  FIX OPTION 1 — Use internal (VPC-only) load balancers
# ─────────────────────────────────────────────────────────────
# Annotate each domain KIC kong-proxy Service so AWS creates an
# internal NLB instead of a public-facing CLB.
#
# Patch after helm install:
#   kubectl annotate svc retail-banking-kic-gateway-proxy \
#     -n retail-banking-kic \
#     service.beta.kubernetes.io/aws-load-balancer-internal="true"
#
#   kubectl annotate svc payments-kic-gateway-proxy \
#     -n payments-kic \
#     service.beta.kubernetes.io/aws-load-balancer-internal="true"
#
#   kubectl annotate svc grc-kic-gateway-proxy \
#     -n grc-kic \
#     service.beta.kubernetes.io/aws-load-balancer-internal="true"
#
# Or set via Helm values at install time:
#   --set proxy.annotations."service\.beta\.kubernetes\.io/aws-load-balancer-internal"="true"

# ─────────────────────────────────────────────────────────────
#  FIX OPTION 2 (Recommended) — ClusterIP for domain gateways
# ─────────────────────────────────────────────────────────────
# Switch domain gateway proxy services to ClusterIP so no AWS load
# balancer is created at all. Traffic can only reach them from inside
# the cluster — exactly how the global gateway's backendRefs call them.
#
#   --set proxy.type=ClusterIP
#
# This is what Kong Solution 3 implements. It is the cleanest fix
# because it removes the attack surface entirely rather than relying
# on network-level restrictions.

# ─────────────────────────────────────────────────────────────
#  SUMMARY
# ─────────────────────────────────────────────────────────────
# | Gateway          | Service Type        | Publicly reachable? |
# |------------------|---------------------|---------------------|
# | global-kic       | LoadBalancer (CLB)  | Yes  ✅ by design   |
# | retail-banking-kic | LoadBalancer (CLB)| Yes  ❌ fix needed  |
# | payments-kic     | LoadBalancer (CLB)  | Yes  ❌ fix needed  |
# | grc-kic          | LoadBalancer (CLB)  | Yes  ❌ fix needed  |
