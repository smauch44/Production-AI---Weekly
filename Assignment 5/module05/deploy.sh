#!/usr/bin/env bash
set -Eeuo pipefail

# ======== CONFIG ========
RG="dev-jhu-dkim-rg-use"
AKS="aks-m09"
ACR_NAME="dkimacruse123"
ACR_LOGIN="${ACR_NAME}.azurecr.io"
NS="gpu-check"
EMAIL="smauch1@jh.edu"

echo "[0] Azure login & kube context"
az account show >/dev/null 2>&1 || az login
az aks get-credentials -g "$RG" -n "$AKS" --overwrite-existing

echo "[1] Ensure NVIDIA device plugin is running on GPU nodes"
kubectl apply -f gpu-operator-daemonset.yaml
kubectl -n kube-system rollout status ds/nvidia-device-plugin-daemonset

echo "[2] Fix my-gpu-app Dockerfile typo if present"
[ -f my-gpu-app/Dockerfille ] && mv my-gpu-app/Dockerfille my-gpu-app/Dockerfile

echo "[3] Standardize my-gpu-app requirements (Torch is installed in Dockerfile)"
cat > my-gpu-app/requirements.txt <<'REQ'
blinker==1.9.0
click==8.1.8
Flask==3.1.0
itsdangerous==2.2.0
Jinja2==3.1.6
MarkupSafe==3.0.2
Werkzeug==3.1.3
REQ

# CUDA-ready Dockerfile (installs PyTorch w/ CUDA 12.6)
cat > my-gpu-app/Dockerfile <<'DOCKER'
FROM python:3.10
WORKDIR /app
COPY . /app
RUN pip install --upgrade pip setuptools wheel
RUN pip3 install torch torchvision torchaudio --index-url https://download.pytorch.org/whl/cu126
RUN pip install --no-cache-dir -r requirements.txt
EXPOSE 8000
CMD ["python", "main.py"]
DOCKER

# Minimal Flask app that reports GPU vs CPU
cat > my-gpu-app/main.py <<'PY'
from flask import Flask, jsonify
import torch

app = Flask(__name__)

@app.get("/status")
def status():
    if torch.cuda.is_available():
        return jsonify({"status": "GPU enabled"})
    return jsonify({"status": "CPU enabled"})

if __name__ == "__main__":
    app.run(host="0.0.0.0", port=8000)
PY

echo "[4] Build & push images with ACR Tasks (no local Docker needed)"
az acr build --registry "$ACR_NAME" --image my-gpu-app:latest ./my-gpu-app
az acr build --registry "$ACR_NAME" --image gateway-service:latest ./gateway-service

echo "[5] Namespace + ACR imagePull secret"
kubectl create namespace "$NS" --dry-run=client -o yaml | kubectl apply -f -
ACR_USER=$(az acr credential show -n "$ACR_NAME" --query username -o tsv)
ACR_PASS=$(az acr credential show -n "$ACR_NAME" --query "passwords[0].value" -o tsv)
kubectl -n "$NS" create secret docker-registry acr-secret \
  --docker-server="$ACR_LOGIN" \
  --docker-username="$ACR_USER" \
  --docker-password="$ACR_PASS" \
  --docker-email="$EMAIL" \
  --dry-run=client -o yaml | kubectl apply -f -

echo "[6] Write/refresh Helm chart files"
mkdir -p helm-chart/templates

# Chart.yaml
cat > helm-chart/Chart.yaml <<'YAML'
apiVersion: v2
name: gpu-checker
version: 1.0.0
YAML

# values.yaml
cat > helm-chart/values.yaml <<EOF
acr: ${ACR_LOGIN}

gateway:
  image: gateway-service
  tag: latest
  port: 5000

myGPUApp:
  image: my-gpu-app
  tag: latest
  replicas: 1
  port: 8000
EOF

# gateway deployment
cat > helm-chart/templates/gateway-deployment.yaml <<'YAML'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: gateway
spec:
  replicas: 1
  selector:
    matchLabels: { app: gateway }
  template:
    metadata:
      labels: { app: gateway }
    spec:
      imagePullSecrets:
        - name: acr-secret
      containers:
        - name: gateway
          image: {{ .Values.acr }}/{{ .Values.gateway.image }}:{{ .Values.gateway.tag }}
          imagePullPolicy: Always
          ports:
            - containerPort: {{ .Values.gateway.port }}
          env:
            - name: GPU_APP_URLS
              value: "http://gpu-app1:8000,http://gpu-app2:8000,http://gpu-app3:8000"
          readinessProbe:
            httpGet: { path: /aggregate, port: {{ .Values.gateway.port }} }
            initialDelaySeconds: 10
            periodSeconds: 15
YAML

# gateway service
cat > helm-chart/templates/gateway-service.yaml <<'YAML'
apiVersion: v1
kind: Service
metadata:
  name: gateway
spec:
  type: LoadBalancer
  selector: { app: gateway }
  ports:
    - protocol: TCP
      port: 80
      targetPort: {{ .Values.gateway.port }}
YAML

# app services
cat > helm-chart/templates/gpu-app-service.yaml <<'YAML'
apiVersion: v1
kind: Service
metadata:
  name: gpu-app1
  labels: { app: gpu-app1 }
spec:
  type: ClusterIP
  selector: { app: gpu-app1 }
  ports:
    - name: http
      protocol: TCP
      port: {{ .Values.myGPUApp.port }}
      targetPort: {{ .Values.myGPUApp.port }}
---
apiVersion: v1
kind: Service
metadata:
  name: gpu-app2
  labels: { app: gpu-app2 }
spec:
  type: ClusterIP
  selector: { app: gpu-app2 }
  ports:
    - name: http
      protocol: TCP
      port: {{ .Values.myGPUApp.port }}
      targetPort: {{ .Values.myGPUApp.port }}
---
apiVersion: v1
kind: Service
metadata:
  name: gpu-app3
  labels: { app: gpu-app3 }
spec:
  type: ClusterIP
  selector: { app: gpu-app3 }
  ports:
    - name: http
      protocol: TCP
      port: {{ .Values.myGPUApp.port }}
      targetPort: {{ .Values.myGPUApp.port }}
YAML

# app deployments (gpu-app1 on GPU, others on CPU)
cat > helm-chart/templates/gpu-app-deployments.yaml <<'YAML'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: gpu-app1
spec:
  replicas: {{ .Values.myGPUApp.replicas }}
  selector: { matchLabels: { app: gpu-app1 } }
  template:
    metadata: { labels: { app: gpu-app1 } }
    spec:
      imagePullSecrets: [ { name: acr-secret } ]
      nodeSelector:
        kubernetes.azure.com/accelerator: nvidia
      tolerations:
        - key: "sku"
          operator: "Equal"
          value: "gpu"
          effect: "NoSchedule"
      containers:
        - name: gpu-app1
          image: {{ .Values.acr }}/{{ .Values.myGPUApp.image }}:{{ .Values.myGPUApp.tag }}
          imagePullPolicy: Always
          ports:
            - containerPort: {{ .Values.myGPUApp.port }}
          resources:
            limits:
              nvidia.com/gpu: 1
          readinessProbe:
            httpGet: { path: /status, port: {{ .Values.myGPUApp.port }} }
            initialDelaySeconds: 5
            periodSeconds: 10
          livenessProbe:
            httpGet: { path: /status, port: {{ .Values.myGPUApp.port }} }
            initialDelaySeconds: 15
            periodSeconds: 20
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: gpu-app2
spec:
  replicas: {{ .Values.myGPUApp.replicas }}
  selector: { matchLabels: { app: gpu-app2 } }
  template:
    metadata: { labels: { app: gpu-app2 } }
    spec:
      imagePullSecrets: [ { name: acr-secret } ]
      affinity:
        nodeAffinity:
          requiredDuringSchedulingIgnoredDuringExecution:
            nodeSelectorTerms:
              - matchExpressions:
                  - key: kubernetes.azure.com/accelerator
                    operator: DoesNotExist
      containers:
        - name: gpu-app2
          image: {{ .Values.acr }}/{{ .Values.myGPUApp.image }}:{{ .Values.myGPUApp.tag }}
          imagePullPolicy: Always
          ports:
            - containerPort: {{ .Values.myGPUApp.port }}
          readinessProbe:
            httpGet: { path: /status, port: {{ .Values.myGPUApp.port }} }
            initialDelaySeconds: 5
            periodSeconds: 10
          livenessProbe:
            httpGet: { path: /status, port: {{ .Values.myGPUApp.port }} }
            initialDelaySeconds: 15
            periodSeconds: 20
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: gpu-app3
spec:
  replicas: {{ .Values.myGPUApp.replicas }}
  selector: { matchLabels: { app: gpu-app3 } }
  template:
    metadata: { labels: { app: gpu-app3 } }
    spec:
      imagePullSecrets: [ { name: acr-secret } ]
      affinity:
        nodeAffinity:
          requiredDuringSchedulingIgnoredDuringExecution:
            nodeSelectorTerms:
              - matchExpressions:
                  - key: kubernetes.azure.com/accelerator
                    operator: DoesNotExist
      containers:
        - name: gpu-app3
          image: {{ .Values.acr }}/{{ .Values.myGPUApp.image }}:{{ .Values.myGPUApp.tag }}
          imagePullPolicy: Always
          ports:
            - containerPort: {{ .Values.myGPUApp.port }}
          readinessProbe:
            httpGet: { path: /status, port: {{ .Values.myGPUApp.port }} }
            initialDelaySeconds: 5
            periodSeconds: 10
          livenessProbe:
            httpGet: { path: /status, port: {{ .Values.myGPUApp.port }} }
            initialDelaySeconds: 15
            periodSeconds: 20
YAML

echo "[7] Helm install/upgrade (waits until everything is Ready)"
helm upgrade --install gpu-checker ./helm-chart \
  -n "$NS" \
  --set acr="$ACR_LOGIN" \
  --set gateway.tag="latest" \
  --set myGPUApp.tag="latest" \
  --wait --timeout 20m

echo "[8] Verify placement & GPU requests"
kubectl get nodes -L agentpool,kubernetes.azure.com/accelerator
kubectl get pods -n "$NS" -o wide
kubectl get pods -n "$NS" \
  -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{.spec.nodeName}{"\t"}{.spec.containers[*].resources.limits.nvidia\.com/gpu}{"\n"}{end}' || true

echo "[9] Assignment endpoint (pretty JSON)"
AGG_IP="$(kubectl get svc gateway -n "$NS" -o jsonpath='{.status.loadBalancer.ingress[0].ip}')"
echo "Gateway external IP: $AGG_IP"
python3 - <<PY
import json,sys,urllib.request
u="http://$AGG_IP/aggregate"
print("GET", u)
try:
    with urllib.request.urlopen(u,timeout=45) as r:
        data=r.read()
    try:
        print(json.dumps(json.loads(data), indent=2))
    except Exception:
        sys.stdout.buffer.write(data)
except Exception as e:
    print("Request failed:", e)
PY

echo "[DONE] Expect ONE 'GPU enabled' and TWO 'CPU enabled'."
