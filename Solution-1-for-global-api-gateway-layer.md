# Solution 1 - for Global API gateway layer

## Note: ReferenceGrant CRD

# Install global Kong Ingress Controller

helm install global-kic kong/ingress \
  --namespace global-kic --create-namespace \
  --set controller.ingressController.env.gateway_api_controller_name=konghq.com/global-kong-gateway-controller

k apply -f 0-gatewayclass-global.yaml
k apply -f 1-kong-api-gateway-global.yaml
k apply -f 2-referencegrants.yaml
k apply -f 3-global-httproute.yaml

# Test
curl http://finance.hellocloud.xyz/retail-banking
curl http://finance.hellocloud.xyz/payments
curl http://finance.hellocloud.xyz/grc