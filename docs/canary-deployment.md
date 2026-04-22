The node-app uses Argo Rollouts with Istio integration.

Traffic is shifted gradually:
- 10% → analysis
- 30% → analysis
- 60% → analysis
- 100%

Prometheus query evaluates success rate.
If it drops below 95%, rollout is aborted and traffic is routed back to stable version.
