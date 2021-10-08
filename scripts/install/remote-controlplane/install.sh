#!/bin/bash
set -xeuEo pipefail

CTX_EXTERNAL_CLUSTER="s.adams@f5.com@shaun-ext.us-west-2.eksctl.io"
CTX_REMOTE_CLUSTER="s.adams@f5.com@shaun-remote.us-west-2.eksctl.io"
export EXTERNAL_CLUSTER_NAME=shaun-ext
export REMOTE_CLUSTER_NAME=shaun-remote
export DNS_DOMAIN="shaun.dev.twistio.io"

ISTIO_VERSION="${ISTIO_VERSION:-1.11.2}"

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" &> /dev/null && pwd)"

# Download istio to AM downloads dir
cd ~/aspenmesh/downloads
curl -L https://istio.io/downloadIstio | ISTIO_VERSION=$ISTIO_VERSION TARGET_ARCH=x86_64 sh -
cd ~/aspenmesh/downloads/istio-"$ISTIO_VERSION"

# Set path to include istioctl binary
export PATH=$(pwd)/bin:$PATH

# # FOLLOWING DOCS FROM HERE: https://istio.io/latest/docs/setup/install/external-controlplane/

# Install ingress GW and istiod into external (control plane) cluster
istioctl install -f "$DIR"/controlplane-gateway.yaml \
    --context="${CTX_EXTERNAL_CLUSTER}" -y
kubectl wait --for=condition=available --timeout=600s \
    deployment/istio-ingressgateway \
    -n istio-system \
    --context="${CTX_EXTERNAL_CLUSTER}"

GW_HOSTNAME=$(kubectl get service istio-ingressgateway \
    --namespace istio-system \
    --context="${CTX_EXTERNAL_CLUSTER}" \
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

export SSL_SECRET_NAME=gateway-cred
export EXTERNAL_ISTIOD_ADDR="cp.${DNS_DOMAIN}"

envsubst < "$DIR"/ready.yaml > /tmp/ready.yaml
kubectl apply -f /tmp/ready.yaml --context="${CTX_EXTERNAL_CLUSTER}"

openssl genrsa -out ca.key 2048
openssl req -new -x509 -days 365 -key ca.key -subj "/C=CN/ST=GD/L=SZ/O=Acme, Inc./CN=Acme Root CA" -out ca.crt
openssl req -newkey rsa:2048 -nodes -keyout server.key -subj "/C=CN/ST=GD/L=SZ/O=Acme, Inc./CN=*.$DNS_DOMAIN" -out server.csr
openssl x509 -req -extfile <(printf "subjectAltName=DNS:$DNS_DOMAIN,DNS:$EXTERNAL_ISTIOD_ADDR") -days 365 -in server.csr -CA ca.crt -CAkey ca.key -CAcreateserial -out server.crt
kubectl create -n istio-system secret tls "$SSL_SECRET_NAME" --key=server.key --cert=server.crt --context="${CTX_EXTERNAL_CLUSTER}"

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

# At this point, the sidecar injection won't work because the replicaset
# does not trust the TLS cert provided by the external ingress gw.
# Here we add the encoded CA cert into 'caBundle' entry of clientConfig options
# in the mutating webhook for injection.
# For more info, see comments here: https://github.com/istio/istio/issues/30899
# kubectl get mutatingwebhookconfiguration/istio-sidecar-injector-external-istiod \
#     -o json \
#     --context="${CTX_REMOTE_CLUSTER}" \
#     > /tmp/wh.json
# export CA_CERT=$(cat server.crt | base64 | tr -d '\n')
# jq --arg CA_CERT "$CA_CERT" '.webhooks = [ .webhooks[] | .clientConfig.caBundle = $CA_CERT]' /tmp/wh.json > /tmp/wh-patched.json
# kubectl apply -f /tmp/wh-patched.json --context="${CTX_REMOTE_CLUSTER}"

# The above allows the injection to proceed, but the proxy does not trust
# the remote istiod.  To fix this, one option is to modify the injection
# template to include the gateway TLS cert.

# Create a configmap containing the CA cert
# The template in external-istiod.yaml will reference the mounted location
# in the injected pod.  There's a couple tricky bits here...
# First, programatically editing the injection template in the external
# cluster configmap is quite tricky (it is in helm)
# The second problem is the configmap will need to be copied
# for all namespaces in the remote cluster.
# kubectl create configmap ca-store -n external-istiod --from-file=server.crt

# Another possible option is to use annotations to mount into pods
# annotations:                                                                                       
#   sidecar.istio.io/userVolumeMount: '[{"name":"my-cert", "mountPath":"/etc/my-cert", "readonly":true}]'
#   sidecar.istio.io/userVolume: '[{"name":"my-cert", "secret":{"secretName":"my-cert"}}]'