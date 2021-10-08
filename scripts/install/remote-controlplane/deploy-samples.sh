#!/bin/bash
set -xeuEo pipefail

CTX_EXTERNAL_CLUSTER="s.adams@f5.com@remote-cp.us-west-2.eksctl.io"
CTX_REMOTE_CLUSTER="s.adams@f5.com@remote-dp-1.us-west-2.eksctl.io"

kubectl create --context="${CTX_REMOTE_CLUSTER}" namespace sample
kubectl label --context="${CTX_REMOTE_CLUSTER}" namespace sample istio-injection=enabled
kubectl apply -f samples/helloworld/helloworld.yaml -l service=helloworld -n sample --context="${CTX_REMOTE_CLUSTER}"
kubectl apply -f samples/helloworld/helloworld.yaml -l version=v1 -n sample --context="${CTX_REMOTE_CLUSTER}"
kubectl apply -f samples/sleep/sleep.yaml -n sample --context="${CTX_REMOTE_CLUSTER}"
