# One AWS account, two Terraform environment stacks, and a stated monthly ceiling

The project runs in a single AWS account for now, with `infra/envs/dev` and `infra/envs/prod`
as separate Terraform roots over shared modules (`network`, `eks`, `data`, `iam`,
`observability`) and one S3 state per environment using native `use_lockfile = true` — no
DynamoDB lock table. Isolation between environments is IAM policy, naming, and separate
state rather than an account boundary, because the risk this project actually carries is data
correctness, not tenancy, and a day of Organizations/SSO/IAM scaffolding before the first
bucket exists buys nothing at M1. A second account is reconsidered at M4, when a public
service makes the boundary worth its cost, as a deliberate step rather than a prerequisite.
Cost posture is part of the decision: everything is tagged `project` and `env`, AWS Budgets
run from day one, and the ceilings are **$250/month for dev** and **$500/month for prod**.
Dev's floor after ADR-0003 (no NAT) is roughly the EKS control plane plus an ALB, a small
spot node, storage, and logs, leaving genuine headroom for recompute bursts; prod adds
CloudFront, WAF, and a larger serving pool.

## Consequences

- Raising an environment's steady-state floor past its ceiling needs a recorded decision.
  The budget's action is an **alarm to the maintainer, never automated teardown** — silently
  destroying a public service to satisfy a billing rule would be the worse failure.
- Tag-based cost allocation is what makes the ceilings meaningful; an untagged resource is
  invisible to the budget and therefore a defect.
- Because the two environments share an account, IAM boundaries are load-bearing and belong
  in review: a dev role must not be able to read or write prod buckets or assume prod roles.
- `use_lockfile` is Terraform's native S3 locking; adding a DynamoDB table is legacy and is
  not to be reintroduced.
