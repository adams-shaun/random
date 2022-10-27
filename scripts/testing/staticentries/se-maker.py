#!/usr/bin/python
import kubernetes
from kubernetes import client, config
from kubernetes import utils
import yaml
import time

config.load_kube_config()
dynamic_client = kubernetes.dynamic.DynamicClient(
    kubernetes.client.api_client.ApiClient()
)

NUM_ENTIRES = 1000

def apply_simple_item(dynamic_client: kubernetes.dynamic.DynamicClient, manifest: dict, verbose: bool=False):
    api_version = manifest.get("apiVersion")
    kind = manifest.get("kind")
    resource_name = manifest.get("metadata").get("name")
    namespace = manifest.get("metadata").get("namespace")
    crd_api = dynamic_client.resources.get(api_version=api_version, kind=kind)

    try:
        crd_api.get(namespace=namespace, name=resource_name)
        crd_api.patch(body=manifest, content_type="application/merge-patch+json")
        if verbose:
            print(f"{namespace}/{resource_name} patched")
    except kubernetes.dynamic.exceptions.NotFoundError:
        crd_api.create(body=manifest, namespace=namespace)
        if verbose:
            print(f"{namespace}/{resource_name} created")


with open("dns.txt", "r") as f:
    cnt = 0
    for dns in f:
        if cnt == NUM_ENTIRES:
            break
        to_apply = f"""
apiVersion: networking.istio.io/v1beta1
kind: ServiceEntry
metadata:
  name: external-svc-https
  namespace: istio-system
spec:
  hosts:
  - {dns.strip()}
  location: MESH_EXTERNAL
  ports:
  - number: 80
    name: http
    protocol: HTTP
  - number: 443
    name: https
    protocol: TLS
  resolution: DNS
"""
        data = yaml.load(to_apply, Loader=yaml.Loader)
        apply_simple_item(dynamic_client=dynamic_client, manifest=data, verbose=False)
        # utils.create_from_yaml(k8s_client, yaml_objects=[data])
        print(to_apply)
        cnt += 1
        time.sleep(2)

