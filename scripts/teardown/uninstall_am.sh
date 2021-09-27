#!/bin/bash

helm del istio-cni -n kube-system
helm del istiod --namespace istio-system
helm del  istio-base --namespace istio-system
kubectl delete configmaps -n istio-system --all
kubectl delete services --all -n istio-system
kubectl delete jobs --all -n istio-system
kubectl delete validatingwebhookconfiguration --all
kubectl delete ns istio-system
kubectl delete ns istio-ready
sleep 60 
