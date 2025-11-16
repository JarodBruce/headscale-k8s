#!/usr/bin/env bash
set -euo pipefail

# Ensure we are at repo root regardless of invocation path.
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR"

if [[ ! -f .env ]]; then
  echo "Error: .env not found. Copy .env.example and populate it first." >&2
  exit 1
fi

for bin in envsubst kubectl; do
  if ! command -v "$bin" >/dev/null 2>&1; then
    echo "Error: Required command '$bin' is not available in PATH." >&2
    exit 1
  fi
done

set -a
source .env
set +a

required_secrets=(
  CLOUDFLARE_TUNNEL_SECRET
  CLOUDFLARE_TUNNEL_CREDENTIALS_JSON
)
missing=()
for var in "${required_secrets[@]}"; do
  if [[ -z "${!var:-}" ]]; then
    missing+=("$var")
  fi
done

if (( ${#missing[@]} > 0 )); then
  echo "Error: The following variables are empty: ${missing[*]}" >&2
  exit 1
fi

echo "Applying Headscale manifests to namespace '${NAMESPACE}'..."
kubectl apply -f <(envsubst < k8s/headscale.yaml)

echo "Applying Cloudflare Tunnel manifests to namespace '${NAMESPACE}'..."
kubectl apply -f <(envsubst < k8s/cloudflare.yaml)

echo "Waiting for pods to become Ready in namespace '${NAMESPACE}'..."
kubectl get pods -n "${NAMESPACE}"
