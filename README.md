<div align="center">

# Platform GitOps — Ambient + AgentGateway

**Enterprise GitOps Delivery Platform for Kubernetes — sidecar-free variant**

[![ArgoCD](https://img.shields.io/badge/ArgoCD-v3.3.6-EF7B4D?style=for-the-badge&logo=argo&logoColor=white)](https://argo-cd.readthedocs.io/)
[![Kubernetes](https://img.shields.io/badge/Kubernetes-k3s-326CE5?style=for-the-badge&logo=kubernetes&logoColor=white)](https://k3s.io/)
[![Ambient Mesh](https://img.shields.io/badge/Istio-Ambient_mTLS-466BB0?style=for-the-badge&logo=istio&logoColor=white)](https://istio.io/latest/docs/ambient/)
[![AgentGateway](https://img.shields.io/badge/AgentGateway-Ingress-14B8A6?style=for-the-badge)](https://agentgateway.dev/)
[![Argo Rollouts](https://img.shields.io/badge/Argo_Rollouts-Canary-FF6F00?style=for-the-badge&logo=argo&logoColor=white)](https://argoproj.github.io/argo-rollouts/)
[![Kyverno](https://img.shields.io/badge/Kyverno-Policy_as_Code-2B5FAB?style=for-the-badge)](https://kyverno.io/)
[![Prometheus](https://img.shields.io/badge/Prometheus-SLO_Analysis-E6522C?style=for-the-badge&logo=prometheus&logoColor=white)](https://prometheus.io/)

*Same platform, no sidecars. Ingress via AgentGateway (Gateway API), east-west via Istio Ambient (ztunnel + waypoint).*

</div>

---

## What this branch changes

This is the `ambient-agentgateway` branch — a drop-in variant of the `main` platform with two swaps:

| Concern | `main` (sidecar) | `ambient-agentgateway` |
|---|---|---|
| Data-plane injection | Istio sidecar per pod (`sidecar.istio.io/inject: "true"`) | Ambient — ztunnel per node, waypoint per namespace |
| North-south ingress | `istio-ingressgateway` + `Gateway` + `VirtualService` | AgentGateway + Gateway API `Gateway` + `HTTPRoute` |
| Canary traffic split | `VirtualService` weights driven by Argo Rollouts Istio plugin | `HTTPRoute` weights driven by Argo Rollouts Gateway API plugin |
| Subset routing | `DestinationRule` `subsets` + pod-label selectors | Two Services (`stable`, `canary`) as HTTPRoute backendRefs |
| L7 authorization | `AuthorizationPolicy` enforced by sidecar | `AuthorizationPolicy` enforced by waypoint |
| mTLS | `PeerAuthentication: STRICT` via sidecar | `PeerAuthentication: STRICT` via ztunnel (same CR, different enforcement point) |
| Metrics | Sidecar emits `istio_requests_total` | Waypoint emits `istio_requests_total{reporter="waypoint"}` |

Kyverno, Argo Rollouts, ArgoCD, the analysis template, and the app-of-apps layout are unchanged.

---

## Platform flow

```
Git commit (ambient-agentgateway)
        │
        ▼
root-app.yaml ── App-of-Apps bootstrap
        │
        ▼
ArgoCD ── reconciles 6 applications
        │
        ├──▶ ambient-config     (path: ambient/)     — waypoint, PeerAuth, AuthzPolicies
        ├──▶ agentgateway-config (path: agentgateway/) — Gateway, HTTPRoute
        ├──▶ kyverno            (Helm 3.0.0)
        ├──▶ nginx-app          (Helm chart)
        ├──▶ node-app           (Argo Rollout)
        └──▶ policies           (Kyverno + NetworkPolicy)
                │
                ▼
    Kubernetes cluster
                │
        ┌───────┴──────────────────────┐
        │                              │
        ▼                              ▼
  Kyverno gate                 Ambient mesh
  (admission)                  ┌───────────────────────────┐
        │                      │  ztunnel  (L4 mTLS)       │
        │                      │  waypoint (L7 policy)     │
        │                      └───────────────────────────┘
        │                              │
        └────────┬─────────────────────┘
                 │
                 ▼
  Client ──▶ AgentGateway ──HTTPRoute weights──▶ node-app-{stable,canary}
                                                          │
                                              Argo Rollouts canary
                                              10% → 30% → 60% → 100%
                                                 (waypoint metrics gate each step)
                                                          │
                                                  ┌───────┴───────┐
                                                  ▼               ▼
                                               promote         rollback
                                              (≥ 95%)         (< 95%)
```

---

## Repository layout — what moved

```
platform-gitops/
│
├── ambient/                     # (was istio/) — ambient config + waypoint
│   ├── namespace.yaml            ← labels default ns with dataplane-mode: ambient
│   ├── waypoint.yaml             ← namespace waypoint (Gateway API, class: istio-waypoint)
│   ├── mtls-strict.yaml          ← unchanged (still PeerAuthentication STRICT)
│   ├── allow-nginx.yaml          ← AuthorizationPolicy targetRef → Service; principal → agentgateway SA
│   └── allow-node-app.yaml       ← same shape, targets node-app services
│
├── agentgateway/                # NEW — north-south ingress
│   ├── gateway.yaml              ← Gateway API Gateway, class: agentgateway
│   └── httproute-node-app.yaml   ← HTTPRoute with weighted stable/canary backendRefs
│
├── apps/
│   ├── ambient.yaml              ← (was istio.yaml) — Argo Application pointing at ambient/
│   ├── agentgateway.yaml         ← NEW — Argo Application pointing at agentgateway/
│   ├── kyverno/kyverno.yaml      ← unchanged
│   ├── nginx.yaml                ← unchanged (chart pinned to this branch)
│   ├── node-app.yaml             ← unchanged (path pinned to this branch)
│   ├── node-app/
│   │   ├── rollout.yaml          ← trafficRouting: argoproj-labs/gatewayAPI plugin
│   │   ├── service.yaml          ← unchanged
│   │   └── analysis-template.yaml ← query pins reporter="waypoint"
│   └── policies.yaml             ← unchanged
│
├── nginx-chart/
│   ├── values.yaml               ← removed sidecar.istio.io/inject; httpRoute.enabled: true
│   └── templates/httproute.yaml  ← unchanged (values now point parentRef at platform-gateway)
│
├── policies/                     ← unchanged
├── projects/project.yaml         ← whitelist swapped: gateway.networking.k8s.io kinds added,
│                                    networking.istio.io/{Gateway,VirtualService,DestinationRule} removed
├── bootstrap/                    ← unchanged shape; root-app targetRevision → ambient-agentgateway
└── docs/                         ← unchanged assets; architecture.md rewritten
```

---

## Prerequisites (what must already be on the cluster)

- **Kubernetes cluster** (k3s or otherwise)
- **ArgoCD** in the `argocd` namespace
- **Gateway API v1 CRDs** installed
- **Istio Ambient** installed with `istio-cni`, `ztunnel`, and the `istio-waypoint` GatewayClass registered
- **AgentGateway** installed with the `agentgateway` GatewayClass registered — Solo Enterprise ships this
- **Argo Rollouts** with the [Gateway API plugin](https://rollouts-plugin-trafficrouter-gatewayapi.readthedocs.io/) mounted into the controller
- **Prometheus** at `prometheus.istio-system.svc.cluster.local:9090`, scraping the waypoint proxies

---

## Bootstrap

```bash
# 1. Create the ArgoCD project boundary
kubectl --context=<ctx> apply -f projects/project.yaml

# 2. CRDs
kubectl --context=<ctx> apply -f bootstrap/argocd-crds.yaml

# 3. Deploy the root App-of-Apps — ArgoCD takes it from here
kubectl --context=<ctx> apply -f bootstrap/root-app.yaml
```

ArgoCD discovers and deploys the six applications. Within a few minutes everything should show `Healthy` + `Synced`.

---

## Verify

```bash
# Confirm the namespace is ambient-enrolled
kubectl --context=<ctx> get ns default -o jsonpath='{.metadata.labels}' | jq

# Confirm the waypoint is programmed
kubectl --context=<ctx> get gateway waypoint -n default
kubectl --context=<ctx> get pods -n default -l gateway.networking.k8s.io/gateway-name=waypoint

# Confirm the AgentGateway is programmed
kubectl --context=<ctx> get gateway platform-gateway -n default -o yaml

# Watch the canary progress via HTTPRoute weights (not VirtualService anymore)
kubectl --context=<ctx> get httproute node-app-route -n default -o yaml | yq '.spec.rules[0].backendRefs'
kubectl --context=<ctx> argo rollouts get rollout node-app --watch

# L7 authz denials will show up on the waypoint, not the sidecar:
kubectl --context=<ctx> logs -n default -l gateway.networking.k8s.io/gateway-name=waypoint --tail=50
```

---

## Notes on the swap

**AuthorizationPolicy principal.** The allow-list source is now
`cluster.local/ns/agentgateway-system/sa/agentgateway`. Adjust the namespace
and ServiceAccount to match your AgentGateway install if it lives elsewhere.

**Waypoint is required for L7.** In ambient, `AuthorizationPolicy` with L7
predicates and `istio_requests_total` metrics are emitted by the waypoint,
not the ztunnel. The namespace label `istio.io/use-waypoint: waypoint`
(see `ambient/namespace.yaml`) routes east-west traffic through it.

**DestinationRule is gone.** Subset routing was only used to steer the
canary split from the ingress. With Gateway API, the split lives on the
HTTPRoute's `backendRefs` and the two existing `node-app-{stable,canary}`
Services already do the job. The connection-pool and outlier-detection
settings from the old DR can be reintroduced via an ambient
[waypoint-scoped `DestinationRule`](https://istio.io/latest/docs/ambient/usage/waypoint/#configure-a-waypoint) if you need them.

**Sidecar annotation removed.** `nginx-chart/values.yaml` no longer sets
`sidecar.istio.io/inject: "true"`; ambient enrolment is namespace-level.

---

## Maintainer

Original repo by **Mahesh Naganna** (`main` branch). This branch is a variant
demonstrating the same platform shape with Istio Ambient + AgentGateway
substituted for the sidecar/ingress-gateway data plane.
