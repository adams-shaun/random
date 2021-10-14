#!/bin/bash

set -xeuEo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" &> /dev/null && pwd)"


export CLUSTER_NAME="${CLUSTER_NAME:-$(whoami)-eks}"
export CLUSTER_REGION="${CLUSTER_REGION:-us-west-2}"
export K8S_VERSION="${K8S_VERSION:-1.19}"
export NODE_SIZE="${NODE_SIZE:-t2.medium}"
export NODE_COUNT="${NODE_COUNT:-5}"

ASPENMESH_HOME="$HOME/aspenmesh"
CLUSTER_ROOT_PATH="${CLUSTER_ROOT_PATH:-${ASPENMESH_HOME}/clusters}"
CLUSTER_PATH="$CLUSTER_ROOT_PATH/$CLUSTER_NAME"

EKS_CONFIG_FILE="$CLUSTER_NAME"_eks.yaml

envsubst < "$DIR"/eks_template.yaml > "$EKS_CONFIG_FILE"
mkdir -p $CLUSTER_PATH

eksctl create cluster \
    --config-file="${EKS_CONFIG_FILE}" \
    --kubeconfig "$CLUSTER_PATH/kube.config"

export KUBECONFIG="$CLUSTER_PATH/kube.config"
