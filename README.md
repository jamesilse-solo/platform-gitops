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
        ├──▶ agentgateway-oss   (Helm chart — OSS agentgateway workload)
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
│   ├── allow-agentgateway-oss.yaml ← AuthorizationPolicy targetRef → Service; principal → ingress AgentGateway SA
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
│   ├── agentgateway-oss.yaml     ← Argo Application for OSS agentgateway workload
│   ├── node-app.yaml             ← unchanged (path pinned to this branch)
│   ├── node-app/
│   │   ├── rollout.yaml          ← trafficRouting: argoproj-labs/gatewayAPI plugin
│   │   ├── service.yaml          ← unchanged
│   │   └── analysis-template.yaml ← query pins reporter="waypoint"
│   └── policies.yaml             ← unchanged
│
├── agentgateway-oss-chart/       # (was nginx-chart/) — OSS agentgateway as a workload
│   ├── Chart.yaml                ← appVersion pinned to upstream agentgateway v1.3.1
│   ├── values.yaml               ← image cr.agentgateway.dev/agentgateway; embedded config
│   └── templates/
│       ├── configmap.yaml        ← NEW — renders values.agentgateway.config into /etc/agentgateway/config.yaml
│       ├── serviceaccount.yaml   ← moved under templates/ (was a latent bug: SA never got created)
│       ├── deployment.yaml       ← mounts config ConfigMap, args -f /etc/agentgateway/config.yaml
│       ├── service.yaml          ← ClusterIP :3000
│       └── httproute.yaml        ← parentRef platform-gateway, path prefix /oss
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

## Zero-trust posture

The branch preserves every zero-trust control from `main`, just enforced by
different data-plane components:

| Control | `main` (sidecar) | `ambient-agentgateway` |
|---|---|---|
| mTLS between workloads | Sidecar Envoy handshake | ztunnel HBONE tunnel (mTLS wrapping every connection) |
| `PeerAuthentication: STRICT` | Sidecar rejects plaintext | ztunnel rejects plaintext at L4 — same CR, different enforcement point |
| Workload identity | SPIFFE issued to sidecar | SPIFFE issued to ztunnel per-pod, seeded into HBONE mTLS certs |
| Authorization | Sidecar RBAC filter | Waypoint Envoy RBAC filter (uses `io.istio.peer_principal` extracted from HBONE cert) |
| Default posture | Deny-all, explicit `AuthorizationPolicy` ALLOW | Same — `ambient/allow-*.yaml` files with `targetRefs: Service` |

**Nothing was traded away.** The waypoint runs an Envoy that terminates HBONE,
extracts the peer SPIFFE ID from the mTLS cert into a filter-state key
(`io.istio.peer_principal`), and evaluates `AuthorizationPolicy` against it —
same RBAC filter you'd find in a sidecar, just moved to a shared L7 hop.

---

## Verifying zero-trust with `istioctl`

All commands below use OSS `istioctl` (1.29). Solo's `istioctl` builds accept the
same subcommands. Assume `CTX=gke-ambient4-jilse` for the examples.

### 1. Every mesh pod has a SPIFFE identity via ztunnel

```bash
istioctl --context=$CTX ztunnel-config workloads
# NAMESPACE  POD NAME                                                 ...  PROTOCOL
# default    agentgateway-oss-agentgateway-oss-chart-58c48c9c74-l6bkr ...  HBONE
# default    node-app-5cdf79789f-9n29v                                ...  HBONE
# default    waypoint-54bf765c5b-l4hjm                                ...  TCP
```

Pods showing `PROTOCOL: HBONE` are mesh-enrolled — ztunnel is intercepting all
inbound traffic and requiring mTLS. Pods marked `TCP` are outside the mesh.

### 2. Confirm STRICT mTLS is programmed globally

```bash
istioctl --context=$CTX ztunnel-config policies
# NAMESPACE    POLICY NAME                   ACTION SCOPE
# istio-system istio_converted_static_strict Deny   WorkloadSelector
```

The `istio_converted_static_strict` entry is what the `PeerAuthentication:
STRICT` in `ambient/mtls-strict.yaml` compiles into at ztunnel. Any plaintext
connection to a mesh pod is dropped before it reaches the workload.

### 3. Inspect the compiled RBAC on the waypoint

```bash
WAYPOD=$(kubectl --context=$CTX -n default get pod \
  -l gateway.networking.k8s.io/gateway-name=waypoint \
  -o jsonpath='{.items[0].metadata.name}')

kubectl --context=$CTX -n default exec $WAYPOD -c istio-proxy -- \
  pilot-agent request GET /config_dump \
  | jq -r '[.configs[] | select(.["@type"]|test("Listeners"))] | .[0].dynamic_listeners[]
           | .active_state.listener.filter_chains[].filters[]
           | select(.name=="envoy.filters.network.http_connection_manager")
           | .typed_config.http_filters[] | select(.name=="envoy.filters.http.rbac")
           | .typed_config.rules.policies | keys'
# [ "ns[default]-policy[allow-node-app]-rule[0]" ]
# [ "ns[default]-policy[allow-agentgateway-oss]-rule[0]" ]
```

Each `AuthorizationPolicy` in `ambient/` shows up here as an RBAC policy on
the waypoint's Envoy. If it's missing, the policy isn't enforcing.

### 4. Prove default-deny with a rogue pod

```bash
kubectl --context=$CTX -n default apply -f - <<'EOF'
apiVersion: v1
kind: ServiceAccount
metadata: {name: rogue, namespace: default}
---
apiVersion: v1
kind: Pod
metadata: {name: rogue-client, namespace: default}
spec:
  serviceAccountName: rogue    # NOT in any allow-list
  containers:
    - name: c
      image: curlimages/curl:8.10.1
      command: [sleep, infinity]
EOF

kubectl --context=$CTX -n default exec rogue-client -- \
  curl -sS -o /dev/null -w 'HTTP %{http_code}\n' -m 5 \
  http://node-app-stable.default.svc.cluster.local/
# HTTP 403

kubectl --context=$CTX -n default delete pod/rogue-client sa/rogue
```

The rogue pod is inside the mesh (ambient-enrolled by the namespace label),
gets its own SPIFFE identity `spiffe://cluster.local/ns/default/sa/rogue`,
and completes the mTLS handshake — but the waypoint's RBAC filter refuses
because that SPIFFE ID isn't in `allow-node-app`'s principal list. Result:
`HTTP 403`.

### 5. Verify from waypoint metrics that mTLS and RBAC are both live

The waypoint emits `istio_requests_total` with the source SPIFFE identity, the
response code, and the connection security policy. Query Prometheus:

```
istio_requests_total{
  reporter="waypoint",
  destination_service="node-app-stable.default.svc.cluster.local"
}
```

Expected shape:

```
# Authorized:   200 + mTLS
source_principal="spiffe://cluster.local/ns/default/sa/agentgateway-oss-agentgateway-oss-chart"
response_code="200"  connection_security_policy="mutual_tls"

# Unauthorized: 403 + mTLS (identity is verified before authorization runs)
source_principal="spiffe://cluster.local/ns/default/sa/rogue"
response_code="403"  connection_security_policy="mutual_tls"
```

The `403 + mutual_tls` row is the exact signature of a zero-trust denial: the
peer authenticated cryptographically, then got refused on identity — no
network path, IP filter, or NetworkPolicy involved.

### 6. Other useful commands

```bash
istioctl --context=$CTX x describe pod <pod> -n default    # what config applies to a pod
istioctl --context=$CTX proxy-config all $WAYPOD.default   # entire Envoy config on the waypoint
istioctl --context=$CTX analyze -n default                 # mesh config sanity check
```

---

## Optional: running without a waypoint (L4-only zero-trust)

The waypoint is the L7 policy + telemetry hop. If you don't need HTTP-level
authorization (`paths`, `methods`, headers) or `istio_requests_total`
metrics, you can drop it — the ztunnel keeps enforcing mTLS + L4 authz on
its own.

### What you get without a waypoint

| Control | Without waypoint | Notes |
|---|---|---|
| mTLS STRICT | ✅ ztunnel enforces | `PeerAuthentication` still works |
| L4 authz (source principal, source ns, ports) | ✅ ztunnel enforces | `AuthorizationPolicy` without `to.operation.paths` |
| L7 authz (paths, methods, headers) | ❌ silently ignored | Needs a waypoint to evaluate |
| `istio_requests_total` per-service | ❌ | Only L4 byte counters emit from ztunnel |
| `AnalysisTemplate` Prometheus canary gate | ❌ won't work as-is | Depends on `istio_requests_total` |

### How to disable the waypoint

1. Drop the namespace opt-in label:

   ```yaml
   # ambient/namespace.yaml
   apiVersion: v1
   kind: Namespace
   metadata:
     name: default
     labels:
       istio.io/dataplane-mode: ambient
       # istio.io/use-waypoint: waypoint   ← comment out or delete
   ```

2. Delete `ambient/waypoint.yaml` from the branch. The `waypoint` Gateway
   resource stops being reconciled and its Deployment is pruned by ArgoCD.

3. Simplify each `AuthorizationPolicy` to L4-only rules — anything under
   `rules[].to.operation.paths` / `methods` / `hosts` is dropped by ztunnel:

   ```yaml
   # ambient/allow-node-app.yaml (L4-only variant)
   spec:
     targetRefs:                # ztunnel does support Service targetRefs
       - group: ""
         kind: Service
         name: node-app-stable
     action: ALLOW
     rules:
       - from:
           - source:
               principals:
                 - cluster.local/ns/agentgateway-system/sa/agentgateway
                 - cluster.local/ns/default/sa/agentgateway-oss-agentgateway-oss-chart
         # no `to.operation.*` fields
   ```

4. Repoint the canary `AnalysisTemplate` at an alternate metric source. The
   AgentGateway ingress and the OSS agentgateway workload both emit
   Prometheus counters on their own — `agentgateway_http_requests_total`
   or the Prometheus scrape configured under `podAnnotations` — which
   work regardless of waypoint presence.

### Selective waypointing (middle ground)

If you want L7 policy for only a subset of workloads, drop the
namespace-scoped label and instead label individual Services or Pods:

```yaml
# on the Service you want L7-policed
apiVersion: v1
kind: Service
metadata:
  name: node-app-stable
  namespace: default
  labels:
    istio.io/use-waypoint: waypoint
```

Everything else in the namespace runs ztunnel-only. `istioctl ztunnel-config
workloads` will show a `WAYPOINT` column pointing at `waypoint` for the
opted-in services and `None` for the rest.

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

**nginx replaced with OSS agentgateway.** The generic web-server workload
that lived in `nginx-chart/` is now `agentgateway-oss-chart/`, deploying
the upstream open-source [agentgateway](https://agentgateway.dev)
(`cr.agentgateway.dev/agentgateway:v1.3.1`) as an in-cluster reverse
proxy. Its config lives in a ConfigMap generated from
`values.agentgateway.config` and is mounted at
`/etc/agentgateway/config.yaml`. The chart's HTTPRoute attaches to the
same `platform-gateway` Gateway at `pathPrefix: /oss` so it doesn't
shadow the node-app canary route.

**Sidecar annotation removed.** `agentgateway-oss-chart/values.yaml` no longer sets
`sidecar.istio.io/inject: "true"`; ambient enrolment is namespace-level.

---

## Maintainer

Original repo by **Mahesh Naganna** (`main` branch). This branch is a variant
demonstrating the same platform shape with Istio Ambient + AgentGateway
substituted for the sidecar/ingress-gateway data plane.
