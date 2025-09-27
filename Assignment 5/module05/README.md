# HOW TO HAVE CONTAINERS TALK TO OTHER CONTAINERS

## CREATE THE DOCKER NETWORK
- docker network create gpu-network

## BUILD GPU APP
- docker build -t my-gpu-app:v1 .

## RUN ALL 3 GPU DOCKER CONTAINERS 1,2,&3 FROM IMAGES ON THE NETWORK
### Notice we dont expose the port!
- docker run -d --name gpu-app1 --network gpu-network my-gpu-app
- docker run -d --name gpu-app2 --network gpu-network my-gpu-app
- docker run -d --name gpu-app3 --network gpu-network my-gpu-app

## BUILD GATEWAY SERVICE
- docker build -t gateway-service:v1 .

## RUN THE gateway service
### Here we expose the port!
- docker run -p 5000:5000 --name gateway-service --network gpu-network gateway-service:v1

## Call the service
- curl http://0.0.0.0:5000/aggregate | jq .

# ONCE CONFIRM WORKS, LETS PUBLISH TO ACR

## Login to Docker
- az acr login --name \<acrName\>.azurecr.io

## Tag the Image
- docker tag gateway-service:v1 \<acrName\>.azurecr.io/gateway-service:v1

## Push the Tagged image pointing to ACR
- docker push \<acrName\>.azurecr.io/gateway-service:v1

### Repeat last 3 processes if you make any updates

# Now we are ready to deploy all of our  kubernetes services

## Ensure Admin is Enabled on your cluster
az acr update -n \<acrName\> --admin-enabled true

## Get ACR Credentials
az acr credential show --name \<acrName\>


## Set Kubernetes Image Pull Secret
kubectl create secret docker-registry acr-secret \
  --docker-server=\<acr-name\>.azurecr.io \
  --docker-username=\<acr-name\> \
  --docker-password=<password> \
  --docker-email=you@example.com

  


## Deploy the Services
helm install \<release-name\> \<Chart-Path\>


