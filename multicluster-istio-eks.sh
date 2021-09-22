#!/bin/bash

export DIR="$(pwd)"

# Set kube files to switch between clusters
# Couldn't get kubectl to properly create multiple contexts by chaining these.
export KUBE1=/home/ubuntu/aspenmesh/clusters/shaun-west-1/kube.config
export KUBE2=/home/ubuntu/aspenmesh/clusters/shaun-west-2/kube.config
export KUBE3=/home/ubuntu/aspenmesh/clusters/shaun-east-1/kube.config

# # Download istio to AM downloads dir
# cd ~/aspenmesh/downloads || exit
# curl -L https://istio.io/downloadIstio | sh -
cd ~/aspenmesh/downloads/istio-1.11.2 || exit

# Need to apply change to CNI daemonset chart for OCP
# overlays:
#   - kind: DaemonSet
#     name: istio-cni-node
#     patches:
#       - path: spec.template.spec.containers[0].securityContext.privileged
#         value: true

# Generate new ca-cert
$DIR/gen-cert.sh
export ECC=$DIR/ecc

for kube in $KUBE1 $KUBE2 $KUBE3
do
    export KUBECONFIG=$kube
    kubectl get pod || exit
    kubectl create namespace istio-system

    # Install root cert in istio-system ns
    kubectl create secret generic cacerts -n istio-system \
        --from-file="$ECC/ca-cert.pem" \
        --from-file="$ECC/ca-key.pem" \
        --from-file="$ECC/root-cert.pem" \
        --from-file="$ECC/cert-chain.pem"

    if [[ $kube == "$KUBE1" ]]; then
        export NETWORK=network1
        export VALS=$DIR/eks1.yaml
    else
        export NETWORK=network2
        export VALS=$DIR/eks2.yaml
    fi

    # Label networks
    kubectl label namespace istio-system topology.istio.io/network=$NETWORK
    kubectl label --overwrite namespace default istio-injection=enabled

    # Install charts
    helm install -n istio-system istio-base ./manifests/charts/base
    helm install istiod manifests/charts/istio-control/istio-discovery -n istio-system --values "$VALS"
    helm install istio-eastwestgateway manifests/charts/gateways/istio-ingress --namespace istio-system --values "$VALS"

    # restart any deployments to get injection
    kubectl rollout restart deploy

done

# # Patch ingress gateway w/ IP
# nslookup $(kubectl get svc -n istio-system istio-eastwestgateway -o json | jq -r '.status.loadBalancer.ingress[].hostname')
# kubectl patch svc -n istio-system istio-eastwestgateway -p '{"spec":{"externalIPs": ["35.X.X.X"]}}'


# # Apply secrets
# istioctl x create-remote-secret --secret-name --name shaun-2 > /home/ubuntu/go/src/github.com/aspenmesh/random/c1secret.yaml