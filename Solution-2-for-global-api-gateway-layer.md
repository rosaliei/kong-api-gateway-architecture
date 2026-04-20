# Solution 2 - for Global API gateway layer

## Note : Not Using ReferenceGrant CRD. Will be using ExternalName. This solution still allow to access directly to Domain Specific Gateway.

# Install global Kong Ingress Controller

helm install global-kic kong/ingress \
  --namespace global-kic --create-namespace \
  --set controller.ingressController.env.gateway_api_controller_name=konghq.com/global-kong-gateway-controller

k apply -f 0-gatewayclass-global.yaml
k apply -f 1-kong-api-gateway-global.yaml
k apply -f 2-downstream-proxy-services.yaml
k apply -f 3-global-httproute.yaml

# Test (should work)
curl http://finance.hellocloud.xyz/retail-banking
curl http://finance.hellocloud.xyz/payments
curl http://finance.hellocloud.xyz/grc

# Test (should still work)
curl http://retail-banking.hellocloud.xyz

curl http://payments.hellocloud.xyz

curl http://grc.hellocloud.xyz