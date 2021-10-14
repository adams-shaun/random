#!/bin/bash
set -xeuEo pipefail

if [[ -z ${CTX_EXTERNAL_CLUSTER+z} ]]; then
    echo "Missing external cluster context"
    exit 1
fi

if [[ -z ${DNS_DOMAIN+z} ]]; then
    echo "This demo install assumes external-dns is installed and DNS_DOMAIN env provided"
    exit 1
fi

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
  --values "cert-values.yaml" \
  --wait

kubectl apply -f cert-issuer.yaml 
sleep 30
kubectl apply -f cert.yaml
sleep 180