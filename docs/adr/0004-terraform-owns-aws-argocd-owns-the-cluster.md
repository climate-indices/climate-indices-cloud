# Terraform owns the AWS APIs, Argo CD reconciles in-cluster state

Workloads reach the EKS cluster by pull, not push: Terraform is the only thing that calls
AWS APIs (cluster, node pools, IAM, buckets, DNS), and Argo CD is the only thing that writes
in-cluster state, reconciling Helm/Kustomize manifests from this repo with an app-of-apps
root. CI's job ends at building and signing an image and writing its tag back to the
repository, which is what Argo CD then observes. The boundary exists because the service
must also prove *data freshness* SLOs: an unreconciled cluster is a second, quieter source
of drift sitting directly beneath the thing being measured. Pull-based reconciliation gives
drift detection, self-heal, and a rollback that is a `git revert`.

## Considered options

**Helm rendered and applied from CI.** Fewest moving parts and nothing extra to run, but the
cluster's actual state is only knowable by querying it; hand edits and partial failures stay
invisible, and rollback is a re-run rather than a revert.

**Flux.** The same GitOps contract with a lighter controller and simpler RBAC, and no
first-party UI worth the name. A legitimate choice on preference; Argo CD's visibility was
worth more here than Flux's footprint, since explaining "what is deployed and is it what the
repo says" is part of what this project exists to demonstrate.

## Consequences

- The **orchestrator decision for E2 is deliberately not settled by this one.** Argo CD is
  delivery, Argo Workflows would be data orchestration; choosing one must not drag the
  other in. They are decided separately, on their own merits.
- Anything that must exist *before* Argo CD can reconcile — the cluster, the controller's own
  IRSA/Pod Identity role, the repository credentials — is a Terraform bootstrap concern, and
  that bootstrap is the one place where the two tools touch.
- Image promotion is a commit. An environment's running version is therefore an answerable
  question from the git history alone, which is also what the E8 telemetry needs to attribute
  a deployment to a change.
