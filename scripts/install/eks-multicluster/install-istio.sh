#!/bin/bash
set -xeuEo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" &> /dev/null && pwd)"

if [[ -z ${KUBE1+z} || -z ${KUBE2+z} || -z ${KUBE3+z} ]]; then
    echo "Missing kubeconfigs as input env vars"
    exit 1
fi

C1NAME="${C1NAME:-cluster1}"
C2NAME="${C2NAME:-cluster2}"
C3NAME="${C3NAME:-cluster3}"

restart_deploys() {
    kubectl rollout restart deploy
    kubectl rollout restart deploy -n istio-system
    kubectl rollout restart deploy -n istio-ready
}

# if [[ -z ${C1NAME+z} || -z ${C2NAME+z} || -z ${C3NAME+z} ]]; then
#     echo "Missing cluster names as input env vars"
#     exit 1
# fi

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
        export NETWORK_NAME=network1
        export CLUSTER_NAME=$C1NAME

    elif [[ $kube == "$KUBE2" ]]; then
        export NETWORK_NAME=network2
        export CLUSTER_NAME=$C2NAME
    else
        export NETWORK_NAME=network3
        export CLUSTER_NAME=$C3NAME
    fi

    VALS=$DIR/overrides/istiod_overrides.yaml
    INGRESS_VALS=$DIR/overrides/ingress_overrides.yaml

    # Label networks
    kubectl label namespace istio-system topology.istio.io/network=$NETWORK_NAME
    kubectl label --overwrite namespace default istio-injection=enabled

    # Install charts
    helm install -n istio-system istio-base ./manifests/charts/base
    envsubst < "$VALS" > /tmp/base_values.yaml
    helm install istiod manifests/charts/istio-control/istio-discovery -n istio-system --values /tmp/base_values.yaml

    # Install Ingress Gateways (n/s and e/w)
    envsubst < "$INGRESS_VALS" > /tmp/ingress_values.yaml
    helm install istio-ingressgateway manifests/charts/gateways/istio-ingress --namespace istio-system --values /tmp/ingress_values.yaml
    helm install istio-eastwestgateway manifests/charts/gateways/istio-ingress --namespace istio-system --values /tmp/base_values.yaml

    # apply ready script
    kubectl apply -f "$DIR"/ready.yaml

    # restart any deployments to get injection/proxy settings to take effect
    restart_deploys
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
    LB_IP=$(nslookup "$EW_HOSTNAME" | grep -E -o "([0-9]{1,3}[\.]){3}[0-9]{1,3}" | tail -1)
    kubectl patch svc -n istio-system istio-eastwestgateway -p "{\"spec\":{\"externalIPs\": [\"$LB_IP\"]}}"
done

# # Apply secrets
export KUBECONFIG=$KUBE1
istioctl x create-remote-secret --name $C1NAME > /tmp/c1secret.yaml
export KUBECONFIG=$KUBE2
istioctl x create-remote-secret --name $C2NAME > /tmp/c2secret.yaml
export KUBECONFIG=$KUBE3
istioctl x create-remote-secret --name $C3NAME > /tmp/c3secret.yaml

export KUBECONFIG=$KUBE1
kubectl apply -f "$DIR"/gw.yaml
kubectl apply -f /tmp/c2secret.yaml
kubectl apply -f /tmp/c3secret.yaml
restart_deploys
export KUBECONFIG=$KUBE2
kubectl apply -f "$DIR"/gw.yaml
kubectl apply -f /tmp/c1secret.yaml
kubectl apply -f /tmp/c3secret.yaml
restart_deploys
export KUBECONFIG=$KUBE3
kubectl apply -f "$DIR"/gw.yaml
kubectl apply -f /tmp/c1secret.yaml
kubectl apply -f /tmp/c2secret.yaml
restart_deploys

