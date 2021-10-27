#!/usr/bin/env bash

set -xeuEo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" &> /dev/null && pwd)"

set +u # Allow referencing unbound variable $CLUSTER
if [[ -z ${CLUSTER} ]]; then
  export CLUSTER_NAME=${1:?"cluster name is required"}
else
  export CLUSTER_NAME=${CLUSTER}
fi

ASPENMESH_HOME="$HOME/aspenmesh"
CLUSTER_ROOT_PATH="${CLUSTER_ROOT_PATH:-${ASPENMESH_HOME}/clusters}"
CLUSTER_PATH="$CLUSTER_ROOT_PATH/$CLUSTER_NAME"
mkdir -p "$CLUSTER_PATH"
KUBECONFIG="$CLUSTER_PATH/kube.config"
set -u

INSTANCE_TYPE=${INSTANCE_TYPE:=t2.medium}
MIN_NODES=${MIN_NODES:-"1"}
MAX_NODES=${MAX_NODES:-"3"}
MAX_PODS_PER_NODE=${MAX_PODS_PER_NODE:-"50"}
K8S_VERSION="${K8S_VERSION:-1.19}"

date

eksctl create cluster \
  --name="$CLUSTER_NAME" \
  --version="$K8S_VERSION" \
  --node-type="$INSTANCE_TYPE" \
  --nodes-min="$MIN_NODES" \
  --nodes-max="$MAX_NODES" \
  --max-pods-per-node="$MAX_PODS_PER_NODE" \
  --ssh-public-key="$HOME/.ssh/id_rsa.pub" \
  --asg-access \
  --with-oidc \
  --kubeconfig="$KUBECONFIG"

eksctl create iamserviceaccount \
  --cluster="$CLUSTER_NAME" \
  --namespace=kube-system \
  --name=cluster-autoscaler \
  --attach-policy-arn=arn:aws:iam::715707337212:policy/AmazonEKSClusterAutoscalerPolicy \
  --override-existing-serviceaccounts \
  --approve

kubectl apply --kubeconfig="$KUBECONFIG" \
    -f https://raw.githubusercontent.com/kubernetes/autoscaler/master/cluster-autoscaler/cloudprovider/aws/examples/cluster-autoscaler-autodiscover.yaml

export K8S_VERSION=$(kubectl --kubeconfig=$KUBECONFIG version --short | grep 'Server Version:' | sed 's/[^0-9.]*\([0-9.]*\).*/\1/' | cut -d. -f1,2)
export AUTOSCALER_VERSION=$(curl -s "https://api.github.com/repos/kubernetes/autoscaler/releases" | grep '"tag_name":' | sed -s 's/.*-\([0-9][0-9\.]*\).*/\1/' | grep -m1 ${K8S_VERSION})

kubectl -n kube-system --kubeconfig=$KUBECONFIG \
    set image deployment.apps/cluster-autoscaler \
    cluster-autoscaler=us.gcr.io/k8s-artifacts-prod/autoscaling/cluster-autoscaler:v${AUTOSCALER_VERSION}

kubectl patch --kubeconfig=$KUBECONFIG deployment cluster-autoscaler \
  -n kube-system \
  -p '{"spec":{"template":{"metadata":{"annotations":{"cluster-autoscaler.kubernetes.io/safe-to-evict": "false"}}}}}'

kubectl patch --kubeconfig=$KUBECONFIG deployment cluster-autoscaler \
   -n kube-system \
   --type=json -p="[{\"op\": \"replace\", \"path\": \"/spec/template/spec/containers/0/command/6\", \"value\": \"--node-group-auto-discovery=asg:tag=k8s.io/cluster-autoscaler/enabled,k8s.io/cluster-autoscaler/${CLUSTER_NAME}\" }]"

kubectl patch --kubeconfig=$KUBECONFIG deployment cluster-autoscaler \
   -n kube-system \
   --type=json -p='[{"op": "add", "path": "/spec/template/spec/containers/0/command/-", "value": "--balance-similar-node-groups" }]'

kubectl patch --kubeconfig=$KUBECONFIG deployment cluster-autoscaler \
   -n kube-system \
   --type=json -p='[{"op": "add", "path": "/spec/template/spec/containers/0/command/-", "value": "--skip-nodes-with-system-pods=false" }]'

if [[ -n ${DNS_DOMAIN} ]]; then
  echo "Setting up external-dns access for ${DNS_DOMAIN}"
  kubectl create ns external-dns
  eksctl create iamserviceaccount \
    --cluster=$CLUSTER_NAME \
    --name=external-dns \
    --namespace=external-dns \
    --attach-policy-arn=arn:aws:iam::715707337212:policy/AllowExternalDNSUpdates \
    --override-existing-serviceaccounts \
    --approve

  export DNS_DOMAIN="$DNS_DOMAIN"
  envsubst < "$DIR"/external-dns.yaml > /tmp/"$CLUSTER_NAME"-external-dns.yaml
  kubectl apply --kubeconfig=$KUBECONFIG -f /tmp/"$CLUSTER_NAME"-external-dns.yaml
  kubectl wait --for=condition=available --timeout=10s deployments external-dns -n external-dns
fi
