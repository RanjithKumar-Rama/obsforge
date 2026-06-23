#!/usr/bin/env bash
# Deploys the full ObsForge stack to the 'monitoring' namespace.
# Applies manifests in dependency order and waits for readiness between stages.
#
# Prerequisites: run scripts/create-secrets.sh first.

set -euo pipefail

K8S_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/../k8s"
NAMESPACE="monitoring"

wait_rollout() {
  local kind=$1
  local name=$2
  echo "  waiting for $kind/$name..."
  kubectl rollout status "$kind/$name" -n "$NAMESPACE" --timeout=5m
}

echo "=== ObsForge Deploy ==="
echo ""

# ── Base ─────────────────────────────────────────────────────────
echo "[1/6] Namespace + RBAC"
kubectl apply -f "${K8S_DIR}/namespace.yml"
kubectl apply -f "${K8S_DIR}/prometheus/rbac.yml"

# ── Prometheus + Sidecars ─────────────────────────────────────────
echo "[2/6] Prometheus HA (replica A and B)"
kubectl apply -f "${K8S_DIR}/prometheus/configmap.yml"
kubectl apply -f "${K8S_DIR}/prometheus/statefulset-a.yml"
kubectl apply -f "${K8S_DIR}/prometheus/statefulset-b.yml"
wait_rollout statefulset prometheus-a
wait_rollout statefulset prometheus-b

# ── Store Gateway ─────────────────────────────────────────────────
echo "[3/6] Thanos Store Gateway"
kubectl apply -f "${K8S_DIR}/thanos/store-gateway.yml"
wait_rollout statefulset thanos-store-gateway

# ── Query path ────────────────────────────────────────────────────
echo "[4/6] Thanos Querier + Query Frontend"
kubectl apply -f "${K8S_DIR}/thanos/querier.yml"
wait_rollout deployment thanos-querier
kubectl apply -f "${K8S_DIR}/thanos/query-frontend.yml"
wait_rollout deployment thanos-query-frontend

# ── Background jobs ───────────────────────────────────────────────
echo "[5/6] Thanos Compactor + Ruler"
kubectl apply -f "${K8S_DIR}/thanos/compactor.yml"
# Ruler is optional — comment this out if you don't need global alert rules
kubectl apply -f "${K8S_DIR}/thanos/ruler.yml"

# ── Grafana ───────────────────────────────────────────────────────
echo "[6/6] Grafana"
kubectl apply -f "${K8S_DIR}/grafana/configmap.yml"
kubectl apply -f "${K8S_DIR}/grafana/deployment.yml"
wait_rollout deployment grafana

# ── Summary ───────────────────────────────────────────────────────
echo ""
echo "=== Deploy complete ==="
echo ""
echo "Grafana LoadBalancer hostname:"
kubectl get svc grafana -n "$NAMESPACE" \
  -o jsonpath='{.status.loadBalancer.ingress[0].hostname}{"\n"}' 2>/dev/null \
  || echo "  (LoadBalancer IP/hostname not yet assigned — check: kubectl get svc grafana -n $NAMESPACE)"
echo ""
echo "Pod status:"
kubectl get pods -n "$NAMESPACE" -o wide
