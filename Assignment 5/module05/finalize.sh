#!/usr/bin/env bash
set -euo pipefail

NS="gpu-check"
ACR_NAME="dkimacruse123"
ACR_LOGIN="${ACR_NAME}.azurecr.io"

# Ensure namespace + image pull secret (uses your JHU email)
kubectl create namespace "$NS" --dry-run=client -o yaml | kubectl apply -f -
ACR_USER="$(az acr credential show -n "$ACR_NAME" --query username -o tsv)"
ACR_PASS="$(az acr credential show -n "$ACR_NAME" --query 'passwords[0].value' -o tsv)"
kubectl -n "$NS" create secret docker-registry acr-secret \
  --docker-server="$ACR_LOGIN" \
  --docker-username="$ACR_USER" \
  --docker-password="$ACR_PASS" \
  --docker-email="smauch1@jh.edu" \
  --dry-run=client -o yaml | kubectl apply -f -

# Make sure NVIDIA device plugin is on the GPU node
kubectl apply -f gpu-operator-daemonset.yaml
kubectl -n kube-system rollout status ds/nvidia-device-plugin-daemonset

# Point deployments to your ACR images (ok if they already match)
kubectl -n "$NS" set image deploy/gpu-app1 gpu-app1="${ACR_LOGIN}/my-gpu-app:latest" || true
kubectl -n "$NS" set image deploy/gpu-app2 gpu-app2="${ACR_LOGIN}/my-gpu-app:latest" || true
kubectl -n "$NS" set image deploy/gpu-app3 gpu-app3="${ACR_LOGIN}/my-gpu-app:latest" || true
kubectl -n "$NS" set image deploy/gateway  gateway="${ACR_LOGIN}/gateway-service:latest" || true

# Ensure gpu-app1 requests a single GPU and lands on GPU node; keep CPU apps off it
kubectl -n "$NS" patch deploy/gpu-app1 --type merge -p '{
  "spec": { "replicas": 1, "template": { "spec": {
    "imagePullSecrets":[{"name":"acr-secret"}],
    "nodeSelector":{"kubernetes.azure.com/accelerator":"nvidia"},
    "tolerations":[{"key":"sku","operator":"Equal","value":"gpu","effect":"NoSchedule"}],
    "containers":[{ "name":"gpu-app1",
      "resources":{"limits":{"nvidia.com/gpu":"1"}}
    }]
  }}}}'

for APP in gpu-app2 gpu-app3; do
  kubectl -n "$NS" patch deploy/$APP --type merge -p '{
    "spec": { "replicas": 1, "template": { "spec": {
      "imagePullSecrets":[{"name":"acr-secret"}],
      "affinity":{"nodeAffinity":{"requiredDuringSchedulingIgnoredDuringExecution":{
        "nodeSelectorTerms":[{"matchExpressions":[
          {"key":"kubernetes.azure.com/accelerator","operator":"DoesNotExist"}
        ]}]
      }}}
    }}}}'
done

# Rollout and wait
kubectl -n "$NS" rollout restart deploy/gpu-app1 deploy/gpu-app2 deploy/gpu-app3 deploy/gateway
kubectl -n "$NS" rollout status deploy/gpu-app1 --timeout=10m
kubectl -n "$NS" rollout status deploy/gpu-app2 --timeout=10m
kubectl -n "$NS" rollout status deploy/gpu-app3 --timeout=10m
kubectl -n "$NS" rollout status deploy/gateway  --timeout=10m

# Quick verification (placement + GPU limits shown)
kubectl get nodes -L agentpool,kubernetes.azure.com/accelerator
kubectl get pods -n "$NS" -o wide
kubectl get pods -n "$NS" \
  -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{.spec.nodeName}{"\t"}{.spec.containers[*].resources.limits.nvidia\.com/gpu}{"\n"}{end}' || true

# ===== Assignment CURL =====
AGG_IP="$(kubectl get svc gateway -n "$NS" -o jsonpath='{.status.loadBalancer.ingress[0].ip}')"
echo "curl -s http://$AGG_IP/aggregate"
curl -s "http://$AGG_IP/aggregate"
