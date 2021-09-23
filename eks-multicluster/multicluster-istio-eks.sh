#!/bin/bash
set -xeuEo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" &> /dev/null && pwd)"

# # Set kube files to switch between clusters
# # Couldn't get kubectl to properly create multiple contexts by chaining these.
KUBE1=/home/ubuntu/aspenmesh/clusters/shaun-west-1/kube.config
KUBE2=/home/ubuntu/aspenmesh/clusters/shaun-west-2/kube.config
KUBE3=/home/ubuntu/aspenmesh/clusters/shaun-east-1/kube.config

# # Download istio to AM downloads dir
# cd ~/aspenmesh/downloads || exit
# curl -L https://istio.io/downloadIstio | sh -
cd ~/aspenmesh/downloads/istio-1.11.2 || exit
export PATH=$(pwd)/bin:$PATH

# Generate new ca-cert
"$DIR"/gen-cert.sh
ECC=$DIR/ecc

for kube in $KUBE1 $KUBE2 $KUBE3
do
    export KUBECONFIG=$kube
    kubectl get pod
    kubectl create namespace istio-system

    # Install root cert in istio-system ns
    kubectl create secret generic cacerts -n istio-system \
        --from-file="$ECC/ca-cert.pem" \
        --from-file="$ECC/ca-key.pem" \
        --from-file="$ECC/root-cert.pem" \
        --from-file="$ECC/cert-chain.pem"

    if [[ $kube == "$KUBE1" ]]; then
        NETWORK=network1
        VALS=$DIR/eks1.yaml
        INGRESS_VALS=$DIR/ingress1.yaml
    elif [[ $kube == "$KUBE2" ]]; then
        NETWORK=network2
        VALS=$DIR/eks2.yaml
        INGRESS_VALS=$DIR/ingress2.yaml
    else
        NETWORK=network3
        VALS=$DIR/eks3.yaml
        INGRESS_VALS=$DIR/ingress3.yaml
    fi

    # Label networks
    kubectl label namespace istio-system topology.istio.io/network=$NETWORK
    kubectl label --overwrite namespace default istio-injection=enabled

    # Install charts
    helm install -n istio-system istio-base ./manifests/charts/base
    helm install istiod manifests/charts/istio-control/istio-discovery -n istio-system --values "$VALS"

    # Install Ingress Gateways (n/s and e/w)
    helm install istio-ingressgateway manifests/charts/gateways/istio-ingress --namespace istio-system --values $INGRESS_VALS
    helm install istio-eastwestgateway manifests/charts/gateways/istio-ingress --namespace istio-system --values "$VALS"

    # restart any deployments to get injection
    kubectl rollout restart deploy

    # apply ready script
    kubectl apply -f "$DIR"/ready.yaml
done

for kube in $KUBE1 $KUBE2 $KUBE3
do
    export KUBECONFIG=$kube
    EW_HOSTNAME=$(kubectl get service istio-eastwestgateway \
        --namespace istio-system \
        -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')
    NS_HOSTNAME=$(kubectl get service istio-ingressgateway \
        --namespace istio-system \
        -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')

    # AWS takes some time to get the NLB up and running
    echo "Waiting for ingress gateway to come online."
    while true; do
        # STATUS1=$(curl --silent \
        #     --output /dev/null \
        #     --write-out "%{http_code}\n" \
        #     "http://$EW_HOSTNAME/status/200" || true)
        STATUS2=$(curl --silent \
            --output /dev/null \
            --write-out "%{http_code}\n" \
            "http://$NS_HOSTNAME/status/200" || true)
        if [[ $STATUS2 == 200 ]]; then
            break
        fi
        sleep 5
    done

    # Patch ingress gateway w/ IP, grab last 'Address' from nslookup
    LB_IP=$(nslookup $EW_HOSTNAME | grep -E -o "([0-9]{1,3}[\.]){3}[0-9]{1,3}" | tail -1)
    kubectl patch svc -n istio-system istio-eastwestgateway -p "{\"spec\":{\"externalIPs\": [\"$LB_IP\"]}}"
done

# # Apply secrets
export KUBECONFIG=$KUBE1
istioctl x create-remote-secret --name shaun-west-1 > /tmp/c1secret.yaml
export KUBECONFIG=$KUBE2
istioctl x create-remote-secret --name shaun-west-2 > /tmp/c2secret.yaml
export KUBECONFIG=$KUBE3
istioctl x create-remote-secret --name shaun-east-1 > /tmp/c3secret.yaml

export KUBECONFIG=$KUBE1
kubectl apply -f gw.yaml
kubectl apply -f /tmp/c2secret.yaml
kubectl apply -f /tmp/c3secret.yaml
kubectl rollout restart deploy
kubectl rollout restart deploy -n istio-system
export KUBECONFIG=$KUBE2
kubectl apply -f gw.yaml
kubectl apply -f /tmp/c1secret.yaml
kubectl apply -f /tmp/c3secret.yaml
kubectl rollout restart deploy
kubectl rollout restart deploy -n istio-system
export KUBECONFIG=$KUBE3
kubectl apply -f gw.yaml
kubectl apply -f /tmp/c1secret.yaml
kubectl apply -f /tmp/c2secret.yaml
kubectl rollout restart deploy
kubectl rollout restart deploy -n istio-system