#!/bin/bash
set -xeuEo pipefail

CTX_EXTERNAL_CLUSTER="s.adams@f5.com@remote-cp.us-west-2.eksctl.io"
CTX_REMOTE_CLUSTER="s.adams@f5.com@remote-dp-1.us-west-2.eksctl.io"
export EXTERNAL_CLUSTER_NAME=remote-cp
export REMOTE_CLUSTER_NAME=remote-dp-1
ISTIO_VERSION="${ISTIO_VERSION:-1.11.2}"

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" &> /dev/null && pwd)"

# Download istio to AM downloads dir
cd ~/aspenmesh/downloads || exit
curl -L https://istio.io/downloadIstio | ISTIO_VERSION=$ISTIO_VERSION TARGET_ARCH=x86_64 sh -
cd ~/aspenmesh/downloads/istio-"$ISTIO_VERSION" || exit

# Set path to include istioctl binary
export PATH=$(pwd)/bin:$PATH

# # FOLLOWING DOCS FROM HERE: https://istio.io/latest/docs/setup/install/external-controlplane/
istioctl install -f "$DIR"/controlplane-gateway.yaml --context="${CTX_EXTERNAL_CLUSTER}" -y
kubectl wait --for=condition=available --timeout=600s deployment/istio-ingressgateway -n istio-system

GW_HOSTNAME=$(kubectl get service istio-eastwestgateway \
    --namespace istio-system \
    -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')

# AWS takes some time to for route53 records to propagate
echo "Waiting for ingress gateway to come online."
while true; do
    STATUS2=$(curl --silent \
        --output /dev/null \
        --write-out "%{http_code}\n" \
        "http://$GW_HOSTNAME:15021/healthz/ready" || true)
    if [[ $STATUS2 == 200 ]]; then
        break
    fi
    sleep 5
done

# Patch the gateway w/ an IP address
LB_IP=$(nslookup "$GW_HOSTNAME" | grep -E -o "([0-9]{1,3}[\.]){3}[0-9]{1,3}" | tail -1)
kubectl patch svc -n istio-system istio-ingressgateway -p "{\"spec\":{\"externalIPs\": [\"$LB_IP\"]}}"

export SSL_SECRET_NAME=gateway-cred

openssl req -x509 -sha256 -nodes -days 365 -newkey rsa:2048 -subj "/C=US/ST=Colorado/L=Longmont/O=Aspen Mesh/CN=''" -keyout gw.key -out gw.crt
openssl req -out $LB_IP.csr -newkey rsa:2048 -nodes -keyout $LB_IP.key -subj "/C=US/ST=Colorado/L=Longmont/O=Aspen Mesh/CN=''"
openssl x509 -req -days 365 -CA gw.crt -CAkey gw.key -set_serial 0 -in $LB_IP.csr -out $LB_IP.crt
kubectl create -n istio-system secret tls "$SSL_SECRET_NAME" --key=httpbin.example.com.key --cert=httpbin.example.com.crt

export EXTERNAL_ISTIOD_ADDR=$(kubectl get service istio-ingressgateway \
                                --namespace istio-system \
                                -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')

envsubst < "$DIR"/remote-config-cluster.yaml > /tmp/remote-config-cluster.yaml
kubectl create namespace external-istiod --context="${CTX_REMOTE_CLUSTER}"
istioctl manifest generate -f /tmp/remote-config-cluster.yaml | kubectl apply --context="${CTX_REMOTE_CLUSTER}" -f -
kubectl get mutatingwebhookconfiguration --context="${CTX_REMOTE_CLUSTER}"

kubectl create namespace external-istiod --context="${CTX_EXTERNAL_CLUSTER}"
kubectl create sa istiod-service-account -n external-istiod --context="${CTX_EXTERNAL_CLUSTER}"
istioctl x create-remote-secret \
  --context="${CTX_REMOTE_CLUSTER}" \
  --type=config \
  --namespace=external-istiod \
  --service-account=istiod \
  --create-service-account=false | \
  kubectl apply -f - --context="${CTX_EXTERNAL_CLUSTER}"


envsubst < "$DIR"/external-istiod.yaml > /tmp/external-istiod.yaml
istioctl install -f /tmp/external-istiod.yaml --context="${CTX_EXTERNAL_CLUSTER}" -y

envsubst < "$DIR"/external-istiod-gw.yaml > /tmp/external-istiod-gw.yaml
kubectl apply -f /tmp/external-istiod-gw.yaml --context="${CTX_EXTERNAL_CLUSTER}"

# Not sure if we need to patch the IP like for multi-cluster yet.
# # AWS takes some time to get the NLB up and running
# echo "Waiting for ingress gateway to come online."
# while true; do
#     STATUS2=$(curl --silent \
#         --output /dev/null \
#         --write-out "%{http_code}\n" \
#         "http://$GW_HOSTNAME/status/200" || true)
#     if [[ $STATUS2 == 200 ]]; then
#         break
#     fi
#     sleep 5
# done

# # Patch ingress gateway w/ IP, grab last 'Address' from nslookup
# export EXTERNAL_ISTIOD_ADDR=$(nslookup "$GW_HOSTNAME" | grep -E -o "([0-9]{1,3}[\.]){3}[0-9]{1,3}" | tail -1)
# kubectl patch svc -n istio-system istio-eastwestgateway -p "{\"spec\":{\"externalIPs\": [\"$EXTERNAL_ISTIOD_ADDR\"]}}"
export EXTERNAL_ISTIOD_ADDR="35.85.251.199"

# export KUBECONFIG=$CTX_REMOTE_CLUSTER
# # kubectl create namespace external-istiod
# envsubst < "$DIR"/overrides/external_istiod.yaml > /tmp/external_istiod.yaml
# helm install external-istiod manifests/charts/istiod-remote --namespace external-istiod --values /tmp/external_istiod.yaml

# istioctl x create-remote-secret \
#   --type=config \
#   --namespace=external-istiod \
#   --service-account=istiod \
#   --create-service-account=false > /tmp/remote_secret.yaml

export KUBECONFIG=$CTX_EXTERNAL_CLUSTER
# kubectl create namespace external-istiod
# kubectl create sa istiod-service-account -n external-istiod
# kubectl apply -f /tmp/remote_secret.yaml

# envsubst < "$DIR"/external-istiod.yaml > /tmp/external-istiod.yaml
# istioctl install -f /tmp/external-istiod.yaml

# export SSL_SECRET_NAME=istio-ingressgateway-certs
# envsubst < "$DIR"/external-istiod-gw.yaml > /tmp/external-istiod-gw.yaml
# kubectl apply -f /tmp/external-istiod-gw.yaml

# export KUBECONFIG=$CTX_REMOTE_CLUSTER
# kubectl create namespace sample
# kubectl label namespace sample istio-injection=enabled
# kubectl apply -f samples/helloworld/helloworld.yaml -l service=helloworld -n sample
# kubectl apply -f samples/helloworld/helloworld.yaml -l version=v1 -n sample
# kubectl apply -f samples/sleep/sleep.yaml -n sample

# istioctl manifest generate -f remote-config-cluster.yaml | kubectl apply -f -
# ingressgateway-certs:                                                                                                                                                  │
#     Type:        Secret (a volume populated by a Secret)                                                                                                                 │
#     SecretName:  istio-ingressgateway-certs                                                                                                                              │
#     Optional:    true                                                                                                                                                    │
#   ingressgateway-ca-certs:                                                                                                                                               │
#     Type:        Secret (a volume populated by a Secret)                                                                                                                 │
#     SecretName:  istio-ingressgateway-ca-certs                                                                                                                           │
#     Optional:    true   