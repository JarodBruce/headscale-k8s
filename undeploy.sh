#!/bin/bash

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Function to print colored output
print_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

# Check if .env file exists
if [ ! -f .env ]; then
    print_error ".env file not found!"
    print_warning "Using default namespace: headscale"
    NAMESPACE=headscale
else
    # Load environment variables
    source .env
    NAMESPACE=${NAMESPACE:-headscale}
fi

# Set default values
KUBECONFIG_PATH=${KUBECONFIG_PATH:-~/.kube/config}

# Expand tilde in KUBECONFIG_PATH
KUBECONFIG_PATH="${KUBECONFIG_PATH/#\~/$HOME}"

# Check if kubectl is installed
if ! command -v kubectl &> /dev/null; then
    print_error "kubectl is not installed!"
    exit 1
fi

# Check if kubeconfig exists
if [ ! -f "$KUBECONFIG_PATH" ]; then
    print_error "Kubeconfig file not found at $KUBECONFIG_PATH"
    exit 1
fi

export KUBECONFIG=$KUBECONFIG_PATH

# Test kubectl connection
print_info "Testing kubectl connection..."
if ! kubectl cluster-info &> /dev/null; then
    print_error "Cannot connect to Kubernetes cluster!"
    exit 1
fi

print_info "Successfully connected to Kubernetes cluster"

# Ask for confirmation
print_warning "This will delete all Headscale resources in namespace '$NAMESPACE'"
read -p "Are you sure you want to continue? (yes/no): " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    print_info "Operation cancelled"
    exit 0
fi

# Delete Cloudflare Tunnel resources
print_info "Deleting Cloudflare Tunnel resources..."
kubectl delete -f k8s/cloudflared/03-deployment.yaml --ignore-not-found=true
kubectl delete configmap cloudflared-config -n $NAMESPACE --ignore-not-found=true
kubectl delete secret cloudflared-credentials -n $NAMESPACE --ignore-not-found=true

# Delete Headscale resources
print_info "Deleting Headscale resources..."
kubectl delete -f k8s/headscale/04-deployment.yaml --ignore-not-found=true
kubectl delete -f k8s/headscale/03-service.yaml --ignore-not-found=true
kubectl delete -f k8s/headscale/01-configmap.yaml --ignore-not-found=true

# Ask about PVC deletion
print_warning "Do you want to delete the PersistentVolumeClaim (this will delete all Headscale data)?"
read -p "Delete PVC? (yes/no): " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    print_info "Deleting PersistentVolumeClaim..."
    kubectl delete -f k8s/headscale/02-pvc.yaml --ignore-not-found=true
else
    print_info "PersistentVolumeClaim retained"
fi

# Ask about namespace deletion
print_warning "Do you want to delete the namespace '$NAMESPACE'?"
read -p "Delete namespace? (yes/no): " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    print_info "Deleting namespace..."
    kubectl delete namespace $NAMESPACE --ignore-not-found=true
else
    print_info "Namespace retained"
fi

# Clean up generated files
print_info "Cleaning up generated files..."
rm -f k8s/cloudflared/01-secret.yaml
rm -f k8s/cloudflared/02-configmap.yaml

print_info "=========================================="
print_info "Undeployment completed successfully!"
print_info "=========================================="
