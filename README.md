# Dockerized Python App

## Features

- Lightweight Docker images using multi-stage builds.
- Healthcheck endpoint to ensure the application is running correctly.
- Exposes port 8080 for communication.
- Uses Alpine Linux for the final image to reduce image size.

## Requirements

- Docker


### Building the Docker Image

To build the Docker image, navigate into the `python-app-code` folder and run the following command

```bash
docker build -t python-app .
```

## Configuration
The application requires a kubeconfig file to run. Make sure to mount it into the container or provide it during runtime.

# Dockerized cronjob image

This repository contains a Dockerized cronjob along with a Dockerfile for building the application and another Dockerfile for creating a Kubernetes CronJob to run a health check script periodically.

## Dockerfile for Building the Application

### Features

- Uses Golang 1.16 as the base image for building the application.
- Installs necessary dependencies such as curl for the build process.
- Downloads and installs a specific version of `kubectl` for Kubernetes interactions.
- Copies the `test.sh` script and `kubeconfig` file into the final image.
- Sets `test.sh` as the default command to run when the container starts.

### Building the Docker Image

To build the Docker image for the cronjob, naviagte back to the home directory of repo and run the following command:

```bash
docker build -t cronjob .
```

## test.sh Script

The `test.sh` script performs health checks on Kubernetes deployments. It verifies the following:

1. Checks if `kubectl` is installed.
2. Verifies if `kubectl` can communicate with the Kubernetes API server.
3. Checks the health of each deployment by ensuring all pods are ready.

### Script Contents

```bash
#!/bin/sh

# Check if kubectl is installed
if ! command -v kubectl &> /dev/null; then
    echo "kubectl not found. Please install kubectl."
    exit 1
fi

# Check if kubectl can communicate with the API server
if kubectl cluster-info &> /dev/null; then
    echo "Successfully connected to the Kubernetes API server."
else
    echo "Unable to communicate with the Kubernetes API server."
    exit 1
fi

# Function to check if all pods in a deployment are ready
check_deployment_health() {
    deployment=$1
    desired=$(kubectl get deployment $deployment -o=jsonpath='{.spec.replicas}')
    ready=$(kubectl get deployment $deployment -o=jsonpath='{.status.readyReplicas}')

    if [ "$desired" != "$ready" ]; then
        echo "Deployment $deployment: Unhealthy - $ready out of $desired pods ready"
    else
        echo "Deployment $deployment: Healthy - All $desired pods ready"
    fi
}

# Get list of deployments
deployments=$(kubectl get deployments -o=jsonpath='{.items[*].metadata.name}')

# Loop through each deployment and check health
for deployment in $deployments; do
    check_deployment_health $deployment
done
```


## Helm Chart (helm-python-app)

The Helm chart `helm-python-app` is used to deploy the Dockerized Golang application and its associated Kubernetes CronJob.

### Chart Structure

The Helm chart consists of the following files in the `templates` folder:

- `cronjob.yaml`: Defines the Kubernetes CronJob resource, which runs the health check script periodically using the `cronjobimage`.
- `deployment.yaml`: Defines the Kubernetes Deployment resource, which deploys the Python application using the `python-app` image.
- `hpa.yaml`: Defines the Horizontal Pod Autoscaler (HPA) resource for the deployment.
- `ingress.yaml`: Defines the Ingress resource for exposing the application to external traffic.
- `networkpolicy.yaml`: Defines the Network Policy resource for controlling network traffic to the application.
- `service.yaml`: Defines the Kubernetes Service resource for exposing the application internally.
- `serviceaccount.yaml`: Defines the Service Account resource for the application.

## Network Policy

The `networkpolicy.yaml` file defines a Kubernetes Network Policy resource to control the network traffic to the deployed pods managed by the Helm chart.

### Policy Details

- **Name**: The name of the network policy is derived from the Helm release name using the template function `{{ include "python-app.fullname" . }}`, ensuring uniqueness within the Kubernetes namespace.
- **Namespace**: The network policy is applied within the namespace where the Helm release is installed, as specified by `{{ .Release.Namespace }}`.
- **Labels**: The network policy is labeled according to the labels defined in the Helm chart using the template function `{{ include "python-app.labels" . | nindent 4 }}`.
- **Pod Selector**: The policy applies to pods with labels matching `name: {{ .Release.Namespace }}`, meaning it applies to pods deployed by the Helm chart within the same namespace.
- **Policy Types**: The policy allows only Ingress traffic, meaning it controls incoming traffic to the pods.
- **Ingress Rules**: The policy allows traffic from pods in the same namespace (`namespaceSelector`) where the Kubernetes metadata name matches the Helm release namespace. It specifies that traffic on TCP port 80 is allowed.

### Purpose

The network policy ensures that only pods from the same namespace as the deployed pods, specifically those labeled with `name: {{ .Release.Namespace }}`, are allowed to communicate with the deployed pods over TCP port 80. This restricts external or cross-namespace communication, enhancing security by reducing the attack surface.


### Configuration

The Helm chart can be configured using the `values.yaml` file. Here are some configurable options:

#### Image Settings

```yaml
image:
  repository: python-app
  pullPolicy: IfNotPresent
  tag: "latest"

cronJob:
  image:
    repository: cronjobimage
    tag: latest
    pullPolicy: IfNotPresent  
``` 
- **repository**: Specifies the repository for the Docker image of the Python application and the cronjob
- **pullPolicy**: Specifies the pull policy for the Docker image.
- **tag**: Overrides the image tag.

#### Resource Limits 
```yaml
resources:
  limits:
    cpu: 200m
    memory: 256Mi
  requests:
    cpu: 50m
    memory: 128Mi  
``` 
Specifies the resource limits and requests for the application.

#### Affinity and Anti-Affinity

```yaml
affinity:
  podAntiAffinity:
    requiredDuringSchedulingIgnoredDuringExecution:
      - labelSelector:
          matchExpressions:
            - key: app
              operator: In
              values:
                - python
        topologyKey: "kubernetes.io/hostname" 
``` 
Effectively, with this configuration, Kubernetes will ensure that pods with the label app: python (presumably your Python application pods) will not be scheduled onto nodes that already have pods with the same label. This helps distribute your application pods across different nodes in the cluster, which can enhance fault tolerance and availability.

## GitHub Actions Workflow

The repository includes a GitHub Actions workflow named `build_and_deploy.yaml` in the .github/workflows folder, which automates the build and deployment process of the Dockerized Python application to Kubernetes.

### Workflow Details

- **Trigger**: The workflow is triggered on every push to the `main` branch of the repository.
- **Permissions**: The workflow requires write access to generate an ID token and read access to repository contents.
- **Jobs**:
  - **build**: This job runs on an Ubuntu-latest runner and consists of the following steps:
    - **Checkout**: Checks out the repository code.
    - **Login to Docker Hub**: Authenticates with Docker Hub using Docker credentials stored as GitHub secrets.
    - **Set up Docker Buildx**: Sets up the Docker Buildx builder for multi-platform builds.
    - **Set short git commit SHA**: Calculates and sets the short git commit SHA as an environment variable.
    - **Build and push**: Builds the Docker image using the Dockerfile and pushes it to Docker Hub with tags based on the commit SHA.
  - **deploy**: This job runs on an Ubuntu-latest runner after the build job and consists of the following steps:
    - **Checkout**: Checks out the repository code.
    - **Setup kubectl**: Sets up the Kubernetes command-line tool, kubectl.
    - **Set Kubernetes Context**: Sets the Kubernetes context using the provided kubeconfig stored as a GitHub secret.
    - **Bake Helm Chart**: Renders the Helm chart located in the `helm-pyhton-app/` directory, applying any overrides specified in the workflow.
    - **Deploy Helm chart**: Deploys the rendered Helm chart to the Kubernetes cluster using the Azure/k8s-deploy action.

### Pre-requisites

Before using the GitHub Actions workflow, make sure to set up the following GitHub secrets in your repository:
- `DOCKERHUB_USERNAME`: Your Docker Hub username.
- `DOCKERHUB_TOKEN`: Your Docker Hub access token.
- `KUBE_CONFIG`: Your Kubernetes kubeconfig file content.

Ensure these secrets are securely stored in your GitHub repository settings to enable the workflow to authenticate and access external services.

## Deploying on Self-Managed Kubernetes Cluster

If you're deploying the Helm chart on a self-managed Kubernetes cluster, you'll need to follow specific steps to ensure proper deployment, especially when deploying on the master node.

### Kubeadm Cluster Setup

Ensure that your self-managed Kubernetes cluster, set up using tools like kubeadm, is properly configured and operational.

### Untainting Master Node

By default, Kubernetes master nodes are tainted to prevent regular workload deployments. Since you intend to deploy the application on the master node, you'll need to untaint it to allow workloads to be scheduled on it.

You can untaint the master node using the following command:

```bash
kubectl taint nodes --all node-role.kubernetes.io/control-plane-
```
To enable Horizontal Pod Autoscaling (HPA) functionality, you need to install the Metrics Server in your Kubernetes cluster. The Metrics Server collects resource usage metrics from nodes and pods in the cluster.

```
kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml

kubectl get deployment metrics-server -n kube-system
```
Also install the helm3 for the helmchart

## Veryfication of deployment
Once you make any changes and push to the main branch of repo, it will trigger the workflow which will create the image and deploy the helm chart in the default namespace,The output should display the deployed Helm release with details such as revision, status, chart, and app version.

```
helm  ls

NAME	NAMESPACE	REVISION	UPDATED                                	STATUS  	CHART           	APP VERSION
python-app 	default  	1       	2024-03-01 06:15:48.373004218 +0000 UTC	deployed	python-app-0.1.0	1.16.0  
```
To verify the NetworkPolicy, create a new namesapce test, and deploy a sample nginx pod from which we will try to access the python-app pod of default namespace

```
kubectl create namespace test

kubectl run nginx --image=nginx -n test
```

Get the IP address of the python-app pod in the "default" namespace:
```
kubectl get pod -owide

NAME                          READY   STATUS    RESTARTS   AGE   IP                NODE               NOMINATED NODE   READINESS GATES
python-app-28488013-lkxtq     1/1     Running   0          34s   192.168.210.162   ip-172-31-25-204   <none>           <none>
```

Once you have the IP address of the python-app pod, execute the following command to enter the nginx pod in the "test" namespace, and from within the nginx pod, attempt to access the python-app pod using its IP address:
```
kubectl exec -it nginx -n test/bin/bash
root@nginx:/# curl 192.168.210.142 


```
If the NetworkPolicy is configured correctly, you should not receive any response. This confirms that the NetworkPolicy is effectively restricting access to the python-app pod from pods in the "test" namespace