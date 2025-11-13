#!/bin/bash

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
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

print_step() {
    echo -e "${BLUE}[STEP]${NC} $1"
}

print_success() {
    echo -e "${CYAN}[SUCCESS]${NC} $1"
}

# Check if .env file exists
if [ ! -f .env ]; then
    print_error ".env file not found!"
    if [ -f .env.example ]; then
        print_info "Creating .env from .env.example..."
        cp .env.example .env
        print_warning "Please edit .env file with your configuration and run this script again."
        print_info ""
        print_info "Required settings:"
        print_info "  - HEADSCALE_DOMAIN: Your domain (e.g., headscale.example.com)"
        print_info "  - CLOUDFLARE_API_TOKEN: Your Cloudflare API token"
    else
        print_warning "Please create a .env file with required variables."
    fi
    exit 1
fi

# Load environment variables
print_info "Loading environment variables from .env..."
source .env

# Validate required environment variables
required_vars=(
    "HEADSCALE_DOMAIN"
    "NAMESPACE"
)

# Check for either CLOUDFLARE_API_TOKEN or CLOUDFLARE_TUNNEL_TOKEN
if [ -z "$CLOUDFLARE_API_TOKEN" ] && [ -z "$CLOUDFLARE_TUNNEL_TOKEN" ]; then
    print_error "Either CLOUDFLARE_API_TOKEN or CLOUDFLARE_TUNNEL_TOKEN must be set in .env file!"
    print_info "For automatic setup, use CLOUDFLARE_API_TOKEN (recommended)"
    print_info "For manual setup, use CLOUDFLARE_TUNNEL_TOKEN"
    exit 1
fi

missing_vars=()
for var in "${required_vars[@]}"; do
    if [ -z "${!var}" ]; then
        missing_vars+=("$var")
    fi
done

if [ ${#missing_vars[@]} -gt 0 ]; then
    print_error "The following required variables are not set in .env file:"
    for var in "${missing_vars[@]}"; do
        echo "  - $var"
    done
    exit 1
fi

# Set defaults for optional variables
STORAGE_CLASS=${STORAGE_CLASS:-"longhorn"}
STORAGE_SIZE=${STORAGE_SIZE:-"1Gi"}
TZ=${TZ:-"Asia/Tokyo"}
HEADSCALE_BASE_DOMAIN=${HEADSCALE_BASE_DOMAIN:-$(echo "$HEADSCALE_DOMAIN" | awk -F. '{print $(NF-1)"."$NF}')}

print_info "Configuration:"
print_info "  Domain: ${HEADSCALE_DOMAIN}"
print_info "  Base Domain: ${HEADSCALE_BASE_DOMAIN}"
print_info "  Namespace: ${NAMESPACE}"
print_info "  Storage Class: ${STORAGE_CLASS}"
print_info "  Storage Size: ${STORAGE_SIZE}"
print_info "  Timezone: ${TZ}"

if [ -n "$CLOUDFLARE_API_TOKEN" ]; then
    print_info "  Mode: Automatic (using API Token)"
else
    print_info "  Mode: Manual (using Tunnel Token)"
fi

# Test kubectl connection
print_step "Testing kubectl connection..."
if ! kubectl cluster-info &> /dev/null; then
    print_error "Cannot connect to Kubernetes cluster!"
    exit 1
fi
print_success "Successfully connected to Kubernetes cluster"

echo ""
print_step "Deploying to Kubernetes..."
echo ""

# Create namespace
print_step "1/5 Creating namespace '${NAMESPACE}'..."
kubectl apply -f k8s/namespace.yaml
print_success "Namespace ready"

# Update Headscale configuration
print_step "2/5 Configuring Headscale..."
cp k8s/headscale/01-configmap.yaml k8s/headscale/01-configmap.yaml.bak 2>/dev/null || true
sed -i.tmp "s|server_url:.*|server_url: https://${HEADSCALE_DOMAIN}|g" k8s/headscale/01-configmap.yaml
sed -i.tmp "s|base_domain:.*|base_domain: ${HEADSCALE_BASE_DOMAIN}|g" k8s/headscale/01-configmap.yaml
rm -f k8s/headscale/01-configmap.yaml.tmp

# Update PVC with storage configuration
cp k8s/headscale/02-pvc.yaml k8s/headscale/02-pvc.yaml.bak 2>/dev/null || true
sed -i.tmp "s|storageClassName:.*|storageClassName: ${STORAGE_CLASS}|g" k8s/headscale/02-pvc.yaml
sed -i.tmp "s|storage:.*|storage: ${STORAGE_SIZE}|g" k8s/headscale/02-pvc.yaml
rm -f k8s/headscale/02-pvc.yaml.tmp

kubectl apply -f k8s/headscale/01-configmap.yaml
kubectl apply -f k8s/headscale/02-pvc.yaml
kubectl apply -f k8s/headscale/03-service.yaml
kubectl apply -f k8s/headscale/04-deployment.yaml
print_success "Headscale deployed"

# Deploy Cloudflare Tunnel
print_step "3/5 Deploying Cloudflare Tunnel..."

if [ -n "$CLOUDFLARE_API_TOKEN" ]; then
    # Use new automated setup with API Token
    print_info "Using automated Cloudflare Tunnel setup..."

    # Check if new manifest files exist
    if [ ! -f "k8s/cloudflared.yaml" ]; then
        print_error "k8s/cloudflared.yaml not found. Please create it with the automated setup configuration."
        print_info "Falling back to manual token-based setup..."
        CLOUDFLARE_API_TOKEN=""
    else
        # Create temporary processed manifest
        TMP_DIR=$(mktemp -d)
        trap "rm -rf ${TMP_DIR}" EXIT

        sed -e "s/HEADSCALE_DOMAIN_PLACEHOLDER/${HEADSCALE_DOMAIN}/g" \
            -e "s/CLOUDFLARE_API_TOKEN_PLACEHOLDER/${CLOUDFLARE_API_TOKEN}/g" \
            -e "s/TZ_PLACEHOLDER/${TZ}/g" \
            -e "s/namespace: headscale/namespace: ${NAMESPACE}/g" \
            k8s/cloudflared.yaml > "${TMP_DIR}/cloudflared.yaml"

        kubectl apply -f "${TMP_DIR}/cloudflared.yaml"

        print_step "4/5 Waiting for Cloudflare Tunnel setup (this may take a minute)..."
        if kubectl wait --for=condition=complete job/cloudflared-setup -n "${NAMESPACE}" --timeout=300s 2>/dev/null; then
            print_success "Cloudflare Tunnel setup complete!"
            echo ""
            print_info "Tunnel details:"
            kubectl logs -n "${NAMESPACE}" job/cloudflared-setup --tail=15 2>/dev/null | grep -E "(Account ID|Zone ID|Tunnel ID|Tunnel Name|Hostname)" || true
        else
            print_warning "Setup job did not complete in expected time"
            print_info "Check logs with: kubectl logs -n ${NAMESPACE} job/cloudflared-setup"
        fi
    fi
fi

if [ -n "$CLOUDFLARE_TUNNEL_TOKEN" ] || [ -z "$CLOUDFLARE_API_TOKEN" ]; then
    # Use old token-based setup
    print_info "Using manual Cloudflare Tunnel token..."

    if [ -z "$CLOUDFLARE_TUNNEL_TOKEN" ]; then
        print_error "CLOUDFLARE_TUNNEL_TOKEN is required for manual setup!"
        exit 1
    fi

    # Process template if it exists
    if [ -f "k8s/cloudflared/01-secret.yaml.template" ]; then
        sed "s|\${CLOUDFLARE_TUNNEL_TOKEN}|${CLOUDFLARE_TUNNEL_TOKEN}|g" \
            k8s/cloudflared/01-secret.yaml.template > k8s/cloudflared/01-secret.yaml
        kubectl apply -f k8s/cloudflared/01-secret.yaml
        rm -f k8s/cloudflared/01-secret.yaml
    fi

    kubectl apply -f k8s/cloudflared/03-deployment.yaml
    print_success "Cloudflared deployed"
fi

# Wait for deployments
print_step "5/5 Waiting for deployments to be ready..."
kubectl wait --for=condition=available deployment/headscale -n "${NAMESPACE}" --timeout=120s 2>/dev/null || {
    print_warning "Headscale deployment taking longer than expected..."
}
kubectl wait --for=condition=available deployment/cloudflared -n "${NAMESPACE}" --timeout=120s 2>/dev/null || {
    print_warning "Cloudflared deployment taking longer than expected..."
}

# Get pod status
echo ""
print_info "Current status:"
kubectl get pods -n "${NAMESPACE}"

# Display final message
echo ""
echo ""
echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${GREEN}                        🎉 Deployment Complete! 🎉${NC}"
echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""
echo -e "${CYAN}Headscale URL:${NC} https://${HEADSCALE_DOMAIN}"
echo ""
echo -e "${YELLOW}Next Steps:${NC}"
echo ""
echo "1. Create a user:"
echo "   ${BLUE}kubectl exec -it deploy/headscale -n ${NAMESPACE} -- headscale users create myuser${NC}"
echo ""
echo "2. Generate a pre-auth key:"
echo "   ${BLUE}kubectl exec -it deploy/headscale -n ${NAMESPACE} -- headscale preauthkeys create --user myuser --expiration 24h${NC}"
echo ""
echo "3. Connect your device:"
echo "   ${BLUE}tailscale up --login-server https://${HEADSCALE_DOMAIN} --authkey <your-key>${NC}"
echo ""
echo -e "${YELLOW}Useful Commands:${NC}"
echo ""
echo "  • Check status:         ${BLUE}./status.sh${NC}"
echo "  • List nodes:           ${BLUE}kubectl exec -it deploy/headscale -n ${NAMESPACE} -- headscale nodes list${NC}"
echo "  • Headscale logs:       ${BLUE}kubectl logs -f deploy/headscale -n ${NAMESPACE}${NC}"
echo "  • Cloudflared logs:     ${BLUE}kubectl logs -f deploy/cloudflared -n ${NAMESPACE}${NC}"
echo ""
echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""
