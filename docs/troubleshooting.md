Issue: New version deployed but old version (v2) still serving traffic

Cause:
- Rollout analysis failed due to missing metrics
- Istio VirtualService still routing to stable

Fix:
- Verified AnalysisTemplate query
- Generated traffic for metrics
- Retried rollout
