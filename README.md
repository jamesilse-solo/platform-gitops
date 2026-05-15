<div align="center">

# 🚀 Platform GitOps
### Enterprise GitOps Delivery Platform for Kubernetes

<p>
  <img src="https://img.shields.io/badge/ArgoCD-GitOps-EF7B4D?logo=argo" />
  <img src="https://img.shields.io/badge/Kubernetes-1.27+-326CE5?logo=kubernetes" />
  <img src="https://img.shields.io/badge/Istio-Service%20Mesh-466BB0" />
  <img src="https://img.shields.io/badge/Argo%20Rollouts-Canary-FF6F00" />
  <img src="https://img.shields.io/badge/Kyverno-Policy%20as%20Code-2B5FAB" />
  <img src="https://img.shields.io/badge/Prometheus-Observability-E6522C?logo=prometheus" />
</p>

**Git as the Source of Truth for Secure, Progressive Kubernetes Delivery**

</div>

---

## 🎯 Overview

This repository implements a production-grade GitOps platform built on Kubernetes.

It combines:

- 🔄 ArgoCD for continuous delivery
- 🌐 Istio for service mesh and mTLS
- 🚀 Argo Rollouts for canary deployments
- 🛡️ Kyverno for policy enforcement
- 📈 Prometheus-based rollout analysis
- 🔐 Network policies and zero-trust controls

---

## 🏗️ Architecture

```text
Git Commit
    ↓
ArgoCD
    ↓
Kubernetes
    ├── Istio (mTLS + traffic routing)
    ├── Kyverno (admission policies)
    ├── Argo Rollouts (canary deployments)
    ├── Prometheus (metrics and SLOs)
    └── Applications (nginx, node-app)
```

---

## 📁 Repository Structure

```text
platform-gitops/
├── apps/          # ArgoCD Applications (App-of-Apps)
├── istio/         # Gateway, VirtualService, DestinationRule
├── nginx-chart/   # Custom Helm chart
├── policies/      # Kyverno and NetworkPolicies
├── projects/      # ArgoCD AppProject
└── rollouts/      # AnalysisTemplate
```

---

## 🔄 GitOps Workflow

```text
Developer Commit
      ↓
Git Repository
      ↓
ArgoCD Detects Change
      ↓
Auto Sync (self-heal + prune)
      ↓
Kubernetes Reconciliation
      ↓
Canary Deployment
      ↓
Prometheus Validation
      ↓
Promote or Rollback
```

---

## 🚀 Progressive Delivery

Canary rollout progression:

```text
10% → 30% → 60% → 100%
```

If success rate drops below **95%**, the rollout is aborted and traffic is reverted automatically.

---

## 🛡️ Security Controls

| Control | Technology |
|-------|-------|
| Mutual TLS | Istio PeerAuthentication |
| Authorization | Istio AuthorizationPolicy |
| Resource Governance | Kyverno ClusterPolicy |
| Network Isolation | Kubernetes NetworkPolicy |

---

## 📊 Observability

Prometheus evaluates rollout health using Istio request metrics.

### Sample PromQL

```promql
sum(irate(istio_requests_total{response_code!~"5.*"}[1m]))
/
sum(irate(istio_requests_total[1m]))
```

Used by Argo Rollouts to decide whether to continue or rollback.

---

## 🧩 Core Components

| Component | Purpose |
|--------|--------|
| ArgoCD | GitOps reconciliation |
| Istio | Service mesh and traffic control |
| Argo Rollouts | Progressive delivery |
| Kyverno | Policy-as-code |
| Prometheus | Metrics and SLO analysis |
| NGINX | Reverse proxy |
| Node App | Sample application |

---

## ⚡ Getting Started

### Install ArgoCD

```bash
kubectl create namespace argocd
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml
```

### Bootstrap Platform

```bash
kubectl apply -f projects/project.yaml
kubectl apply -f apps/
```

ArgoCD will automatically deploy all components.

---

## 🧠 Enterprise Patterns Demonstrated

- GitOps architecture
- App-of-Apps pattern
- Progressive delivery
- Zero-trust networking
- Policy-as-code
- Automated rollback
- Production observability

---

## 💼 Resume Value

This project demonstrates hands-on experience with:

- Kubernetes platform engineering
- ArgoCD GitOps
- Istio service mesh
- Argo Rollouts
- Kyverno policy enforcement
- Prometheus-driven deployment analysis

---

## 👨‍💻 Author

**Mahesh Naganna**  
Platform & DevSecOps Engineer • Bengaluru, India
