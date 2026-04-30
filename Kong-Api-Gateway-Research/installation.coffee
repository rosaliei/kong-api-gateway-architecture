# JUST NOTES
eksctl create cluster --name sgp-eks-cluster --region ap-southeast-1 --version 1.34 --instance-types t3.medium --nodes-min 3 --profile kyawsithu.hc+devops

# Resources Analysis
No Gateway api is installed by default
'kubectl api-resources | grep networking
applicationnetworkpolicies          anp          networking.k8s.aws/v1alpha1       true         ApplicationNetworkPolicy
clusternetworkpolicies              cnp          networking.k8s.aws/v1alpha1       false        ClusterNetworkPolicy
clusterpolicyendpoints              cpe          networking.k8s.aws/v1alpha1       false        ClusterPolicyEndpoint
policyendpoints                                  networking.k8s.aws/v1alpha1       true         PolicyEndpoint
ingressclasses                                   networking.k8s.io/v1              false        IngressClass
ingresses                           ing          networking.k8s.io/v1              true         Ingress
ipaddresses                         ip           networking.k8s.io/v1              false        IPAddress
networkpolicies                     netpol       networking.k8s.io/v1              true         NetworkPolicy
servicecidrs                                     networking.k8s.io/v1              false        ServiceCIDR'

# Kong doesn't install Gateway API by default, we need to install the Gateway API separately based on the version of Kong.
# REFERENCE : https://github.com/kubernetes-sigs/gateway-api/releases

# Gateway API Version
https://github.com/kubernetes-sigs/gateway-api/tree/main/conformance/reports

Always check which gateway api version needs to install for kong ingress controller.
# REFERENCE : https://developer.konghq.com/kubernetes-ingress-controller/version-compatibility

# All versions need to be matched
Gateway API --> Kong Ingress Controller --> Kong Gateway

# helm repo add kong
helm search repo kong
NAME                    CHART VERSION   APP VERSION     DESCRIPTION                                    
kong/kong               3.2.0           3.9             The Cloud-Native Ingress and API-management    
kong/kong-operator      1.2.3           2.1.3           Deploy Kong Operator                           
kong/gateway-operator   0.6.1           1.6             Deploy Kong Gateway Operator                   
kong/ingress            0.24.0          3.9             Deploy Kong Ingress Controller and Kong Gateway

# helm repo pull
helm pull kong/ingress --version 0.20.0 --untar --untardir kong-ingress-v0.20.0

# Install Gateway API Standard
kubectl apply --server-side -f https://github.com/kubernetes-sigs/gateway-api/releases/download/v1.4.1/standard-install.yaml
# OR Install Gateway API Experimental
kubectl apply --server-side -f https://github.com/kubernetes-sigs/gateway-api/releases/download/v1.4.1/experimental-install.yaml

kubectl api-resources | grep networking
backendtlspolicies                  btlspolicy   gateway.networking.k8s.io/v1        true         BackendTLSPolicy
gatewayclasses                      gc           gateway.networking.k8s.io/v1        false        GatewayClass
gateways                            gtw          gateway.networking.k8s.io/v1        true         Gateway
grpcroutes                                       gateway.networking.k8s.io/v1        true         GRPCRoute
httproutes                                       gateway.networking.k8s.io/v1        true         HTTPRoute
referencegrants                     refgrant     gateway.networking.k8s.io/v1beta1   true         ReferenceGrant
applicationnetworkpolicies          anp          networking.k8s.aws/v1alpha1         true         ApplicationNetworkPolicy
clusternetworkpolicies              cnp          networking.k8s.aws/v1alpha1         false        ClusterNetworkPolicy
clusterpolicyendpoints              cpe          networking.k8s.aws/v1alpha1         false        ClusterPolicyEndpoint
policyendpoints                                  networking.k8s.aws/v1alpha1         true         PolicyEndpoint
ingressclasses                                   networking.k8s.io/v1                false        IngressClass
ingresses                           ing          networking.k8s.io/v1                true         Ingress
ipaddresses                         ip           networking.k8s.io/v1                false        IPAddress
networkpolicies                     netpol       networking.k8s.io/v1                true         NetworkPolicy
servicecidrs                                     networking.k8s.io/v1                false        ServiceCIDR

# Kong Installation
helm install kong kong/ingress --create-namespace -n kong --version=0.24.0

# Resources Analysis
kubectl get all -n kong
NAME                                   READY   STATUS    RESTARTS   AGE
pod/kong-controller-76b96c895c-lwx4x   1/1     Running   0          64s
pod/kong-gateway-7778b48867-v89fr      1/1     Running   0          64s

NAME                                         TYPE           CLUSTER-IP      EXTERNAL-IP                                                                    PORT(S)                         AGE
service/kong-controller-metrics              ClusterIP      10.100.170.84   <none>                                                                         10255/TCP,10254/TCP             65s
service/kong-controller-validation-webhook   ClusterIP      10.100.254.63   <none>                                                                         443/TCP                         65s
service/kong-gateway-admin                   ClusterIP      None            <none>                                                                         8444/TCP                        65s
service/kong-gateway-manager                 NodePort       10.100.62.96    <none>                                                                         8002:30339/TCP,8445:30602/TCP   65s
service/kong-gateway-proxy                   LoadBalancer   10.100.103.75   a8b0c28e3de734f34a7b1817fb2cf6e5-1916500489.ap-southeast-1.elb.amazonaws.com   80:31192/TCP,443:30243/TCP      65s

NAME                              READY   UP-TO-DATE   AVAILABLE   AGE
deployment.apps/kong-controller   1/1     1            1           66s
deployment.apps/kong-gateway      1/1     1            1           66s

NAME                                         DESIRED   CURRENT   READY   AGE
replicaset.apps/kong-controller-76b96c895c   1         1         1       66s
replicaset.apps/kong-gateway-7778b48867      1         1         1       66s

kubectl get deployment kong-controller -n kong -o yaml | grep image
        image: kong/kubernetes-ingress-controller:3.5
        imagePullPolicy: IfNotPresent
kubectl get deployment kong-gateway -n kong -o yaml | grep image
        image: kong:3.9
        imagePullPolicy: IfNotPresent

# Install Gateway & GatewayClass
kubectl apply -f 0-gatewayclass.yaml
kubectl apply -f 1-kong-api-gateway.yaml

# Get GatewayClass
kubectl get gc -o yaml
apiVersion: v1
items:
- apiVersion: gateway.networking.k8s.io/v1
  kind: GatewayClass
  metadata:
    annotations:
      konghq.com/gatewayclass-unmanaged: "true"
      kubectl.kubernetes.io/last-applied-configuration: |
        {"apiVersion":"gateway.networking.k8s.io/v1","kind":"GatewayClass","metadata":{"annotations":{"konghq.com/gatewayclass-unmanaged":"true"},"name":"kong"},"spec":{"controllerName":"konghq.com/kic-gateway-controller"}}
    creationTimestamp: "2026-04-27T07:25:57Z"
    generation: 1
    name: kong
    resourceVersion: "18906"
    uid: cd54038a-1c2c-4279-828a-b89c2f91f601
  spec:
    controllerName: konghq.com/kic-gateway-controller
  status:
    conditions:
    - lastTransitionTime: "2026-04-27T07:25:57Z"
      message: the gatewayclass has been accepted by the controller
      observedGeneration: 1
      reason: Accepted
      status: "True"
      type: Accepted
kind: List
metadata:
  resourceVersion: ""

kubectl get gateway 
NAME                       CLASS   ADDRESS                                                                        PROGRAMMED   AGE
central-kong-api-gateway   kong    a8b0c28e3de734f34a7b1817fb2cf6e5-1916500489.ap-southeast-1.elb.amazonaws.com   True         114s

# Get Gateway
kubectl get gateway -o yaml
apiVersion: v1
items:
- apiVersion: gateway.networking.k8s.io/v1
  kind: Gateway
  metadata:
    annotations:
      konghq.com/publish-service: kong/kong-gateway-proxy
      kubectl.kubernetes.io/last-applied-configuration: |
        {"apiVersion":"gateway.networking.k8s.io/v1beta1","kind":"Gateway","metadata":{"annotations":{},"name":"central-kong-api-gateway","namespace":"default"},"spec":{"gatewayClassName":"kong","listeners":[{"allowedRoutes":{"namespaces":{"from":"All"}},"name":"http","port":80,"protocol":"HTTP"}]}}
    creationTimestamp: "2026-04-27T07:26:00Z"
    generation: 1
    name: central-kong-api-gateway
    namespace: default
    resourceVersion: "18917"
    uid: 1764385c-b030-438f-a0da-e5c2493fcd48
  spec:
    gatewayClassName: kong
    listeners:
    - allowedRoutes:
        namespaces:
          from: All
      name: http
      port: 80
      protocol: HTTP
  status:
    addresses:
    - type: Hostname
      value: a8b0c28e3de734f34a7b1817fb2cf6e5-1916500489.ap-southeast-1.elb.amazonaws.com

# Get all resources in kong namespace
kubectl get all -n kong
NAME                                   READY   STATUS    RESTARTS   AGE
pod/kong-controller-76b96c895c-lwx4x   1/1     Running   0          28m
pod/kong-gateway-7778b48867-v89fr      1/1     Running   0          28m

NAME                                         TYPE           CLUSTER-IP      EXTERNAL-IP                                                                    PORT(S)                         AGE
service/kong-controller-metrics              ClusterIP      10.100.170.84   <none>                                                                         10255/TCP,10254/TCP             28m
service/kong-controller-validation-webhook   ClusterIP      10.100.254.63   <none>                                                                         443/TCP                         28m
service/kong-gateway-admin                   ClusterIP      None            <none>                                                                         8444/TCP                        28m
service/kong-gateway-manager                 NodePort       10.100.62.96    <none>                                                                         8002:30339/TCP,8445:30602/TCP   28m
service/kong-gateway-proxy                   LoadBalancer   10.100.103.75   a8b0c28e3de734f34a7b1817fb2cf6e5-1916500489.ap-southeast-1.elb.amazonaws.com   80:31192/TCP,443:30243/TCP      28m

NAME                              READY   UP-TO-DATE   AVAILABLE   AGE
deployment.apps/kong-controller   1/1     1            1           28m
deployment.apps/kong-gateway      1/1     1            1           28m

NAME                                         DESIRED   CURRENT   READY   AGE
replicaset.apps/kong-controller-76b96c895c   1         1         1       28m
replicaset.apps/kong-gateway-7778b48867      1         1         1       28m