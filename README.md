# 🚀 Platform GitOps

A production-grade GitOps platform built on **Kubernetes**, using **ArgoCD** for continuous delivery, **Istio** for service mesh, **Argo Rollouts** for progressive delivery, and **Kyverno** for policy enforcement.

---

## 📐 Architecture Overview

```
                          ┌─────────────────────────────────────────┐
                          │              ArgoCD                      │
                          │   (Watches this repo, syncs cluster)     │
                          └────────────┬────────────────────────────┘
                                       │
            ┌──────────────────────────┼──────────────────────────┐
            │                          │                          │
     ┌──────▼──────┐          ┌────────▼──────┐         ┌────────▼──────┐
     │  Istio      │          │  Kyverno      │         │  Applications │
     │  (Service   │          │  (Policies)   │         │  (nginx,      │
     │   Mesh)     │          │               │         │   node-app)   │
     └─────────────┘          └───────────────┘         └───────────────┘
```

Traffic flows via the **Istio Ingress Gateway → nginx (reverse proxy) → node-app**, with mTLS enforced across the mesh and Kyverno validating all workloads at admission time.

---

## 📁 Repository Structure

```
platform-gitops/
├── apps/                    # ArgoCD Application manifests (App of Apps pattern)
│   ├── istio.yaml           # Deploys Istio config from /istio
│   ├── nginx.yaml           # Deploys nginx via Helm chart
│   ├── node-app.yaml        # Deploys node-app (uses Argo Rollouts)
│   ├── policies.yaml        # Deploys Kyverno policies from /policies
│   ├── kyverno/
│   │   └── kyverno.yaml     # Installs Kyverno from Helm chart
│   └── node-app/
│       ├── rollout.yaml     # Argo Rollouts canary strategy
│       └── service.yaml     # Stable + canary services
│
├── istio/                   # Istio networking & security config
│   ├── gateway.yaml         # Ingress gateway (HTTP on port 80)
│   ├── virtualservice.yaml  # Traffic split: stable vs canary
│   ├── destinationrule.yaml # Circuit breaker + outlier detection
│   ├── mtls-strict.yaml     # Enforce mTLS across default namespace
│   ├── allow-nginx.yaml     # AuthorizationPolicy for nginx
│   └── allow-node-app.yaml  # AuthorizationPolicy for node-app
│
├── nginx-chart/             # Custom Helm chart for nginx (ingress proxy)
│   ├── Chart.yaml
│   ├── values.yaml
│   └── templates/
│       ├── deployment.yaml
│       ├── service.yaml
│       └── httproute.yaml
│
├── nginx/                   # Raw nginx manifests (for reference/testing)
│   ├── deployment.yaml
│   └── service.yaml
│
├── policies/                # Kyverno + Kubernetes NetworkPolicies
│   ├── require-limits.yaml  # Enforce CPU/memory limits on all workloads
│   ├── allow-nginx.yaml     # NetworkPolicy: allow ingress/egress for nginx
│   └── allow-dns.yaml       # NetworkPolicy: allow DNS egress (UDP/TCP 53)
│
├── projects/
│   └── project.yaml         # ArgoCD AppProject: platform-project
│
└── rollouts/
    └── analysis-template.yaml  # Prometheus-based canary success rate check
```

---

## 🧩 Components

### ArgoCD — GitOps Engine
All applications are declared as `Application` CRDs under `apps/` and grouped under the `platform-project` AppProject. ArgoCD watches this repo on `main` and auto-syncs with `prune: true` and `selfHeal: true`.

### Istio — Service Mesh
- **mTLS STRICT** enforced across the `default` namespace
- **AuthorizationPolicies** allow traffic only from the Istio ingress gateway service account
- **VirtualService** manages the canary/stable traffic split for `node-app`
- **DestinationRule** configures connection pooling and outlier detection (circuit breaker)

### Argo Rollouts — Progressive Delivery
`node-app` uses a **canary deployment strategy** with automated traffic shifting:

| Step | Canary Weight | Analysis |
|------|--------------|---------|
| 1    | 10%          | ✅ Success rate check |
| 2    | 30%          | ✅ Success rate check |
| 3    | 60%          | ✅ Success rate check |
| 4    | 100%         | — |

Traffic is routed through Istio's VirtualService. If the success rate drops below **95%**, the rollout is automatically aborted.

### Kyverno — Policy Engine
- `require-resource-limits`: Enforces CPU and memory limits on all `Deployment`, `StatefulSet`, `DaemonSet`, and `Job` workloads (excludes system namespaces)
- NetworkPolicies restrict ingress/egress for nginx and ensure DNS resolution always works

---

## ⚡ Getting Started

### Prerequisites

| Tool | Version |
|------|---------|
| Kubernetes | ≥ 1.27 |
| ArgoCD | ≥ 2.8 |
| Istio | ≥ 1.18 |
| Argo Rollouts | ≥ 1.6 |
| Kyverno | 3.0.0 |
| Helm | ≥ 3.x |

### 1. Install ArgoCD

```bash
kubectl create namespace argocd
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml
```

### 2. Install Istio

```bash
istioctl install --set profile=default -y
kubectl label namespace default istio-injection=enabled
```

### 3. Install Argo Rollouts

```bash
kubectl create namespace argo-rollouts
kubectl apply -n argo-rollouts -f https://github.com/argoproj/argo-rollouts/releases/latest/download/install.yaml
```

### 4. Bootstrap the Platform

Apply the ArgoCD AppProject and App-of-Apps:

```bash
kubectl apply -f projects/project.yaml
kubectl apply -f apps/kyverno/kyverno.yaml
kubectl apply -f apps/
```

ArgoCD will now reconcile all other applications automatically.

---

## 🔁 Canary Deployment Flow

```
New image pushed
       │
       ▼
ArgoCD detects change in rollout.yaml
       │
       ▼
Argo Rollouts starts canary
       │
  10% → analysis → 30% → analysis → 60% → analysis → 100%
       │
  If success rate < 95% at any step → auto rollback
```

To manually promote or abort a rollout:

```bash
# Check rollout status
kubectl argo rollouts get rollout node-app -n default --watch

# Promote to next step
kubectl argo rollouts promote node-app -n default

# Abort and rollback
kubectl argo rollouts abort node-app -n default
```

---

## 🛡️ Security Model

| Control | Implementation |
|---------|---------------|
| mTLS | `PeerAuthentication` – STRICT mode in `default` namespace |
| Authorization | `AuthorizationPolicy` – ingress gateway SA only |
| Network isolation | `NetworkPolicy` – explicit allow-list for nginx and DNS |
| Resource governance | Kyverno `ClusterPolicy` – CPU/memory limits required |

---

## 📊 Observability

The `AnalysisTemplate` in `rollouts/analysis-template.yaml` queries Prometheus for Istio request success rates:

```promql
sum(irate(istio_requests_total{destination_service=~"node-app.*", response_code!~"5.*"}[1m]))
/
sum(irate(istio_requests_total{destination_service=~"node-app.*"}[1m]))
```

**Success threshold**: ≥ 95%  
**Evaluated**: every 30s, 3 times per step  
**Failure tolerance**: up to 10 failures before abort

> ⚠️ Update the Prometheus address in `rollouts/analysis-template.yaml` to point to your actual Prometheus instance before using this in production.

---

## 🗂️ ArgoCD Applications Summary

| Application | Source | Namespace | Sync |
|-------------|--------|-----------|------|
| `kyverno` | Helm chart (kyverno.github.io) | `kyverno` | Auto |
| `istio-config` | `./istio` | `default` | Auto |
| `nginx-app` | `./nginx-chart` | `default` | Auto |
| `node-app` | `./apps/node-app` | `default` | Auto |
| `policies` | `./policies` | `default` | Auto |

---

## 🤝 Contributing

1. Fork the repo and create a feature branch
2. Make changes — ArgoCD will validate via dry-run on PRs
3. Ensure all workloads declare CPU/memory limits (enforced by Kyverno)
4. Open a PR targeting `main`

---

## 📄 License

MIT
