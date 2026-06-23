#!/usr/bin/env bash
# Removes the full ObsForge stack from the 'monitoring' namespace.
#
# This deletes all Kubernetes resources including PVCs (local metric data).
# Data already uploaded to S3 is NOT touched by this script.

set -euo pipefail

NAMESPACE="monitoring"
K8S_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/../k8s"

echo "This will delete all ObsForge resources in namespace '$NAMESPACE'."
echo "PVCs (local Prometheus data) will be removed. S3 data is untouched."
echo ""
read -rp "Type 'yes' to continue: " confirm

if [[ "$confirm" != "yes" ]]; then
  echo "Aborted."
  exit 0
fi

echo "Removing Grafana..."
kubectl delete -f "${K8S_DIR}/grafana/" --ignore-not-found

echo "Removing Thanos components..."
kubectl delete -f "${K8S_DIR}/thanos/" --ignore-not-found

echo "Removing Prometheus..."
kubectl delete -f "${K8S_DIR}/prometheus/" --ignore-not-found

echo "Removing secrets and config..."
kubectl delete secret thanos-objstore grafana-secret -n "$NAMESPACE" --ignore-not-found
kubectl delete configmap obsforge-config -n "$NAMESPACE" --ignore-not-found

echo "Removing namespace..."
kubectl delete namespace "$NAMESPACE" --ignore-not-found

echo ""
echo "Done. Check for orphaned PVs with: kubectl get pv"
