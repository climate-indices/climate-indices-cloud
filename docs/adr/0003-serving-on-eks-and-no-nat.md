# The API is served from the compute cluster, and the VPC has no NAT gateway

E3 requires Dask on EKS with Karpenter spot pools regardless of how the API is served —
the library's block-vectorized path is what makes a full CONUS recompute economical — so
the EKS control plane's ~$73/month is already committed. Given that floor, serving the API
from the same cluster costs one small always-on spot node pool plus an ALB, while moving it
to Fargate/ECS or Lambda pays for a second runtime and pipeline to save a node EKS was
already paying for. We therefore serve FastAPI from EKS, on a Karpenter-managed node pool
**separate from the burst compute pool** so a full recompute cannot starve the public API,
and we run **no NAT gateway**: private subnets plus an S3 gateway endpoint and interface
endpoints for ECR, Secrets Manager, CloudWatch, and STS. Every input dataset this service
reads is in S3 — NOAA's open data *is* S3 — and container images carry their dependencies,
so nothing in the runtime path needs general internet egress, and the brief's own "classic
surprise" line item disappears.

## Considered options

**Lambda + API Gateway/Function URL.** Cheaper at idle than any cluster-resident service,
and rejected despite that. A Python handler importing NumPy, xarray, and zarr pays a
cold-start cost measured in seconds, and the endpoint exists to return small time series
quickly — the optimization is backwards. The near-zero floor also cannot be spent twice:
EKS's control plane is still paid for the compute side.

**Fargate/ECS for serving, EKS for compute.** Pays an ALB and a second deployment model to
save roughly one small node, while inheriting none of the Karpenter/spot integration the
compute side needs anyway.

## Consequences

- Lambda is not banned from the project; it is rejected *for this API*. A future
  request-shaped workload (an on-demand, low-frequency job) can still choose it on its own
  merits.
- The no-NAT posture is a real constraint, not an accounting trick: a compute job that
  needs a non-S3 source (Copernicus's CDS API for ERA5, or an HTTPS-only provider) requires
  general egress and must add it deliberately — a NAT gateway, a proxy, or moving that fetch
  to a CI/batch path outside the VPC — at the time that source is actually adopted. M1's
  nClimGrid ingest is pure S3 and needs none of it.
- Serving and computing share a cluster, so they share a blast radius. The separate node
  pool is the mitigation, and pod-level resource limits and PriorityClasses are what make it
  hold; the SLO work in E7 owns proving that.
- CloudFront in front of the API and site is what keeps this small; the cluster is sized for
  cache misses, not for every request.
