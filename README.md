# EKS Cluster with Kong Gateway

A reference architecture for deploying a multi-domain API gateway layer on AWS EKS using Kong Ingress Controller and the Kubernetes Gateway API. The setup models a financial platform with three domain-specific services (Retail Banking, Payments, GRC), each with their own Kong Ingress Controller, fronted by a single global Kong gateway.

## Architecture

```
Internet
   |
Global Kong Gateway (LoadBalancer)
   |
   +-- /retail-banking --> Retail Banking KIC
   +-- /payments       --> Payments KIC
   +-- /grc            --> GRC KIC
```

Each domain namespace runs its own Kong Ingress Controller and exposes services internally. The global gateway routes traffic across namespaces via one of three strategies (see Solutions below).

### Domain Services

| Domain | Namespace | Services |
|---|---|---|
| Retail Banking | `retail-banking-kic` | customer-profile, account, statement |
| Payments | `payments-kic` | transfer, payment-gateway, fx |
| GRC | `grc-kic` | fraud, audit, sanction |

## Prerequisites

- AWS CLI configured with appropriate permissions
- `eksctl`, `kubectl`, `helm` installed
- Kong Helm chart repo added: `helm repo add kong https://charts.konghq.com`

## Initial Setup

Spin up the EKS cluster and install the Gateway API CRDs:

```bash
eksctl create cluster --name eu-eks-cluster --region eu-north-1 --version 1.34 \
  --instance-types t3.medium --nodes-min 3

kubectl apply --server-side -f https://github.com/kubernetes-sigs/gateway-api/releases/download/v1.4.1/standard-install.yaml
kubectl apply --server-side -f https://github.com/kubernetes-sigs/gateway-api/releases/download/v1.4.1/experimental-install.yaml
```

Install the domain-specific Kong Ingress Controllers and apply their manifests. See [Runbook.md](Runbook.md) for full step-by-step commands.

## Solutions

Three approaches are provided for wiring the global gateway to domain-specific gateways. Each is self-contained under its own directory.

### Solution 1 — ReferenceGrant-based cross-namespace routing

Uses the `ReferenceGrant` CRD to allow the global HTTPRoute to reference backends in other namespaces.

- All domain gateways remain as `LoadBalancer` services (directly accessible).
- Requires `ReferenceGrant` resources in each domain namespace.

```bash
cd Solution-1
helm install global-kic kong/ingress \
  --namespace global-kic --create-namespace \
  --set controller.ingressController.env.gateway_api_controller_name=konghq.com/global-kong-gateway-controller

kubectl apply -f 0-gatewayclass-global.yaml
kubectl apply -f 1-kong-api-gateway-global.yaml
kubectl apply -f 2-referencegrants.yaml
kubectl apply -f 3-global-httproute.yaml
```

### Solution 2 — ExternalName services (no ReferenceGrant)

Uses `ExternalName` services in the global namespace to proxy to domain gateways. Domain gateways remain as `LoadBalancer` services and are still directly accessible via their own hostnames.

```bash
cd Solution-2
helm install global-kic kong/ingress \
  --namespace global-kic --create-namespace \
  --set controller.ingressController.env.gateway_api_controller_name=konghq.com/global-kong-gateway-controller

kubectl apply -f 0-gatewayclass-global.yaml
kubectl apply -f 1-kong-api-gateway-global.yaml
kubectl apply -f 2-downstream-proxy-services.yaml
kubectl apply -f 3-global-httproute.yaml
```

### Solution 3 — Domain gateways as ClusterIP (global gateway as single entry point)

Domain-specific gateways are deployed as `ClusterIP` instead of `LoadBalancer`, so they are not reachable directly from outside the cluster. All external traffic must flow through the global gateway.

```bash
cd Solution-3
helm install global-kic kong/ingress \
  --namespace global-kic --create-namespace \
  --set controller.ingressController.env.gateway_api_controller_name=konghq.com/global-kong-gateway-controller

helm upgrade retail-banking-kic kong/ingress --namespace retail-banking-kic \
  --set controller.ingressController.env.gateway_api_controller_name=konghq.com/retail-banking-kong-gateway-controller \
  --set gateway.proxy.type=ClusterIP

helm upgrade payments-kic kong/ingress --namespace payments-kic \
  --set controller.ingressController.env.gateway_api_controller_name=konghq.com/payments-kong-gateway-controller \
  --set gateway.proxy.type=ClusterIP

helm upgrade grc-kic kong/ingress --namespace grc-kic \
  --set controller.ingressController.env.gateway_api_controller_name=konghq.com/grc-kong-gateway-controller \
  --set gateway.proxy.type=ClusterIP

kubectl apply -f 0-gatewayclass-global.yaml
kubectl apply -f 1-kong-api-gateway-global.yaml
kubectl apply -f 2-downstream-proxy-services.yaml
kubectl apply -f 3-global-httproute.yaml
```

## Solution Comparison

| | Solution 1 | Solution 2 | Solution 3 |
|---|---|---|---|
| Mechanism | ReferenceGrant | ExternalName services | ClusterIP domain gateways |
| Domain gateways directly accessible | Yes | Yes | No |
| Requires ReferenceGrant CRD | Yes | No | No |
| Single point of entry enforced | No | No | Yes |

## Testing

After deploying any solution, verify global routing:

```bash
curl http://finance.hellocloud.xyz/retail-banking
curl http://finance.hellocloud.xyz/payments
curl http://finance.hellocloud.xyz/grc
```

For Solutions 1 and 2, direct domain access also works:

```bash
curl http://retail-banking.hellocloud.xyz
curl http://payments.hellocloud.xyz
curl http://grc.hellocloud.xyz
```

Direct domain access will not work in Solution 3 by design.

## Repository Structure

```
.
├── Runbook.md                          # Full setup commands
├── 1-retail-banking/                   # Retail Banking domain manifests
├── 2-payments/                         # Payments domain manifests
├── 3-grc/                              # GRC domain manifests
├── Solution-1/                         # ReferenceGrant-based global gateway
├── Solution-2/                         # ExternalName-based global gateway
└── Solution-3/                         # ClusterIP domain gateways
```
