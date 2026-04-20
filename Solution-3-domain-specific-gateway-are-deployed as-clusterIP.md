# Solution 3 - Domain Specific Gateway are deployed as ClusterIP, so that the point of entry is only GLOBAL API GATEWAY LAYER.

# Install global Kong Ingress Controller as LB, but Domain specific Gateways are ClusterIP

helm install global-kic kong/ingress \
  --namespace global-kic --create-namespace \
  --set controller.ingressController.env.gateway_api_controller_name=konghq.com/global-kong-gateway-controller

helm upgrade retail-banking-kic kong/ingress \
  --namespace retail-banking-kic \
  --set controller.ingressController.env.gateway_api_controller_name=konghq.com/retail-banking-kong-gateway-controller \
  --set gateway.proxy.type=ClusterIP

helm upgrade payments-kic kong/ingress \
  --namespace payments-kic \
  --set controller.ingressController.env.gateway_api_controller_name=konghq.com/payments-kong-gateway-controller \
  --set gateway.proxy.type=ClusterIP

helm upgrade grc-kic kong/ingress \
  --namespace grc-kic \
  --set controller.ingressController.env.gateway_api_controller_name=konghq.com/grc-kong-gateway-controller \
  --set gateway.proxy.type=ClusterIP


k apply -f 0-gatewayclass-global.yaml
k apply -f 1-kong-api-gateway-global.yaml
k apply -f 2-downstream-proxy-services.yaml
k apply -f 3-global-httproute.yaml

# Test (should work)
curl http://finance.hellocloud.xyz/retail-banking
curl http://finance.hellocloud.xyz/payments
curl http://finance.hellocloud.xyz/grc

# Test (won't be working anymore)

curl http://retail-banking.hellocloud.xyz
curl http://payments.hellocloud.xyz
curl http://grc.hellocloud.xyz