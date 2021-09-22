#!/bin/bash

export DIR="$(pwd)"

# Set kube files to switch between clusters
# Couldn't get kubectl to properly create multiple contexts by chaining these.
export KUBE1=/home/ubuntu/aspenmesh/clusters/shaun-west-1/kube.config
export KUBE2=/home/ubuntu/aspenmesh/clusters/shaun-west-2/kube.config

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

for kube in $KUBE1 $KUBE2
do
    kubectl create namespace istio-system --kubeconfig=$kube
    kubectl create secret generic cacerts -n istio-system --kubeconfig=$kube \
        --from-file="$ECC/ca-cert.pem" \
        --from-file="$ECC/ca-key.pem" \
        --from-file="$ECC/root-cert.pem" \
        --from-file="$ECC/cert-chain.pem"
    helm install --kubeconfig=$kube -n istio-system istio-base ./manifests/charts/base
    # for OCP
    helm install --kubeconfig=$kube istio-cni ./manifests/charts/istio-cni -n kube-system --set components.cni.enabled=true
done

kubectl --kubeconfig=$KUBE1 label namespace istio-system topology.istio.io/network=network1
kubectl --kubeconfig=$KUBE2 label namespace istio-system topology.istio.io/network=network2

helm install --kubeconfig=$KUBE1 -n istio-system istiod ./manifests/charts/istio-control/istio-discovery -f $DIR/mc1.yaml
helm install --kubeconfig=$KUBE2 -n istio-system istiod ./manifests/charts/istio-control/istio-discovery -f $DIR/mc2.yaml

# Add NetworkAttachmentDefinition for any namespaces needing injection
kubectl apply --kubeconfig=$KUBE1 -f $DIR/nad.yaml
kubectl apply --kubeconfig=$KUBE2 -f $DIR/nad.yaml


helm install --kubeconfig=$KUBE1 -n istio-system ewgw ./manifests/charts/gateways/istio-ingress -f /home/ubuntu/go/src/github.com/aspenmesh/random/mc1.yaml
kubectl apply --kubeconfig=$KUBE1 -n istio-system -f samples/multicluster/expose-services.yaml 

helm install --kubeconfig=$KUBE2 -n istio-system ewgw ./manifests/charts/gateways/istio-ingress -f /home/ubuntu/go/src/github.com/aspenmesh/random/mc2.yaml
kubectl apply --kubeconfig=$KUBE1 -n istio-system -f samples/multicluster/expose-services.yaml 

# with kube2
istioctl x create-remote-secret --secret-name istio-reader-service-account-token-lcp2t --name shaun-2 > /home/ubuntu/go/src/github.com/aspenmesh/random/c1secret.yaml