#!/bin/bash

set -xeuEo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" &> /dev/null && pwd)"

# Creates three clusters for istio multicluster install
# CXNAME, KUBEX needed for the install istio multicluster script.
export CLUSTER_NAME="$(whoami)-us-west-1"
export CLUSTER_REGION=us-west-1
"$DIR"/new_eks.sh &

export CLUSTER_NAME="$(whoami)-us-west-2"
export CLUSTER_REGION=us-west-2
"$DIR"/new_eks.sh &

export CLUSTER_NAME="$(whoami)-us-east-1"
export CLUSTER_REGION=us-east-1
"$DIR"/new_eks.sh &