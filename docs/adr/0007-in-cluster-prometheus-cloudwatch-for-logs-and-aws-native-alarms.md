# Logs go to CloudWatch, SLOs run on in-cluster Prometheus and Grafana, and tracing waits for the queue path

Services log with `structlog` as JSON to stdout/stderr; a Fluent Bit **DaemonSet** ships those
logs to CloudWatch Logs, in Standard class with 7-day retention in dev (prod retention is set
when prod exists at M4, defaulting to 30 days). Metrics and dashboards run on an in-cluster
kube-prometheus-stack and Grafana that Argo CD manages ([ADR-0004](0004-terraform-owns-aws-argocd-owns-the-cluster.md)),
reachable only by port-forward or an IP-allowlisted internal ALB. Signals only AWS can raise
stay in CloudWatch: ALB, CloudFront, WAF, and Budgets metrics and alarms. The availability
alarm is built on the ALB's CloudWatch metrics, not on Prometheus, so it still fires when the
cluster, and Prometheus with it, is down. Three SLOs apply to prod from M4 and are objectives
with best-effort response, not guarantees or an on-call promise:

- **API availability:** 99.5% of requests over a rolling 30 days are not 5xx (a 3.6-hour error
  budget), measured at the ALB, the origin, so a CloudFront cache hit cannot mask an origin
  outage. 4xx responses, including the 422 and 404 of the M1 endpoint, count as good.
- **Latency:** at least 95% of point reads complete in under 500 ms at the origin over a rolling
  30 days, a 5% budget. Other endpoint classes get their own targets from the API ticket.
- **Data Freshness:** every new or revised Upstream object is Published within 24 hours of its
  publication, warning at 12 hours, with a budget of one miss per 12 upstream months. A Publish
  delayed by a Validation Gate block still counts as late.

There are no traces and no OpenTelemetry Collector until the bring-your-own-series queue path
(API, SQS, worker) exists at M4; then one Collector feeds Tempo on S3 in-cluster, one backend
with no fan-out. Until then a `request_id` in every API log line carries correlation.

## Considered options

**Amazon Managed Prometheus and Grafana.** Fees are small at this volume ($0.90 per 10M
samples ingested; $9 per editor and $5 per viewer per workspace), so cost is not what decided
it. Managed Grafana needs IAM Identity Center or SAML, ingestion needs a SigV4 remote-write
path, and under [ADR-0003](0003-serving-on-eks-and-no-nat.md) it would need an additional
interface endpoint. That is plumbing to avoid running two charts on a cluster that already
runs Argo CD.

**CloudWatch only.** ALB and CloudFront metrics cover availability, but a per-route latency
SLO needs histograms, and per-series custom metrics cost $0.30 per metric-month, so cost
grows with route and label cardinality. It also leaves nothing in-cluster for Alertmanager or
Tempo later.

**Fluent Bit as a sidecar.** A sidecar cannot read another container's stdout, so it would need
the app to write a log file, diverging from the library's `configure_logging`. In a plain
Kubernetes Job the pod does not complete unless the sidecar is a native sidecar, and a chart
that forgets it ships nothing without any error. One Fluent Bit per node also costs less than
one per pod once Dask workers are many pods.

**Traces from M1 (X-Ray or a Collector).** The API is one hop until M4 and M1 excludes OTel
([#18](https://github.com/climate-indices/climate-indices-cloud/issues/18)). X-Ray would add a
second UI next to Grafana.

## Consequences

- **Logging contract.** Every entrypoint calls the library's `configure_logging("json")` once
  and binds context at the call site; the level is the library's `CLIMATE_INDICES_LOG_LEVEL`.
  The library's configuration is one-shot and replaces the root handlers, so a second
  configurer in the service would clobber it or be clobbered. If context variables are needed
  later, that is a change to the library after 3.0.0. Pipeline lines carry `run_id` and `stage`
  (`ingest|compute|gate|publish`), plus `dataset_version` once known. The API emits one
  structured access line per request with `request_id`, `route`, `status`, and `duration_ms`,
  with uvicorn's access log off. Secrets are never logged.
- **Log guards.** A CloudWatch alarm on `IncomingBytes` at 1 GB/day per log group, about
  $15/month if sustained at $0.50/GB, emails the maintainer through SNS. It is a first guess
  to revisit once a full-CONUS recompute gives a measured volume.
- **Other AWS logs.** ALB access logs go to S3 with a 30-day lifecycle, not CloudWatch. EKS
  control-plane logs are off in dev; prod enables `audit` and `authenticator` at M4. VPC Flow
  Logs stay off until a specific need appears.
- **Freshness needs two timestamps in provenance from M1.** Freshness is measurable from the
  run's provenance without any metrics backend, provided each run records the Upstream object's
  publication time and the Publish time. M1 ingest is a manual trigger, so the SLO itself
  applies only once ingest is event-driven; the fields must exist before then.
- **Alerts and no NAT.** Alertmanager cannot reach email, Slack, or PagerDuty without egress.
  M1 alerts (the budget and the log guard) are CloudWatch alarms to an SNS email topic. From M4,
  an SNS interface endpoint lets Alertmanager's SNS receiver use the same topic. The hourly
  price of that endpoint was not verified; AWS lists $0.01 per GB processed only. There is no
  PagerDuty or Slack.
- **Third-party images and plugins.** Without NAT, Prometheus, Grafana, and Fluent Bit images
  must come through an ECR pull-through cache, which the spec verifies per upstream registry.
  Grafana runs with built-in datasources only, since plugins cannot be downloaded at runtime.
- **Prometheus durability.** It is a single instance with 30-day local retention and no HA or
  long-term store. A lost volume loses metric history, not alerts, because the availability
  alarm lives in CloudWatch.
