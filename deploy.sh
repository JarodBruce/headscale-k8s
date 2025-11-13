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
    print_info "Creating .env from .env.example..."
    cp .env.example .env
    print_warning "Please edit .env file with your configuration and run this script again."
    exit 1
fi

# Load environment variables
source .env

# Validate required environment variables
required_vars=(
    "HEADSCALE_DOMAIN"
    "CLOUDFLARE_TUNNEL_TOKEN"
    "NAMESPACE"
)

for var in "${required_vars[@]}"; do
    if [ -z "${!var}" ]; then
        print_error "$var is not set in .env file!"
        exit 1
    fi
done

# Set default values if not provided
KUBECONFIG_PATH=${KUBECONFIG_PATH:-~/.kube/config}
STORAGE_CLASS=${STORAGE_CLASS:-standard}
STORAGE_SIZE=${STORAGE_SIZE:-1Gi}
TZ=${TZ:-Asia/Tokyo}

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

# Function to apply template files
apply_template() {
    local template_file=$1
    local output_file="${template_file%.template}"

    print_info "Processing $template_file..."

    # Create a temporary file
    temp_file=$(mktemp)

    # Copy template to temp file
    cp "$template_file" "$temp_file"

    # Replace variables in temp file
    sed -i.bak "s|\${HEADSCALE_DOMAIN}|${HEADSCALE_DOMAIN}|g" "$temp_file"
    sed -i.bak "s|\${CLOUDFLARE_TUNNEL_TOKEN}|${CLOUDFLARE_TUNNEL_TOKEN}|g" "$temp_file"
    sed -i.bak "s|\${NAMESPACE}|${NAMESPACE}|g" "$temp_file"
    sed -i.bak "s|\${STORAGE_CLASS}|${STORAGE_CLASS}|g" "$temp_file"
    sed -i.bak "s|\${STORAGE_SIZE}|${STORAGE_SIZE}|g" "$temp_file"
    sed -i.bak "s|\${TZ}|${TZ}|g" "$temp_file"

    # Move processed file to output location
    mv "$temp_file" "$output_file"
    rm -f "${temp_file}.bak"

    print_info "Created $output_file"
}

# Create namespace
print_info "Creating namespace '$NAMESPACE'..."
kubectl apply -f k8s/00-namespace.yaml

# Wait for namespace to be ready
print_info "Waiting for namespace to be ready..."
kubectl wait --for=condition=Active namespace/$NAMESPACE --timeout=30s 2>/dev/null || true

# Update Headscale configuration with actual domain
print_info "Updating Headscale configuration..."
sed -i.bak "s|headscale.example.com|${HEADSCALE_DOMAIN}|g" k8s/headscale/01-configmap.yaml
sed -i.bak "s|example.com|${HEADSCALE_BASE_DOMAIN:-example.com}|g" k8s/headscale/01-configmap.yaml
rm -f k8s/headscale/01-configmap.yaml.bak

# Update PVC with storage configuration
if [ "$STORAGE_CLASS" != "standard" ]; then
    print_info "Updating storage class to $STORAGE_CLASS..."
    sed -i.bak "s|storageClassName: standard|storageClassName: ${STORAGE_CLASS}|g" k8s/headscale/02-pvc.yaml
    rm -f k8s/headscale/02-pvc.yaml.bak
fi

if [ "$STORAGE_SIZE" != "1Gi" ]; then
    print_info "Updating storage size to $STORAGE_SIZE..."
    sed -i.bak "s|storage: 1Gi|storage: ${STORAGE_SIZE}|g" k8s/headscale/02-pvc.yaml
    rm -f k8s/headscale/02-pvc.yaml.bak
fi

# Process template files for Cloudflare
print_info "Processing Cloudflare Tunnel templates..."
apply_template "k8s/cloudflared/01-secret.yaml.template"

# Deploy Headscale
print_info "Deploying Headscale..."
kubectl apply -f k8s/headscale/01-configmap.yaml
kubectl apply -f k8s/headscale/02-pvc.yaml
kubectl apply -f k8s/headscale/03-service.yaml
kubectl apply -f k8s/headscale/04-deployment.yaml

# Wait for Headscale to be ready
print_info "Waiting for Headscale deployment to be ready..."
kubectl rollout status deployment/headscale -n $NAMESPACE --timeout=300s

# Deploy Cloudflare Tunnel
print_info "Deploying Cloudflare Tunnel..."
kubectl apply -f k8s/cloudflared/01-secret.yaml
kubectl apply -f k8s/cloudflared/03-deployment.yaml

# Clean up generated files
rm -f k8s/cloudflared/01-secret.yaml

# Wait for Cloudflare Tunnel to be ready
print_info "Waiting for Cloudflare Tunnel deployment to be ready..."
kubectl rollout status deployment/cloudflared -n $NAMESPACE --timeout=300s

# Get pod status
print_info "Current pod status:"
kubectl get pods -n $NAMESPACE

# Get service status
print_info "Current service status:"
kubectl get svc -n $NAMESPACE

print_info "=========================================="
print_info "Deployment completed successfully!"
print_info "=========================================="
print_info ""
print_info "Headscale is now accessible at: https://${HEADSCALE_DOMAIN}"
print_info ""
print_info "To create the first user, run:"
print_info "  kubectl exec -it deploy/headscale -n $NAMESPACE -- headscale users create <username>"
print_info ""
print_info "To generate a pre-auth key, run:"
print_info "  kubectl exec -it deploy/headscale -n $NAMESPACE -- headscale preauthkeys create --user <username>"
print_info ""
print_info "To view logs:"
print_info "  kubectl logs -f deploy/headscale -n $NAMESPACE"
print_info "  kubectl logs -f deploy/cloudflared -n $NAMESPACE"
print_info ""
print_warning "Note: Make sure your Cloudflare Tunnel is properly configured in the Zero Trust dashboard"
print_warning "      with a public hostname pointing to this tunnel."
