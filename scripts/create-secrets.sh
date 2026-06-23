#!/usr/bin/env bash
# Creates all Kubernetes Secrets and ConfigMaps from your .env file.
# Run this once before deploy.sh and any time you rotate credentials.
#
# 
#   - thanos-objstore    Secret  (S3/GCS/Azure bucket credentials)
#   - grafana-secret     Secret  (Grafana admin password)
#   - obsforge-config    ConfigMap (retention settings, cluster name)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_FILE="${SCRIPT_DIR}/../.env"
BUCKET_TEMPLATE="${SCRIPT_DIR}/../config/thanos/bucket.yml.example"
NAMESPACE="monitoring"

# ## Preflight 
if [[ ! -f "$ENV_FILE" ]]; then
  echo "ERROR: .env not found. Copy .env.example to .env and fill in your values."
  exit 1
fi

if ! command -v envsubst &>/dev/null; then
  echo "ERROR: envsubst not found. Install it with:"
  echo "  apt install gettext-base   (Debian/Ubuntu)"
  echo "  brew install gettext       (macOS)"
  exit 1
fi

# shellcheck source=/dev/null
source "$ENV_FILE"

# ## Namespace 
echo "Applying namespace..."
kubectl apply -f "${SCRIPT_DIR}/../k8s/namespace.yml"

# ## Object storage secret 
echo "Creating thanos-objstore secret..."
BUCKET_CONTENT=$(envsubst < "$BUCKET_TEMPLATE")
kubectl create secret generic thanos-objstore \
  --namespace="$NAMESPACE" \
  --from-literal=bucket.yml="$BUCKET_CONTENT" \
  --dry-run=client -o yaml | kubectl apply -f -

# ## Grafana secret 
echo "Creating grafana-secret..."
kubectl create secret generic grafana-secret \
  --namespace="$NAMESPACE" \
  --from-literal=admin-password="${GRAFANA_ADMIN_PASSWORD}" \
  --dry-run=client -o yaml | kubectl apply -f -

# ## Non-sensitive config 
echo "Creating obsforge-config ConfigMap..."
kubectl create configmap obsforge-config \
  --namespace="$NAMESPACE" \
  --from-literal=CLUSTER_NAME="${CLUSTER_NAME:-prod}" \
  --from-literal=RETENTION_RAW="${RETENTION_RAW:-30d}" \
  --from-literal=RETENTION_5M="${RETENTION_5M:-90d}" \
  --from-literal=RETENTION_1H="${RETENTION_1H:-1y}" \
  --dry-run=client -o yaml | kubectl apply -f -

echo ""
echo "Done. Secrets and config are in namespace: $NAMESPACE"
echo "Run ./scripts/deploy.sh to deploy the stack."
