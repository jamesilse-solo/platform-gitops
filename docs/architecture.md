This platform follows a GitOps-based architecture:

1. Developer updates manifests in Git
2. ArgoCD detects changes and syncs cluster
3. Argo Rollouts performs canary deployment
4. Istio routes traffic between versions
5. Prometheus collects metrics
6. Rollout decision is made based on success rate
7. If metrics fail → automatic rollback

This ensures safe, observable, and controlled deployments.
