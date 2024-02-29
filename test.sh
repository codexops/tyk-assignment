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