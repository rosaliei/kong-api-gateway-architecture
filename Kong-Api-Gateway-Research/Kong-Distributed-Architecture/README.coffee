# Install Gateway API CRDs
kubectl apply --server-side -f https://github.com/kubernetes-sigs/gateway-api/releases/download/v1.4.1/standard-install.yaml
kubectl apply --server-side -f https://github.com/kubernetes-sigs/gateway-api/releases/download/v1.4.1/experimental-install.yaml

# Add kong helm repo
helm repo add kong https://charts.konghq.com
helm repo update kong

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