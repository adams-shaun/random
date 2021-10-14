#!/bin/bash
set -xeuEo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" &> /dev/null && pwd)"

# FOLLOWING DOCS FROM HERE: https://istio.io/latest/docs/setup/install/external-controlplane/

# This script uses kubectl contexts, be sure to set KUBECONFIG accordingly
# KUBECONFIG=<kube1path>:<kube2path>:...
# kubectl config get-contexts 
if [[ -z ${CTX_EXTERNAL_CLUSTER+z} || -z ${CTX_REMOTE_CLUSTER+z} || -z ${CTX_SECOND_CLUSTER+z} ]]; then
    echo "Missing kube contexts as input env vars"
    exit 1
fi

# We use external-dns as well as signed certs, so this is required.
if [[ -z ${DNS_DOMAIN+z} ]]; then
    echo "This demo install assumes external-dns is installed and DNS_DOMAIN env provided"
    exit 1
fi

# export CTX_EXTERNAL_CLUSTER="s.adams@f5.com@shaun-ext.us-west-2.eksctl.io"
# export CTX_REMOTE_CLUSTER="s.adams@f5.com@shaun-remote.us-west-2.eksctl.io"
# export CTX_SECOND_CLUSTER="s.adams@f5.com@shaun-remote-2.us-west-2.eksctl.io"

export EXTERNAL_CLUSTER_NAME="${EXTERNAL_CLUSTER_NAME:-shaun-ext}"
export REMOTE_CLUSTER_NAME="${REMOTE_CLUSTER_NAME:-shaun-remote}"
export SECOND_CLUSTER_NAME="${SECOND_CLUSTER_NAME:-shaun-remote-2}"
export DNS_DOMAIN="${DNS_DOMAIN:-}"

# Download istio to AM downloads dir
ISTIO_VERSION="${ISTIO_VERSION:-1.11.2}"
cd ~/aspenmesh/downloads
curl -L https://istio.io/downloadIstio | ISTIO_VERSION=$ISTIO_VERSION TARGET_ARCH=x86_64 sh -
cd ~/aspenmesh/downloads/istio-"$ISTIO_VERSION"

# Set path to include istioctl binary
export PATH=$(pwd)/bin:$PATH

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

# SSL_SECRET_NAME is used for termination of requests to istiod at the gateway
export SSL_SECRET_NAME=gw-cert
export EXTERNAL_ISTIOD_ADDR="cp.${DNS_DOMAIN}"

# we need to install cert-manager to generate the TLS cert
# policy is pre-made according to the docs
eksctl create iamserviceaccount \
    --name cert-manager \
    --namespace cert-manager \
    --cluster shaun-ext \
    --attach-policy-arn "arn:aws:iam::715707337212:policy/cert-manager-policy" \
    --approve \
    --override-existing-serviceaccounts
# install via helm
helm repo add jetstack https://charts.jetstack.io
helm repo update
helm upgrade cert-manager jetstack/cert-manager \
  --install \
  --kube-context "${CTX_EXTERNAL_CLUSTER}" \
  --namespace cert-manager \
  --create-namespace \
  --values "$DIR/cert-values.yaml" \
  --wait

kubectl apply -f "$DIR/cert-issuer.yaml"
sleep 30 # TODO: there must be a better way than just waiting
envsubst < "$DIR/cert.yaml" | kubectl apply -f -
sleep 180

# Generate the TLS cert for gateway termination
# openssl genrsa -out ca.key 2048
# openssl req -new -x509 -days 365 -key ca.key -subj "/C=CN/ST=GD/L=SZ/O=Acme, Inc./CN=Acme Root CA" -out ca.crt
# openssl req -newkey rsa:2048 -nodes -keyout server.key -subj "/C=CN/ST=GD/L=SZ/O=Acme, Inc./CN=*.$DNS_DOMAIN" -out server.csr
# openssl x509 -req -extfile <(printf "subjectAltName=DNS:$DNS_DOMAIN,DNS:$EXTERNAL_ISTIOD_ADDR") -days 365 -in server.csr -CA ca.crt -CAkey ca.key -CAcreateserial -out server.crt
# kubectl create -n istio-system secret tls "$SSL_SECRET_NAME" --key=server.key --cert=server.crt --context="${CTX_EXTERNAL_CLUSTER}"

# Set up the remote config cluster
envsubst < "$DIR"/remote-config-cluster.yaml > /tmp/remote-config-cluster.yaml
kubectl create namespace external-istiod --context="${CTX_REMOTE_CLUSTER}"
istioctl manifest generate -f /tmp/remote-config-cluster.yaml | kubectl apply --context="${CTX_REMOTE_CLUSTER}" -f -
kubectl get mutatingwebhookconfiguration --context="${CTX_REMOTE_CLUSTER}"

# Set up the control plane in the external cluster
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
# Internal error occurred: failed calling webhook "namespace.sidecar-injector.istio.i │
# │ o": Post "https://cp.shaun.dev.twistio.io:15017/inject/:ENV:cluster=shaun-remote:EN │
# │ V:net=network1?timeout=10s": x509: certificate signed by unknown authority

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
# the remote istiod.
# 2021-10-11T13:57:49.136559Z    warn    ca    ca request failed, starting attempt 4 in 830.723933ms
# 2021-10-11T13:57:49.967619Z    warn    sds    failed to warm certificate: failed to generate workload certificate: create certificate: rpc error: code = Unavailable desc = connection error: desc = "transport: authentication handshake failed: x509: certificate signed by unknown authority"

# To fix this, one option is to modify the injection
# template to include the gateway TLS cert.

# Create a configmap containing the CA cert
# The template in external-istiod.yaml will reference the mounted location
# in the injected pod.  There's a couple tricky bits here...
# First, programatically editing the injection template in the external
# cluster configmap is quite tricky (it is in helm)
# The second problem is the configmap will need to be copied
# for all namespaces in the remote cluster.
# kubectl create configmap ca-store -n external-istiod --from-file=server.crt --context="${CTX_REMOTE_CLUSTER}"

# kubectl -n istio-system get configmap istio-sidecar-injector -o yaml --context="${CTX_EXTERNAL_CLUSTER}" > inject-template.yaml
# (here we edit the sidecar injection template)
#             volumeMounts:
            # - mountPath: /etc/ssl/certs
            #   name: gw-cert
            #   readOnly: true
        #   volumes:
        #   - name: gw-cert
        #     configMap:
        #       name: ca-store
        #       items:
        #       - key: server.crt
        #         path: ca-certificates.crt
# kubectl apply -f injection-template.yaml --context="${CTX_EXTERNAL_CLUSTER}"
# kubectl rollout restart deploy -n istio-external --context="${CTX_EXTERNAL_CLUSTER}"

# Deploy sample application
kubectl create --context="${CTX_REMOTE_CLUSTER}" namespace sample
kubectl label --context="${CTX_REMOTE_CLUSTER}" namespace sample istio-injection=enabled
kubectl apply -f samples/helloworld/helloworld.yaml -l service=helloworld -n sample --context="${CTX_REMOTE_CLUSTER}"
kubectl apply -f samples/helloworld/helloworld.yaml -l version=v1 -n sample --context="${CTX_REMOTE_CLUSTER}"
kubectl apply -f samples/sleep/sleep.yaml -n sample --context="${CTX_REMOTE_CLUSTER}"
kubectl apply -f samples/helloworld/helloworld-gateway.yaml -n sample --context="${CTX_REMOTE_CLUSTER}"

# Enable gateways
istioctl install -f "$DIR/istio-ingressgateway.yaml" --context="${CTX_REMOTE_CLUSTER}" -y
kubectl create ns external-istiod --context="${CTX_REMOTE_CLUSTER}"

# Register the second cluster
envsubst < "$DIR/second-config-cluster.yaml" > /tmp/second-config-cluster.yaml
istioctl manifest generate -f /tmp/second-config-cluster.yaml | kubectl apply --context="${CTX_SECOND_CLUSTER}" -f -
istioctl x create-remote-secret \
  --context="${CTX_SECOND_CLUSTER}" \
  --name="${SECOND_CLUSTER_NAME}" \
  --type=remote \
  --namespace=external-istiod \
  --create-service-account=false | \
  kubectl apply -f - --context="${CTX_REMOTE_CLUSTER}"
kubectl create ns external-istiod --context="${CTX_SECOND_CLUSTER}"
# interesting read here: https://github.com/istio/istio/issues/31946

# Setup east-west gateways
samples/multicluster/gen-eastwest-gateway.sh \
    --mesh mesh1 --cluster "${REMOTE_CLUSTER_NAME}" --network network1 > eastwest-gateway-1.yaml
istioctl manifest generate -f eastwest-gateway-1.yaml \
    --set values.global.istioNamespace=external-istiod | \
    kubectl apply --context="${CTX_REMOTE_CLUSTER}" -f -

samples/multicluster/gen-eastwest-gateway.sh \
    --mesh mesh1 --cluster "${SECOND_CLUSTER_NAME}" --network network2 > eastwest-gateway-2.yaml
istioctl manifest generate -f eastwest-gateway-2.yaml \
    --set values.global.istioNamespace=external-istiod | \
    kubectl apply --context="${CTX_SECOND_CLUSTER}" -f -

# Next we need to patch the east west gateway external IPs (similar to multicluster)
EW_HOSTNAME1=$(kubectl get service istio-eastwestgateway \
    --namespace external-istiod \
    --context="${CTX_REMOTE_CLUSTER}" \
    -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')
EW_HOSTNAME2=$(kubectl get service istio-eastwestgateway \
    --namespace external-istiod \
    --context="${CTX_SECOND_CLUSTER}" \
    -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')

LB_IP=$(nslookup "$EW_HOSTNAME1" | grep -E -o "([0-9]{1,3}[\.]){3}[0-9]{1,3}" | tail -1)
kubectl patch svc -n external-istiod istio-eastwestgateway \
    --context="${CTX_REMOTE_CLUSTER}" \
    -p "{\"spec\":{\"externalIPs\": [\"$LB_IP\"]}}"
LB_IP=$(nslookup "$EW_HOSTNAME2" | grep -E -o "([0-9]{1,3}[\.]){3}[0-9]{1,3}" | tail -1)
kubectl patch svc -n external-istiod istio-eastwestgateway \
    --context="${CTX_SECOND_CLUSTER}" \
    -p "{\"spec\":{\"externalIPs\": [\"$LB_IP\"]}}"

kubectl --context="${CTX_REMOTE_CLUSTER}" apply -n external-istiod -f \
    samples/multicluster/expose-services.yaml

# Validation
kubectl create --context="${CTX_SECOND_CLUSTER}" namespace sample
kubectl label --context="${CTX_SECOND_CLUSTER}" namespace sample istio-injection=enabled
kubectl apply -f samples/helloworld/helloworld.yaml -l service=helloworld -n sample --context="${CTX_SECOND_CLUSTER}"
kubectl apply -f samples/helloworld/helloworld.yaml -l version=v2 -n sample --context="${CTX_SECOND_CLUSTER}"
kubectl apply -f samples/sleep/sleep.yaml -n sample --context="${CTX_SECOND_CLUSTER}"
