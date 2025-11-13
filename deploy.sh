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
        echo ""
        print_info "Required settings:"
        print_info "  - HEADSCALE_DOMAIN: Your domain (e.g., headscale.example.com)"
        print_info "  - CLOUDFLARE_API_TOKEN: Your Cloudflare API token (with tunnel permissions)"
        print_info "  - NAMESPACE: Kubernetes namespace (default: headscale)"
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
    "CLOUDFLARE_API_TOKEN"
    "NAMESPACE"
)

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
CLOUDFLARE_ACCOUNT_ID=${CLOUDFLARE_ACCOUNT_ID:-""}



print_info "Configuration:"
print_info "  Domain: ${HEADSCALE_DOMAIN}"
print_info "  Namespace: ${NAMESPACE}"
print_info "  Storage Class: ${STORAGE_CLASS}"
print_info "  Storage Size: ${STORAGE_SIZE}"
print_info "  Timezone: ${TZ}"
print_info "  Mode: Automatic tunnel setup (using API Token)"

# Test kubectl connection
print_step "Testing kubectl connection..."
if ! kubectl cluster-info &> /dev/null; then
    print_error "Cannot connect to Kubernetes cluster!"
    exit 1
fi
print_success "Successfully connected to Kubernetes cluster"

# Create temporary directory for processed manifests
TMP_DIR=$(mktemp -d)
trap "rm -rf ${TMP_DIR}" EXIT

print_step "Processing manifest templates..."

# Process namespace.yaml
sed "s|namespace: headscale|namespace: ${NAMESPACE}|g; s|name: headscale|name: ${NAMESPACE}|g" \
    k8s/namespace.yaml > "${TMP_DIR}/namespace.yaml"

# Process headscale.yaml
sed -e "s|HEADSCALE_DOMAIN_PLACEHOLDER|${HEADSCALE_DOMAIN}|g" \
    -e "s|STORAGE_CLASS_PLACEHOLDER|${STORAGE_CLASS}|g" \
    -e "s|STORAGE_SIZE_PLACEHOLDER|${STORAGE_SIZE}|g" \
    -e "s|TZ_PLACEHOLDER|${TZ}|g" \
    -e "s|namespace: headscale|namespace: ${NAMESPACE}|g" \
    k8s/headscale.yaml > "${TMP_DIR}/headscale.yaml"

# Process cloudflared.yaml
sed -e "s|HEADSCALE_DOMAIN_PLACEHOLDER|${HEADSCALE_DOMAIN}|g" \
    -e "s|CLOUDFLARE_API_TOKEN_PLACEHOLDER|${CLOUDFLARE_API_TOKEN}|g" \
    -e "s|CLOUDFLARE_ACCOUNT_ID_PLACEHOLDER|${CLOUDFLARE_ACCOUNT_ID}|g" \
    -e "s|TZ_PLACEHOLDER|${TZ}|g" \
    -e "s|namespace: headscale|namespace: ${NAMESPACE}|g" \
    k8s/cloudflared.yaml > "${TMP_DIR}/cloudflared.yaml"

echo ""
print_step "Deploying to Kubernetes..."
echo ""

# Deploy resources
print_step "1/3 Creating namespace '${NAMESPACE}'..."
kubectl apply -f "${TMP_DIR}/namespace.yaml"
print_success "Namespace created"

print_step "2/3 Deploying Headscale..."
kubectl apply -f "${TMP_DIR}/headscale.yaml"
print_success "Headscale deployed"

print_step "3/4 Deploying Cloudflared Tunnel (with automatic setup)..."
kubectl apply -f "${TMP_DIR}/cloudflared.yaml"
print_success "Cloudflared deployed"

echo ""
print_step "4/4 Waiting for setup job to complete (this may take 1-2 minutes)..."
kubectl wait --for=condition=complete job/cloudflared-setup -n "${NAMESPACE}" --timeout=180s 2>/dev/null || {
    print_warning "Setup job taking longer than expected..."
    kubectl logs -n "${NAMESPACE}" job/cloudflared-setup | tail -20
}

echo ""
print_step "Waiting for deployments to be ready..."
kubectl wait --for=condition=available deployment/headscale -n "${NAMESPACE}" --timeout=120s 2>/dev/null || {
    print_warning "Headscale deployment taking longer than expected, continuing anyway..."
}
kubectl wait --for=condition=available deployment/cloudflared -n "${NAMESPACE}" --timeout=120s 2>/dev/null || {
    print_warning "Cloudflared deployment taking longer than expected, continuing anyway..."
}

# Display final status
echo ""
print_info "Current status:"
kubectl get pods -n "${NAMESPACE}" -o wide

echo ""
echo ""
echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${GREEN}                        🎉 Deployment Complete! 🎉${NC}"
echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""
echo -e "${CYAN}Headscale URL:${NC} https://${HEADSCALE_DOMAIN}"
echo ""
echo -e "${YELLOW}Important:${NC}"
echo "1. Check setup job status:"
echo "   ${BLUE}kubectl logs -n ${NAMESPACE} job/cloudflared-setup${NC}"
echo ""
echo "2. Once tunnel is setup, configure DNS in Cloudflare:"
echo "   - Type: CNAME"
echo "   - Name: ${HEADSCALE_DOMAIN}"
echo "   - Content: <TUNNEL_ID>.cfargotunnel.com (see job logs)"
echo "   - Proxy: Proxied (orange cloud)"
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
echo "  • Check status:         ${BLUE}kubectl get pods -n ${NAMESPACE}${NC}"
echo "  • List nodes:           ${BLUE}kubectl exec -it deploy/headscale -n ${NAMESPACE} -- headscale nodes list${NC}"
echo "  • List users:           ${BLUE}kubectl exec -it deploy/headscale -n ${NAMESPACE} -- headscale users list${NC}"
echo "  • Headscale logs:       ${BLUE}kubectl logs -f deploy/headscale -n ${NAMESPACE}${NC}"
echo "  • Cloudflared logs:     ${BLUE}kubectl logs -f deploy/cloudflared -n ${NAMESPACE}${NC}"
echo "  • Setup job logs:       ${BLUE}kubectl logs -f job/cloudflared-setup -n ${NAMESPACE}${NC}"
echo ""
echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""
