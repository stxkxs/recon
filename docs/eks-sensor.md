# recond as an in-cluster sensor (design)

> Status: design / not yet built. This captures the repositioning of recond
> from an external CLI into a node-resident reconnaissance sensor for
> Kubernetes/EKS. Today recond runs once and exits; the sensor is a
> longer-running deployment that reuses the same scan modules.

## Positioning

`cloudgov` governs from the **control-plane side** — IAM, cost, drift,
compliance: *"is the configuration correct?"* recond, run inside the cluster,
is the **data-plane complement**: *"what is actually reachable and exposed
right now, from where a compromised pod would stand?"* The two are halves of
the same posture story — cloudgov says *the node role is too broad*; recond
says *and a pod can actually reach it*.

The pivot is conceptual, not a rewrite: recond's modules already take a target,
gather security-relevant signal, and score it. In a cluster every node, pod,
and service is a target — so the modules become introspective rather than
outward-facing.

## Topology — hybrid, not pure DaemonSet

Per-node vantage and cluster-wide sweeps have different shapes:

- **DaemonSet (per-node vantage).** Network position matters: each pod scans
  what is reachable *from its own node's network namespace* — the surface an
  attacker who popped a pod on that node would see. Used for assume-breach
  scanning, IMDS probing, and egress-control validation.
- **Singleton Deployment / CronJob (cluster-wide sweeps).** Certificate
  inventory, takeover sweeps, and external-surface diffs are global; running
  them on every node means N× redundant work and N× alert storms. One owner.

An **operator owning a `ScanPolicy` CRD** schedules both and reconciles desired
coverage — mirroring the `eks-agent-platform` operator pattern.

## Scan strategies

1. **Assume-breach vantage scanning.** From each node, scan neighbor pod IPs
   and ClusterIP services with the `ports`/`http`/`tech`/`cors` modules. Alert
   on the *per-node differential* — surface reachable from node A but not node
   B signals a NetworkPolicy gap. Continuous lateral-movement surface mapping.
2. **IMDS credential-theft canary** (highest value, EKS-specific). Point the
   `http` module at `169.254.169.254` from inside each pod. If a pod can reach
   IMDS and pull node-role credentials (hop-limit not enforced, IMDSv2 not
   required) → always high severity. The #1 pod→node→AWS escalation path.
3. **Inside-out vs outside-in surface diff.** Scan the cluster's Ingress/LB
   hostnames externally, map the *intended* surface from in-cluster
   Ingress/Service specs (or `eks-gitops`), and diff. Anything externally
   reachable but undeclared in Git → shadow-exposure alert.
4. **ExternalDNS dangling-takeover sweep.** Use `takeover`+`crt`+`dns` against
   the cluster's own managed zones — deleting an Ingress can orphan a Route53
   record pointing at a recycled ELB/CloudFront.
5. **Live software-BOM / rogue-workload detection.** `favicon`+`tech`+
   `jsanalysis` fingerprint what is actually serving on each pod; diff against
   admitted images / desired state. Catches exposed datastores, unexpected
   admin UIs, and JS bundles leaking secrets.
6. **TLS/cert posture mesh.** `ssl`+`dnssec`+`crt` sweep Ingress and endpoint
   certificates. Low = expiring soon, medium = near expiry or weak cipher,
   high = expired or self-signed where a CA is expected.
7. **Egress-control validation.** From each node, attempt the lookups that
   require egress (external DNS, HTTP to a sinkhole, the API-backed modules).
   A pod that should be egress-locked reaching the internet → medium/high.
   Validates that NetworkPolicy / Cilium actually works, not just that it is
   declared.

## Alert mapping

The `score` module already emits an A–F grade; map F/E → high, D/C → medium,
B/A → low, with per-module overrides (IMDS-reachable is always high regardless
of aggregate score). Emit findings as Prometheus metrics
(`recond_finding{severity,module,target,node}`) → Alertmanager → existing
routes. Kubernetes Events / CRD status / EventBridge are alternative sinks.

## Runtime considerations

- recond is run-once-emit-JSON-exit Bash. The sensor needs a scheduling loop.
  Prototype: a thin loop wrapping the existing modules (fine at multi-minute
  cadence; Bash cold-starts `curl`/`dig`/`openssl` per cycle). Longer term:
  keep Bash as the scan engine, add a small controller shell (Go) for
  scheduling, the CRD, and metrics — matching the org stack.
- **The sensor is itself a target.** A workload with broad network reach,
  egress, and IMDS probing is attractive to an attacker. Tight RBAC, a
  dedicated minimal IAM role, read-only filesystem, and no secrets.

## Phased roadmap

1. Package recond as a container + Helm chart (single-scan Job).
2. Add a scheduling loop and Prometheus metric emission; ship the cert-posture
   sweep (strategy 6) as the first always-on check.
3. DaemonSet vantage scanning + IMDS canary (strategies 1, 2).
4. `ScanPolicy` CRD + operator; egress validation and surface-diff (3, 7).
5. Software-BOM and takeover sweeps (4, 5); integrate with `eks-gitops`
   desired state.
