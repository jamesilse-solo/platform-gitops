#!/bin/bash
# Run this after every VM restart
# Usage: bash scripts/recover.sh

set -e
echo "=== Platform GitOps Recovery Script ==="

echo "[1/4] Waiting 20s for cluster to stabilise..."
sleep 20

echo "[2/4] Cleaning up Unknown state pods..."
kubectl get pods -A --field-selector=status.phase=Unknown \
  -o json 2>/dev/null | \
  jq -r '.items[] | .metadata.namespace + " " + .metadata.name' | \
  while read ns name; do
    echo "  Deleting stuck pod: $name in $ns"
    kubectl delete pod "$name" -n "$ns" --force \
      --grace-period=0 2>/dev/null || true
  done

echo "[3/4] Applying ArgoCD ApplicationSet CRD..."
kubectl apply -f https://raw.githubusercontent.com/argoproj/argo-cd/v3.0.0/manifests/crds/applicationset-crd.yaml

echo "[4/4] Applying root bootstrap app..."
kubectl apply -f bootstrap/root-app.yaml

echo ""
echo "=== Done! Waiting for ArgoCD to sync... ==="
kubectl get pods -n argocd
