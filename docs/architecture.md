This platform follows a GitOps-based architecture:

1. Developer updates manifests in Git
2. ArgoCD detects changes and syncs cluster
3. Argo Rollouts performs canary deployment
4. AgentGateway (Gateway API) shifts north-south traffic between the stable and canary services via HTTPRoute weights
5. Ambient mesh (ztunnel + waypoint) enforces mTLS and L7 policy east-west, and emits Prometheus metrics from the waypoint
6. Argo Rollouts queries Prometheus (`istio_requests_total` from the waypoint) to gate each canary step
7. If success rate < 95% → automatic rollback; else promote

This ensures safe, observable, and controlled deployments — without sidecars.
