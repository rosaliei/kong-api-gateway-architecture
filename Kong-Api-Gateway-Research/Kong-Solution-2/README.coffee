# Solution 2 - for Global API gateway layer

# Install Gateway API CRDs
kubectl apply --server-side -f https://github.com/kubernetes-sigs/gateway-api/releases/download/v1.4.1/standard-install.yaml
kubectl apply --server-side -f https://github.com/kubernetes-sigs/gateway-api/releases/download/v1.4.1/experimental-install.yaml

# Add kong helm repo
helm repo add kong https://charts.konghq.com
helm repo update kong

# Install Domain Specific Kong Ingress Controller
# Install retail-banking Kong Ingress Controller
helm install retail-banking-kic kong/ingress \
  --namespace retail-banking-kic --create-namespace \
  --set controller.ingressController.env.gateway_api_controller_name=konghq.com/retail-banking-kong-gateway-controller

kubectl apply -f 0-gatewayclass-retail-banking.yaml
kubectl apply -f 1-kong-api-gateway-retail-banking.yaml
kubectl apply -f 2-customer-profile-httproute.yaml
kubectl apply -f 3-customer-profile.yaml 
kubectl apply -f 4-account.yaml 
kubectl apply -f 5-statement.yaml

# Install Domain Specific Kong Ingress Controller
# Install payments Kong Ingress Controller

helm install payments-kic kong/ingress \
  --namespace payments-kic --create-namespace \
  --set controller.ingressController.env.gateway_api_controller_name=konghq.com/payments-kong-gateway-controller

kubectl apply -f 0-gatewayclass-payments.yaml 
kubectl apply -f 1-kong-api-gateway-payments.yaml 
kubectl apply -f 2-transfer-httproute.yaml 
kubectl apply -f 3-transfer.yaml 
kubectl apply -f 4-payment-gateway.yaml 
kubectl apply -f 5-fx.yaml

# Install Domain Specific Kong Ingress Controller
# Install grc Kong Ingress Controller

helm install grc-kic kong/ingress \
  --namespace grc-kic --create-namespace \
  --set controller.ingressController.env.gateway_api_controller_name=konghq.com/grc-kong-gateway-controller

kubectl apply -f 0-gatewayclass-grc.yaml
kubectl apply -f 1-kong-api-gateway-grc.yaml
kubectl apply -f 2-fraud-httproute.yaml
kubectl apply -f 3-fraud.yaml
kubectl apply -f 4-audit.yaml
kubectl apply -f 5-sanction.yaml


# Solution 2 - for Global API gateway layer
## Note : Not Using ReferenceGrant CRD. Will be using ExternalName. This solution still allow to access directly to Domain Specific Gateway.
# Install global Kong Ingress Controller

helm install global-kic kong/ingress \
  --namespace global-kic --create-namespace \
  --set controller.ingressController.env.gateway_api_controller_name=konghq.com/global-kong-gateway-controller

kubectl apply -f 0-gatewayclass-global.yaml
kubectl apply -f 1-kong-api-gateway-global.yaml
kubectl apply -f 2-downstream-proxy-services.yaml
kubectl apply -f 3-global-httproute.yaml

# Test (should work)
curl http://finance.kst-devops.com/retail-banking
curl http://finance.kst-devops.com/payments
curl http://finance.kst-devops.com/grc

# Test (should still work)
curl http://retail-banking.kst-devops.com

curl http://payments.kst-devops.com

curl http://grc.kst-devops.com