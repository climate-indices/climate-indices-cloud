# Dagster OSS orchestrates the pipeline by launching its stages as containers

E2 needs something that reacts to new Upstream objects, backfills 130 years, reruns a month
idempotently, and stops a Publish when the Validation Gate fails.
[ADR-0004](0004-terraform-owns-aws-argocd-owns-the-cluster.md) left the choice open on purpose
(Argo CD is delivery; a data orchestrator is decided separately), and
[#18](https://github.com/climate-indices/climate-indices-cloud/issues/18) runs M1 as plain
Kubernetes Jobs with one manual trigger. From the start of M2 the pipeline is orchestrated by
**Dagster OSS**, self-hosted on the EKS cluster and reconciled by Argo CD. Partitioned assets,
backfill policies, and blocking asset checks are first-class in Dagster and are what a
versioned, gated Publish needs; the alternatives would write them by hand. The licence is $0,
and there is no vendor control plane to reach without a NAT gateway
([ADR-0003](0003-serving-on-eks-and-no-nat.md)) or to pay for under the alarm-only ceilings of
[ADR-0005](0005-one-account-two-environments-with-a-ceiling.md).

Dagster does not measure the freshness SLO, and this decision does not rely on it to. Its
freshness policies are documented as under active development and off by default, and they
clock from the last materialization, not from the Upstream's publication.
[Data Freshness](../../CONTEXT.md) is computed from run provenance under any orchestrator.

The seam that keeps this reversible: each stage (ingest, compute, gate, publish) is a container
with a stable entrypoint, and Dagster launches it through its Kubernetes Pipes client. Stage
code never imports Dagster. What the orchestrator owns is scheduling, backfill, run history,
and the blocking check; what a stage does is unchanged from M1.

## Considered options

**Argo Workflows (runner-up).** The lightest to run for one person: no database, the same
tool family as Argo CD, YAML wrappers around the M1 Job specs, and metrics for the Prometheus
already planned ([ADR-0007](https://github.com/climate-indices/climate-indices-cloud/pull/32)).
Rejected because it has no asset, partition, or backfill model (a documented "Cron Backfill"
pattern is user-built), and its event source for SNS needs an ingress reachable from AWS. It
stays the fallback if Dagster's control plane proves too heavy.

**Airflow OSS.** Heaviest to run (scheduler, Dag processor, API server, database, and a
triggerer for event-driven work), and backfill is tied to time-based schedules, which does not
fit a calibration-window rerun.

**Amazon MWAA.** The smallest provisioned environment, micro at $0.29/h, is about $211.70/month
at 730 h: 85% of the $250 dev ceiling, and it cannot scale to zero. Its DAG delivery is an AWS
API write that ADR-0004 keeps out of CI.

**Dagster+.** Starter is $100/month plus credits, before separating dev from prod, and its
Hybrid agent needs egress to Dagster that ADR-0003 does not have; PrivateLink's plan and price
are unpublished.

**Plain Jobs plus a CronJob and an SQS poller.** Costs nothing and is M1's design. It lacks run
history, a backfill interface, and lineage, which are what Dagster is adopted for. It stays as
M1's design and as the break-glass path below.

The deciding weight is a judgement, not a measurement: for a linear pipeline of four or five
stages, Argo Workflows would be enough, and Dagster's advantage grows with the number of
indices, timescales, and calibration windows. The maintainer prefers Dagster, and the research
([#4](https://github.com/climate-indices/climate-indices-cloud/issues/4)) did not measure job
postings or find a benchmarked advantage either way.

## Consequences

- **Asset model.** Ingest is partitioned by Upstream month. Compute and publish are
  unpartitioned, one chain per Published Dataset, generated from the index configuration that
  [#23](https://github.com/climate-indices/climate-indices-cloud/issues/23) defines. A
  Calibration Window is configuration, not a partition dimension
  ([ADR-0006](0006-spi-calibrates-pearson-iii-on-a-fixed-1895-2022-window.md) already makes each
  a separate Published Dataset). The 130-year backfill is one single-run ingest backfill; the
  library recomputes the whole series per cell, so per-month compute runs would not mirror it.
- **Trigger.** An hourly sensor lists the NOAA bucket through the S3 gateway endpoint and
  compares each object's key and ETag with the last Publish manifest in S3, not only with its
  own cursor. A tick that sees changes waits for one quiet tick, then requests a single run
  keyed on the sorted set of changes, so an annual revision of about twelve months is one
  recompute and one `.r<N+1>` Publish. The wait counts against the 24 h. At M4, SNS to SQS
  replaces polling once the SQS endpoint exists for the Submission queue
  ([ADR-0008](https://github.com/climate-indices/climate-indices-cloud/pull/33)).
- **Gate.** The gate container runs as a blocking asset check on the compute asset, and the
  Publish asset is downstream of it. A breach is not retried automatically. Spot loss is
  resumed by Dagster's run monitoring.
- **Freshness and alerts.** Each Publish records the Upstream object's `LastModified` and the
  Publish time. Each sensor tick logs the age of the oldest unpublished Upstream object;
  Fluent Bit ships it to CloudWatch, a metric filter feeds alarms at 12 h and 24 h to the
  existing SNS topic, and missing data counts as breaching, so a dead orchestrator alarms too.
  Run-failure events take the same path.
- **State.** The metadata database is in-cluster Postgres on an EBS volume, treated as
  disposable: it holds run history and cursors only. S3 manifests are the system of record.
- **Placement.** The control plane (daemon, webserver, code server, Postgres) shares the API's
  spot pool at a lower PriorityClass. Pod sizes were not measured. If the requests do not fit,
  growing the pool changes ADR-0005's floor and needs a recorded decision.
- **Concurrency.** One active run per Published Dataset, and one compute run cluster-wide
  until #23 sets the pool ceilings.
- **Break-glass.** M1's manual command stays documented. The Publish stage claims
  `published/…/<YYYY-MM>.r<N>/` with an S3 conditional write, so a second writer fails instead
  of overwriting, whatever Dagster's queue says.
- **Images.** Two: the pipeline image (no Dagster dependency, validated by CI per
  [#18](https://github.com/climate-indices/climate-indices-cloud/issues/18)) and a thin
  Dagster code-location image. The code location reads the stage image digest from one value
  in the Argo CD-managed manifests, which the promotion commit updates; it is never a tag, and
  a mismatch fails closed at the gate.
- **Access.** The webserver is reached by port-forward only and is never behind CloudFront or
  a public ALB.
- **Gap in ADR-0003.** AWS's private-cluster page lists `ec2`, `eks-auth` or `oidc-eks`, and
  `elasticloadbalancing` interface endpoints that ADR-0003's list does not. EBS volumes
  depend on the EC2 API, so Postgres inherits the fix and adds no endpoint of its own. The
  fix belongs to the cluster spec, not to this decision.
- Not verified: that the OSS webserver has no built-in authentication; that the chart's
  images resolve through an ECR pull-through cache with a Docker Hub credential; S3 conditional
  write behaviour in the SDK the pipeline pins; whether NOAA's SNS topic accepts a cross-account
  SQS subscription; and that run monitoring resumes a run after a Karpenter drain. The M2 spec
  confirms each before it depends on it.
