# E2 Orchestrator: Dagster vs Airflow vs Argo Workflows

**Research ticket:** [#4](https://github.com/climate-indices/climate-indices-cloud/issues/4) (feeds the decision ticket [#27](https://github.com/climate-indices/climate-indices-cloud/issues/27); no ADR is written here)
**Date:** 2026-09-24. Every web page and price list cited below was read on this date. Versions are from PyPI and GitHub release APIs read the same day.

Legend: a claim with a link is verified against the owning source. "(analysis)" marks my inference from verified facts. Anything unverified is in "Gaps Requiring Manual Verification".

## Summary

- **Recommendation: Dagster OSS, self-hosted on the EKS cluster and delivered by Argo CD, adopted at the start of M2 (after M1's plain Jobs).** Keep each pipeline stage a container with a stable entrypoint so the orchestrator only launches it (analysis). Do not buy Dagster+ (Starter is $100/month against a $250 dev ceiling, and the hosted control plane needs egress or an unpriced PrivateLink). Do not use provisioned MWAA (the smallest environment, micro at $0.29/h, is about $211.70/month at 730 h, 85% of the dev ceiling, and it cannot scale to zero).
- **Freshness policy is not the discriminator.** Dagster freshness policies are "under active development" and off by default; Airflow Deadline Alerts are "experimental"; Argo Workflows has no freshness concept. None of the three measures "Published within 24 h of the Upstream's publication" natively, because each clocks from its own run or materialization. The SLO must be computed from the two provenance timestamps regardless (analysis). What separates them is backfill, the asset/partition model, blocking checks for the Publish gate, and the running footprint.
- **Strongest counter-argument:** Argo Workflows (or M1's Jobs plus a CronJob and an SQS poller) is lighter to run for one person, needs no database, and is enough if scope stays at a few linear stages; Dagster's asset graph only pays off as the index x timescale x calibration-window count grows.
- **Independent of orchestrator:** event-driven ingest needs SNS -> SQS -> in-cluster consumer, and ADR-0003's endpoint list has no SQS endpoint ($0.01 per endpoint-hour, about $7.30/month per AZ). Argo Events' SNS source needs an ingress reachable from AWS, which a private cluster lacks.
- **Market signal in job postings was not measured** (see Section 8). The brief's "Airflow appears in more job postings" is an unverified assumption.

## Comparison Table

Prices are us-east-1, read 2026-09-24 (MWAA and VPC from the AWS Price List API, files published 2026-09-11 and 2026-09-17). Monthly figures use 730 h/month, my assumption.

| Criterion | Dagster (OSS; Dagster+) | Airflow (OSS Helm; MWAA; MWAA Serverless) | Argo Workflows (+ Argo Events) | Baseline: M1 plain Jobs (+ CronJob) |
|---|---|---|---|---|
| Runs on EKS | Helm chart; always-on: daemon, webserver, user-code server, PostgreSQL; one K8s Job per run by default ([deploy guide](https://docs.dagster.io/deployment/oss/deployment-options/kubernetes/deploying-to-kubernetes), [chart values](https://raw.githubusercontent.com/dagster-io/dagster/master/helm/dagster/values.yaml)) | Official chart 1.22.0, needs K8s >= 1.30.13; scheduler, Dag processor, API server, Postgres/MySQL; triggerer for deferred work ([chart](https://airflow.apache.org/docs/helm-chart/stable/index.html), [architecture](https://airflow.apache.org/docs/apache-airflow/stable/core-concepts/overview.html)) | CRD controller, cluster or namespace install; no database needed; optional Postgres/MySQL archive ([install](https://argo-workflows.readthedocs.io/en/stable/installation/), [archive](https://argo-workflows.readthedocs.io/en/stable/workflow-archive/)); Argo Events adds NATS EventBus (JetStream example: 3-replica StatefulSet) + EventSource + Sensor ([EventBus](https://argoproj.github.io/argo-events/eventbus/jetstream/)) | Only the Jobs |
| Managed option and cost | Dagster+ Solo $10/mo + $0.040/credit (1 user, 1 code location, 1 deployment); Starter $100/mo + $0.035/credit (3 users, 5 code locations, 1 deployment); Pro/Enterprise "Contact Sales"; Hybrid "no compute charge"; credit = one materialization or op executed ([pricing](https://dagster.io/pricing)) | MWAA micro $0.29/h (~$211.70/mo), small $0.49/h (~$357.70/mo), no minimum fee but billed while the environment exists; MWAA Serverless $0.08/h per AWS-managed task ([price list](https://pricing.us-east-1.amazonaws.com/offers/v1.0/aws/AmazonMWAA/current/us-east-1/index.json), [pricing page](https://aws.amazon.com/managed-workflows-for-apache-airflow/pricing/)) | None for Workflows: AWS's EKS Capabilities list managed Argo CD, ACK and kro only ([capabilities](https://docs.aws.amazon.com/eks/latest/userguide/capabilities.html)) | $0 |
| Fits ADR-0003 (no NAT) | OSS: no control-plane egress; chart images default to `docker.io` ([values](https://raw.githubusercontent.com/dagster-io/dagster/master/helm/dagster/values.yaml)). Hybrid: agent is outbound-only to Dagster+; AWS PrivateLink documented for the API; code snapshots and compute logs go to Dagster-managed S3 ([architecture](https://docs.dagster.io/deployment/dagster-plus/hybrid/architecture)) | OSS: no control-plane egress. MWAA private routing needs endpoints for S3, CloudWatch logs and monitoring, SQS, KMS; private web server needs Python deps as wheels ([VPC endpoints](https://docs.aws.amazon.com/mwaa/latest/userguide/vpc-vpe-create-access.html)). Serverless: VPC optional, tasks have no internet by default ([python/bash operators](https://docs.aws.amazon.com/mwaa/latest/mwaa-serverless-userguide/operators-python-bash-detail.html)) | No external control plane. Argo Events SNS source needs "an Ingress ... so that it can be reached from AWS" ([SNS](https://argoproj.github.io/argo-events/eventsources/setup/aws-sns/)); SQS source polls a queue ([SQS](https://argoproj.github.io/argo-events/eventsources/setup/aws-sqs/)) | Needs an SQS consumer with an SQS endpoint |
| Asset / lineage model | Software-defined assets, partitions, asset checks are the core model ([partitions](https://docs.dagster.io/guides/build/partitions-and-backfills/partitioning-assets)) | Assets (3.0+) as scheduling triggers between Dags ([asset scheduling](https://airflow.apache.org/docs/apache-airflow/stable/authoring-and-scheduling/asset-scheduling.html)); Serverless: YAML workflows, no Airflow UI ([concepts](https://docs.aws.amazon.com/mwaa/latest/mwaa-serverless-userguide/mwaas-concepts.html)) | None found: a Workflow is a DAG of containers ([overview](https://argo-workflows.readthedocs.io/en/stable/)) | None |
| Freshness / SLO primitive | `FreshnessPolicy.time_window(fail_window, warn_window)` and `.cron(...)`; "under active development", off by default, not supported on source observable assets; clock is last successful materialization ([freshness](https://docs.dagster.io/guides/observe/asset-freshness-policies)) | Deadline Alerts: "new in Airflow 3.1 ... experimental"; references: queued time, logical date, fixed time, average runtime, custom ([deadline alerts](https://airflow.apache.org/docs/apache-airflow/stable/howto/deadline-alerts.html)); Serverless ignores `sla` and callbacks ([params](https://docs.aws.amazon.com/mwaa/latest/mwaa-serverless-userguide/supported-airflow-parameters.html)) | Custom Prometheus/OTLP metrics per workflow or template ([metrics](https://argo-workflows.readthedocs.io/en/stable/metrics/)); no freshness object | Provenance timestamps only (ADR-0007) |
| Publish gate that blocks | `@asset_check(blocking=True)` stops downstream materialization; default is non-blocking ([asset checks](https://docs.dagster.io/guides/test/asset-checks)) | Task dependency/failure semantics (analysis); no first-party data-check primitive read | Step failure halts the DAG branch (analysis) | Job exit code |
| Backfill | Partition-per-run by default (N partitions = N runs); `BackfillPolicy.single_run()` for ranges ([backfill](https://docs.dagster.io/guides/build/partitions-and-backfills/backfilling-data)) | `airflow backfill create`, reprocess `none`/`failed`/`completed`, `max_active_runs`; "does not make sense for Dags that don't have a time-based schedule" ([backfill](https://airflow.apache.org/docs/apache-airflow/stable/core-concepts/backfill.html)); Serverless ignores `catchup` ([params](https://docs.aws.amazon.com/mwaa/latest/mwaa-serverless-userguide/supported-airflow-parameters.html)) | No primitive; documented "Cron Backfill" pattern using `withSequence` ([cron backfill](https://argo-workflows.readthedocs.io/en/stable/cron-backfill/)) | Hand-run Jobs |
| Idempotent reruns | By convention: overwrite the partition; no versioning concept for `.r<N>` (analysis) | Documented practice: read/write a specific partition, avoid `now()`, tasks like transactions ([best practices](https://airflow.apache.org/docs/apache-airflow/stable/best-practices.html)) | Step memoization in ConfigMaps, all steps memoizable from 3.5 ([memoization](https://argo-workflows.readthedocs.io/en/stable/memoization/)); retries by policy ([retries](https://argo-workflows.readthedocs.io/en/stable/retries/)) | Entirely in pipeline code |
| Event-driven triggers | No SQS/SNS/EventBridge in the `dagster-aws` docs ([dagster-aws](https://docs.dagster.io/api/libraries/dagster-aws)); polling sensors with cursor and run keys ([sensors](https://docs.dagster.io/guides/automate/sensors)) | 3.0+ `AssetWatcher` with event triggers ([event scheduling](https://airflow.apache.org/docs/apache-airflow/stable/authoring-and-scheduling/event-scheduling.html)); SQS via `MessageQueueTrigger(scheme="sqs")` ([Amazon provider](https://airflow.apache.org/docs/apache-airflow-providers-amazon/stable/message-queues/index.html)); Serverless: cron schedule (EventBridge Scheduler) or on-demand start ([workflows](https://docs.aws.amazon.com/mwaa/latest/mwaa-serverless-userguide/workflows.html)) | Argo Events: SQS EventSource works; SNS EventSource needs public ingress | Small SQS poller |
| Dask on Kubernetes | `dagster-dask` executor runs steps on a Dask cluster ([dagster-dask](https://docs.dagster.io/api/libraries/dagster-dask)); not needed if a task starts its own cluster (analysis) | Dask executor provider last released 2023-12-17 ([PyPI](https://pypi.org/pypi/apache-airflow-providers-daskexecutor/json)) | No Dask integration found; a task or resource step can create the cluster (analysis) | LocalCluster in pod (M1) |
| Karpenter spot pools | `dagster-k8s/config` tag sets pod node selectors/affinity; `max_resume_run_attempts` resumes a run after a run-worker crash ([customizing](https://docs.dagster.io/deployment/oss/deployment-options/kubernetes/customizing-your-deployment), [run monitoring](https://docs.dagster.io/deployment/execution/run-monitoring)) | KubernetesExecutor: one pod per task, `pod_override` ([executor](https://airflow.apache.org/docs/apache-airflow-providers-cncf-kubernetes/stable/kubernetes_executor.html)) | Workflow/template `nodeSelector`, `tolerations`, `podSpecPatch` ([fields](https://argo-workflows.readthedocs.io/en/stable/fields/)); `retryPolicy` `OnFailure`/`OnError`/`OnTransientError`/`Always` ([retries](https://argo-workflows.readthedocs.io/en/stable/retries/)) | Job `backoffLimit` (analysis) |
| Terraform / IaC | Chart via Argo CD; Dagster+ provider `dagster-io/dagsterplus` 0.1.11, README "Early Development" ([README](https://github.com/dagster-io/terraform-provider-dagsterplus), [docs](https://docs.dagster.io/deployment/dagster-plus/management/terraform)) | Official chart (Argo CD needs four extra values); MWAA has an `aws_mwaa_environment` resource in the AWS provider ([docs](https://github.com/hashicorp/terraform-provider-aws/blob/main/website/docs/r/mwaa_environment.html.markdown)) | Release manifests; Helm chart is community-maintained ([install](https://argo-workflows.readthedocs.io/en/stable/installation/)) | Manifests only |
| Argo CD interaction (ADR-0004) | Chart plus user-code image tag per commit fits the image-promotion commit (analysis) | Needs `useHelmHooks: false` and `applyCustomEnv: false` on two jobs; migrations may need an Argo CD hook annotation ([chart](https://airflow.apache.org/docs/helm-chart/stable/index.html)). MWAA DAGs go to S3 ([MWAA on EKS](https://docs.aws.amazon.com/mwaa/latest/userguide/mwaa-eks-example.html)), an AWS API call outside Argo CD | Argo CD hooks "tend to be Pod, Job or Argo Workflows" ([sync waves](https://raw.githubusercontent.com/argoproj/argo-cd/stable/docs/user-guide/sync-waves.md)); "You can manage CronWorkflow resources with GitOps by using Argo CD" ([cron](https://argo-workflows.readthedocs.io/en/stable/cron-workflows/)) | Manifests already Argo CD-managed |
| Ops burden, one person | 4 always-on pods incl. a stateful DB; code-server image must track pipeline image | Highest: 4+ components incl. DB, plus chart/Argo CD caveats; MWAA removes that at the cost ceiling | Lowest without Argo Events; with it adds 5+ pods | Lowest; no run history or UI |
| Cost to adopt after M1 / M1 lock-in | Wrap Job images via Pipes K8s client or rewrite stages as assets; no lock-in of M1 Jobs | KubernetesPodOperator/executor wraps images; MWAA needs S3 DAG delivery | YAML wrappers around existing Job specs; no code change (analysis) | n/a |
| Market signal | Not measured | Not measured | Not measured | n/a |

## 1. How each runs on EKS, and what it costs

**Dagster OSS.** The [Kubernetes guide](https://docs.dagster.io/deployment/oss/deployment-options/kubernetes/deploying-to-kubernetes) lists the daemon, webserver, user-code location server and a PostgreSQL container as the running pods, with runs launched as ephemeral Kubernetes Jobs. The [chart values](https://raw.githubusercontent.com/dagster-io/dagster/master/helm/dagster/values.yaml) confirm `runLauncher.type: K8sRunLauncher` as default and a bundled `library/postgres`; the [customization guide](https://docs.dagster.io/deployment/oss/deployment-options/kubernetes/customizing-your-deployment) says "in a real deployment, users will likely want to set up an external PostgreSQL database". The daemon is required for schedules, sensors and run queueing ([daemon](https://docs.dagster.io/deployment/execution/dagster-daemon)). Latest release 1.13.24 (2026-09-21, [PyPI](https://pypi.org/pypi/dagster/json)). License cost is $0; the cost is pods and a database (not priced in this pass, see Gaps).

**Dagster+ Hybrid.** Backend services (UI, GraphQL API, metadata DB, daemons) run at Dagster; an agent in your cluster "polls Dagster+'s API servers for new work" ([architecture](https://docs.dagster.io/deployment/dagster-plus/hybrid/architecture)). Published prices ([pricing page](https://dagster.io/pricing), "Updated Solo and Starter pricing takes effect May 1, 2026"): Solo $10/month plus $0.040/credit; Starter $100/month plus $0.035/credit; Pro and Enterprise "Contact Sales"; "If you use Hybrid, there is no compute charge"; the page states no nonprofit discount ("We do not currently offer a self-enrollment discount for not-for-profit organizations"). Solo and Starter both list "1 Deployment", so dev and prod would share one deployment (as code locations) or need the unpriced Pro tier (analysis). Illustrative credit arithmetic at the Starter rate, with my assumed volumes: monthly ingest about 5 materializations = $0.18; a daily fire pipeline of 5 assets x 30 days = 150 credits = $5.25; a naive backfill of 1,560 monthly partitions x 4 assets = 6,240 credits = $218 one time, if each partition materialization counts as a credit (the page does not say; see Gaps). Starter is 40% of the dev ceiling before credits.

**Airflow OSS.** The [official chart](https://airflow.apache.org/docs/helm-chart/stable/index.html) (1.22.0, released 2026-06-13, [GitHub releases](https://github.com/apache/airflow/releases)) requires Kubernetes v1.30.13+ and Helm v3.19.0+ and supports Postgres or MySQL. Required components are the scheduler, a Dag processor, an API server and the metadata database; a triggerer is needed for deferred tasks ([architecture](https://airflow.apache.org/docs/apache-airflow/stable/core-concepts/overview.html)), and event-driven `AssetWatcher` triggers run there (analysis). Latest release 3.3.2 (2026-09-17, [PyPI](https://pypi.org/pypi/apache-airflow/json)).

**MWAA (provisioned).** From the [AWS Price List API](https://pricing.us-east-1.amazonaws.com/offers/v1.0/aws/AmazonMWAA/current/us-east-1/index.json) (published 2026-09-11): micro $0.29/h, small $0.49/h, medium $0.74/h, large $0.99/h, metadata storage $0.10 per GB-month. At 730 h: micro $211.70, small $357.70. The [pricing page](https://aws.amazon.com/managed-workflows-for-apache-airflow/pricing/) says you pay "for the time your Airflow Environment runs", so there is no scale to zero. One micro environment is 85% of the $250 dev ceiling. A prod environment of the same class would take $211.70 of the $500 prod ceiling, leaving $288.30 for the EKS control plane (about $73 per the brief), serving, storage and compute, and dev plus prod together are $423.40 before extra workers, storage and endpoints (analysis). Supported versions: 3.3.1, 3.2.1, 3.0.6, 2.11.2, 2.11.0 ([versions](https://docs.aws.amazon.com/mwaa/latest/userguide/airflow-versions.html)).

**MWAA Serverless.** Pay for task run time: $0.08/h per AWS-managed task, billed at one-second resolution with a one-minute minimum ([pricing page](https://aws.amazon.com/managed-workflows-for-apache-airflow/pricing/)); "no minimum provisioning" ([what is](https://docs.aws.amazon.com/mwaa/latest/mwaa-serverless-userguide/what-is-mwaa-serverless.html)). It supports `EksPodOperator` and `SqsSensor` ([operators](https://docs.aws.amazon.com/mwaa/latest/mwaa-serverless-userguide/operators.html)). Limits from the docs: no Airflow web UI ([concepts](https://docs.aws.amazon.com/mwaa/latest/mwaa-serverless-userguide/mwaas-concepts.html)), `schedule` must be cron, `retries` 0 to 3, and `catchup`, `sla` and all callbacks are ignored ([parameters](https://docs.aws.amazon.com/mwaa/latest/mwaa-serverless-userguide/supported-airflow-parameters.html)). Illustrative cost if a pod-waiting task bills for its whole runtime: 18 task-hours/month (3 h monthly stages + 30 x 0.5 h daily) = $1.44 (my assumed durations). It is cheap, but it drops backfill and the UI.

**Argo Workflows.** Container-native engine implemented as a Kubernetes CRD ([docs](https://argo-workflows.readthedocs.io/en/stable/)); cluster, namespace and managed-namespace installs ([install](https://argo-workflows.readthedocs.io/en/stable/installation/)). The workflow archive is optional: "If you want to keep completed workflows for a long time, you can use the workflow archive to save them in a Postgres (>=9.4) or MySQL (>= 5.7.8) database"; pod logs are not archived ([archive](https://argo-workflows.readthedocs.io/en/stable/workflow-archive/)). Latest releases v4.1.4 and v4.0.12 (2026-09-18, [GitHub releases](https://github.com/argoproj/argo-workflows/releases)). Argo Events (v1.9.11, 2026-07-13, [releases](https://github.com/argoproj/argo-events/releases)) requires an EventBus per namespace, backed by NATS ([EventBus](https://argoproj.github.io/argo-events/eventbus/eventbus/)); the simplest JetStream example is a 3-replica StatefulSet ([JetStream](https://argoproj.github.io/argo-events/eventbus/jetstream/)).

**Ceilings summary** (always-on, us-east-1, 730 h, analysis):

| Option | Verified always-on cost | vs $250 dev | vs $500 prod |
|---|---|---|---|
| MWAA micro, one environment | $211.70 | 85% | 42% |
| Dagster+ Starter + credits | $100 + credits | 40% | 20% |
| MWAA Serverless | about $1.44 (assumed) | <1% | <1% |
| Dagster / Airflow / Argo Workflows self-hosted | $0 licence; pod and DB cost unquantified | node share | node share |

## 2. Assets, lineage, freshness and the data SLOs

**The SLO to express** (ADR-0007, ticket #27): every new or revised Upstream object is Published within 24 h of its publication, warning at 12 h, and a Publish delayed by a Validation Gate block counts as late. The clock starts at the Upstream's publication, not at our run.

**Dagster.** [Freshness policies](https://docs.dagster.io/guides/observe/asset-freshness-policies): `time_window(fail_window=24h, warn_window=12h)` matches the numbers, but the docs define it as a successful materialization of the asset at least every 24 hours for the asset to be considered fresh, so the reference clock is the last materialization. For a monthly Upstream that policy would fail for about 29 days of each month, and `cron` policies need a known deadline while nClimGrid latency is 1 to 2 weeks and undocumented ([nClimGrid report](https://github.com/climate-indices/climate-indices-cloud/blob/research/nclimgrid-aws/docs/research/nclimgrid-aws.md)) (analysis). The page states policies are "not currently supported for source observable assets", the natural place to record an Upstream timestamp. They are disabled by default (`freshness: enabled: True` in `dagster.yaml`) and "under active development ... APIs may change". They superseded freshness checks in 1.12, which "will continue to be supported". Strength: blocking [asset checks](https://docs.dagster.io/guides/test/asset-checks) express the Publish gate: by default a failed check does not stop the run, and `blocking=True` keeps downstream assets from materializing. The asset graph gives lineage.

**Airflow.** [Deadline Alerts](https://airflow.apache.org/docs/apache-airflow/stable/howto/deadline-alerts.html) can fire a callback when a Dag run misses a deadline from a reference; the docs allow "any custom method that returns a timestamp", so an Upstream-publication reference is plausible (analysis), but the feature is "new in Airflow 3.1 and should be considered experimental". Deadline alerts are per-run notifications, not a persisted freshness state. Assets exist for scheduling between Dags; I read no asset-level freshness object.

**Argo Workflows.** No asset or freshness concept. Custom metrics ("Counter, gauge and histogram") can be emitted per workflow or template and scraped by Prometheus or sent over OTLP ([metrics](https://argo-workflows.readthedocs.io/en/stable/metrics/)), which fits ADR-0007's in-cluster Prometheus (analysis). Kubernetes events "can be lost or rolled-up" and must not drive automation ([workflow events](https://argo-workflows.readthedocs.io/en/stable/workflow-events/)).

**Bottom line (analysis).** Under any candidate, Data Freshness = Publish time minus Upstream publication time computed from provenance (ADR-0007 amendment on #27), exported as a metric or an asset check. The orchestrator's job is to expose both timestamps and keep its own scheduling delay small against 24 h.

## 3. Backfill and idempotency

- **Dagster.** Backfills create one run per partition unless a `single_run` policy is set; single-run backfills "only work if they are launched from the asset graph or asset page, or if the assets are part of an asset job that shares the same backfill policy" ([backfill](https://docs.dagster.io/guides/build/partitions-and-backfills/backfilling-data)). Partition types include time-window, static, multi-dimensional and dynamic ([partitioning](https://docs.dagster.io/guides/build/partitions-and-backfills/partitioning-assets)). A calibration window (ADR-0006: a different Published Dataset) maps to a static partition dimension or plain config (analysis). The library recomputes the whole 1895-2022 series per cell (ADR-0001), so monthly partitions per stage would not mirror the compute and would inflate Dagster+ credits (analysis).
- **Airflow.** Backfill has three reprocess modes and `max_active_runs`, and a 3.3 partitioned-Dag mode ([backfill](https://airflow.apache.org/docs/apache-airflow/stable/core-concepts/backfill.html)). It "does not make sense for Dags that don't have a time-based schedule", so an SQS/asset-triggered ingest Dag has no native backfill; a calibration-window rerun would be a manual trigger with `dag_run.conf` (analysis). The docs advise reading and writing a specific partition and never "the latest available data" ([best practices](https://airflow.apache.org/docs/apache-airflow/stable/best-practices.html)), which matches the versioned Published Dataset rule.
- **Argo Workflows.** No backfill feature; the [Cron Backfill](https://argo-workflows.readthedocs.io/en/stable/cron-backfill/) page shows a user-built backfill workflow with `withSequence`. A CronWorkflow with `startingDeadlineSeconds` runs a single missed schedule after a controller crash ([cron](https://argo-workflows.readthedocs.io/en/stable/cron-workflows/)). Mutexes and semaphores limit concurrent executions of workflows or templates ([synchronization](https://argo-workflows.readthedocs.io/en/stable/synchronization/)), which would serve a one-at-a-time Publish (analysis). Memoization stores results in ConfigMaps ([memoization](https://argo-workflows.readthedocs.io/en/stable/memoization/)), useful for pure steps only.
- **All (analysis).** `.r<N+1>` versioning (ADR-0006, CONTEXT.md **Dataset Version**) and the Publish gate live in pipeline code; no candidate implements them. A re-Publish is a new version, so Dagster's overwrite-the-partition convention and Airflow's partition-write advice both need a version-aware writer.

## 4. Event-driven triggers

**Source.** The nClimGrid SNS topic `arn:aws:sns:us-east-1:123901341784:NewNClimGridMonthlyObject` comes from the repo's [nClimGrid report](https://github.com/climate-indices/climate-indices-cloud/blob/research/nclimgrid-aws/docs/research/nclimgrid-aws.md) (owner: [AWS Open Data registry](https://registry.opendata.aws/noaa-nclimgrid/), not re-read here). Bucket-level S3 events and EventBridge for that bucket belong to NOAA, so SNS is the only channel (analysis).

**Network consequence (analysis, applies to every option).** A pod cannot receive an SNS HTTP push without a public ingress, and ADR-0003's endpoint list (S3, ECR, Secrets Manager, CloudWatch, STS) has no SQS endpoint. The workable path is SNS -> SQS (subscription permission not verified, see Gaps) -> in-cluster poller, plus an SQS interface endpoint: $0.01 per endpoint-hour and $0.01 per GB processed ([AWS Price List, VPC](https://pricing.us-east-1.amazonaws.com/offers/v1.0/aws/AmazonVPC/current/us-east-1/index.json), [PrivateLink pricing](https://aws.amazon.com/privatelink/pricing/)), which is $7.30/month per AZ, $14.60 for two AZs. ADR-0007 recorded the hourly endpoint price as unverified; this is it.

- **Dagster:** sensors run in the daemon, poll at `minimum_interval_seconds`, use cursors and run keys to avoid duplicates, and events can also be pushed through the GraphQL API ([sensors](https://docs.dagster.io/guides/automate/sensors)). The `dagster-aws` reference lists Athena, CloudWatch, EMR, Glue, Lambda, Redshift, S3, Secrets Manager, SSM, ECS and Pipes, with no SQS, SNS or EventBridge ([dagster-aws](https://docs.dagster.io/api/libraries/dagster-aws)), so an SQS sensor is hand-written (analysis).
- **Airflow:** first-class. `AssetWatcher` plus an event trigger schedules a Dag on external events ([event scheduling](https://airflow.apache.org/docs/apache-airflow/stable/authoring-and-scheduling/event-scheduling.html)), and the Amazon provider ships an SQS queue provider ([provider](https://airflow.apache.org/docs/apache-airflow-providers-amazon/stable/message-queues/index.html)). MWAA private routing already requires an SQS endpoint because MWAA uses SQS internally ([VPC endpoints](https://docs.aws.amazon.com/mwaa/latest/userguide/vpc-vpe-create-access.html)).
- **Argo Workflows:** needs Argo Events. The SQS EventSource "listens to messages on AWS SQS queue"; the SNS EventSource needs "an Ingress or OpenShift Route ... so that it can be reached from AWS" ([SNS](https://argoproj.github.io/argo-events/eventsources/setup/aws-sns/)). Cost: EventBus (NATS) plus EventSource and Sensor pods.

## 5. Dask on Kubernetes and Karpenter spot pools

- **Dask operator.** `dask-kubernetes` 2026.3.0 (2026-03-02, [PyPI](https://pypi.org/pypi/dask-kubernetes/json)) provides the operator; `KubeCluster` deploys clusters via custom resources and is "designed to dynamically launch ad-hoc deployments" ([docs](https://kubernetes.dask.org/en/latest/)). M1 runs a `LocalCluster` inside the pod (#18). None of the three needs a first-party Dask integration: a task pod can start its own cluster (analysis). `dagster-dask` (0.29.24) is an executor that runs steps on a Dask cluster ([API](https://docs.dagster.io/api/libraries/dagster-dask)), a different model from Dask arrays inside one step; Airflow's Dask executor provider was last released 2023-12-17.
- **Karpenter.** Spot interruptions give a two-minute notice; Karpenter drains and starts a replacement; `karpenter.sh/do-not-disrupt` blocks voluntary disruption; consolidation defaults to `WhenEmptyOrUnderutilized` with `consolidateAfter: 0s` ([disruption](https://karpenter.sh/docs/concepts/disruption/), v1.14.1 released 2026-08-21, [releases](https://github.com/aws/karpenter-provider-aws/releases)). All three place pods with ordinary pod spec fields; the differences are retry and resume:
  - Dagster: `dagster-k8s/config` carries `pod_spec_config` and `job_spec_config`; with the `k8s_job_executor`, step pods take `step_k8s_config` instead ([customizing](https://docs.dagster.io/deployment/oss/deployment-options/kubernetes/customizing-your-deployment)); run monitoring can resume a run after a run-worker crash detected as a failed K8s Job, "only works when using a run launcher other than the DefaultRunLauncher" ([run monitoring](https://docs.dagster.io/deployment/execution/run-monitoring)).
  - Airflow: each task in its own pod, with `pod_override` and a documented "Handling Worker Pod Crashes" section; without remote logging "logs will be lost after the worker pods shut down" ([executor](https://airflow.apache.org/docs/apache-airflow-providers-cncf-kubernetes/stable/kubernetes_executor.html)).
  - Argo Workflows: `retryPolicy` values `Always`, `OnFailure` (default), `OnError` (controller errors or failed init/wait containers), `OnTransientError` ([retries](https://argo-workflows.readthedocs.io/en/stable/retries/)). Which of these a spot drain triggers was not verified.

## 6. Terraform and IaC maturity

ADR-0004: Terraform owns AWS APIs, Argo CD owns in-cluster state. Self-hosted Dagster, Airflow and Argo Workflows are all Helm or manifest deployments, so they land on the Argo CD side; the AWS-side needs are pod identity roles and (optionally) an RDS instance.

- **Dagster+:** provider `dagster-io/dagsterplus` 0.1.11, published 2026-08-13 ([registry API](https://registry.terraform.io/v1/providers/dagster-io/dagsterplus)); repo description "[WIP]", README "Early Development" ([repo](https://github.com/dagster-io/terraform-provider-dagsterplus)); docs label it "Early access preview" ([docs](https://docs.dagster.io/deployment/dagster-plus/management/terraform)).
- **MWAA:** the AWS provider has an `aws_mwaa_environment` resource (arguments include `dag_s3_path` and `source_bucket_arn`; [docs](https://github.com/hashicorp/terraform-provider-aws/blob/main/website/docs/r/mwaa_environment.html.markdown); provider 6.66.0, [registry API](https://registry.terraform.io/v1/providers/hashicorp/aws)). DAGs and `kube_config.yaml` are delivered to S3 ([MWAA on EKS](https://docs.aws.amazon.com/mwaa/latest/userguide/mwaa-eks-example.html)) and the environment needs an EKS access entry for its execution role, so CI would write to S3 (an AWS API call by CI, against ADR-0004's "CI's job ends at building and signing an image") (analysis). MWAA Serverless workflows are created with `aws mwaa-serverless create-workflow` after uploading YAML to S3 ([workflows](https://docs.aws.amazon.com/mwaa/latest/mwaa-serverless-userguide/workflows.html)).
- **Airflow chart under Argo CD:** must set `createUserJob.useHelmHooks: false`, `createUserJob.applyCustomEnv: false`, `migrateDatabaseJob.useHelmHooks: false`, `migrateDatabaseJob.applyCustomEnv: false` "or your application will not start as the migrations will not be run"; migrations may need `argocd.argoproj.io/hook: Sync` ([chart](https://airflow.apache.org/docs/helm-chart/stable/index.html)). Argo CD maps `helm.sh/hook` `pre-install` and `pre-upgrade` to `PreSync` ([Argo CD Helm](https://argo-cd.readthedocs.io/en/stable/user-guide/helm/)).
- **Argo Workflows:** official release manifests; the Helm chart is "community maintained" ([install](https://argo-workflows.readthedocs.io/en/stable/installation/)).

**Images without NAT (ADR-0007 assigns the check to the spec).** ECR pull-through cache supports Amazon ECR Public, the Kubernetes registry and Quay without credentials, and Docker Hub, Azure, GitHub, GitLab and Chainguard registries with credentials in a Secrets Manager secret named with the `ecr-pullthroughcache/` prefix ([ECR](https://docs.aws.amazon.com/AmazonECR/latest/userguide/pull-through-cache.md)). The Dagster chart's default images are on Docker Hub (`docker.io/dagster/...`, `library/postgres`), so they need that credential; Secrets Manager is already on ADR-0003's endpoint list. Default image registries for Airflow and Argo Workflows were not read.

## 7. Operational burden for one operator

Verified footprint (always-on): Dagster four pods including PostgreSQL; Airflow scheduler, Dag processor, API server, metadata DB, plus triggerer for events; Argo Workflows the controller alone, plus EventBus, EventSource and Sensor for events. Pod resource sizes were not read (see Gaps). Failure visibility (ticket #27's "fails silently"):

- Dagster: run start and max-runtime timeouts, crash detection and resume are built in ([run monitoring](https://docs.dagster.io/deployment/execution/run-monitoring)); freshness alerts are documented under Dagster+ alerts (OSS availability not verified).
- Airflow: Deadline Alerts (experimental); alert callbacks such as Slack need egress, which ADR-0007 also notes for Alertmanager (an SNS endpoint from M4).
- Argo Workflows: custom Prometheus metrics; alerting is Prometheus rules on the in-cluster stack (ADR-0007) (analysis).
- Every orchestrator UI adds another internal endpoint under ADR-0007's port-forward or IP-allowlisted internal ALB rule (analysis). Dagster+ Hybrid uploads compute logs to Dagster by default ([architecture](https://docs.dagster.io/deployment/dagster-plus/hybrid/architecture)); the log path for the self-hosted options is Fluent Bit per ADR-0007.

Ordering (analysis): Argo Workflows without Argo Events is lightest; Dagster OSS is medium; Airflow OSS is heaviest; MWAA removes the cluster burden but breaks the cost ceiling; MWAA Serverless is the least to operate but drops the UI and backfill.

## 8. Market signal in job postings

Not measured. No first-party source for posting counts exists that I could fetch reliably, and I did not scrape job boards. I make no ranking claim. The capstone brief asserts "Airflow: appears in more job postings"; treat it as the maintainer's assumption. Any weighting of this criterion should be done by the maintainer from live searches, dated.

## 9. M1 interplay and cost to adopt later

M1 is plain Kubernetes Jobs with a manual trigger, no orchestrator and no OTel ([#18](https://github.com/climate-indices/climate-indices-cloud/issues/18), ADR-0007). None of the candidates locks the M1 Jobs in (analysis): Dagster has a Pipes client "for launching kubernetes pods" ([dagster-k8s](https://docs.dagster.io/api/libraries/dagster-k8s)); Airflow's KubernetesExecutor and pod operators run images; an Argo Workflows step is a container template. The design choice that keeps every option open is the same: each stage is a container whose parameters are env or args, whose result is an exit code, and whose provenance record (including Upstream publication time and Publish time, per the #18 amendment) is written to S3, so the orchestrator only launches and observes.

Adoption cost, ordered lightest to heaviest (analysis): Argo Workflows (YAML wrappers, no DB) < Dagster (asset definitions plus Helm, code-server image) < Airflow OSS (chart plus DB plus Dag delivery) < MWAA (S3 delivery outside ADR-0004, plus cost).

## 10. Fourth option

- **Plain Jobs plus a CronJob and a small SQS poller (defer the orchestrator).** Justified as an explicit baseline: it is the M1 design already accepted in #18, it costs nothing, and the freshness SLO needs provenance timestamps regardless. It lacks run history, a backfill UI and lineage, which is what the orchestrator would buy. Included in the table for that reason.
- **Prefect and AWS Step Functions with EventBridge Pipes:** not evaluated; I gathered no evidence that either beats the three on any criterion, so I do not include them (see Gaps).

## Recommendation

**Adopt Dagster OSS, self-hosted on the EKS cluster and reconciled by Argo CD, at the start of M2. Run M1 exactly as #18 defines it.** Reasons, all from the tables above:

1. **Cost.** $0 licence against MWAA micro at $211.70/month (85% of the dev ceiling) and Dagster+ Starter at $100/month plus credits. ADR-0005's alarm-only ceilings make a fixed vendor line item the dominant risk.
2. **Fit to the workload.** Partitions, backfill policies, blocking asset checks for the Validation Gate, and an asset graph over index x timescale x calibration window are first-class. The per-index Publish gate and evidence-class reporting map onto asset checks and metadata (analysis).
3. **No-NAT posture.** Self-hosted has no control-plane egress; Dagster+ needs PrivateLink whose plan and price are not published.
4. **Kubernetes-native execution.** One Job per run on the Karpenter pools, `dagster-k8s/config` for scheduling, and resume-after-crash for spot loss.

Conditions: (a) compute the freshness SLO from provenance and export it to the ADR-0007 Prometheus, using Dagster freshness policies only as a secondary signal until they leave preview; (b) SQS consumption is hand-written and needs the SQS endpoint, whatever the orchestrator; (c) keep stages as container entrypoints so the choice stays reversible; (d) size Postgres and pods before M2 so the always-on set fits the existing node pools.

**Runner-up:** Argo Workflows without Argo Events, if the scope stays linear. **Not recommended:** provisioned MWAA (ceiling), Dagster+ (cost and egress unknowns), Airflow OSS (heaviest to run, backfill tied to time-based schedules).

**Strongest counter-argument, stated fairly.** For one person, a $250 dev ceiling and a pipeline of four or five linear stages, Dagster adds a stateful control plane (daemon, webserver, code server, Postgres) that must be patched, backed up and kept in step with the pipeline image. Its headline advantage, freshness policy, is in preview and cannot express the actual SLO, so the SLO code is written by hand anyway. Argo Workflows needs no database, is the same tool family and GitOps habit as Argo CD, wraps existing Job specs without code changes, and exposes metrics to the Prometheus already planned. The asset model pays off mostly at M2 and later, when index, timescale and calibration-window combinations multiply; if M2 stays small, M1's Jobs plus Argo Workflows may be all this service ever needs. The rebuttal is that the backfill, versioned re-Publish and blocking-gate semantics are the things that would otherwise be written by hand in YAML, and the portfolio goal favours a data-orchestrator narrative. That is a judgment, not a measured fact, and it is the maintainer's call in #27.

## Open Questions

1. Will M2 stay at SPI/SPEI/EDDI on a handful of assets, or grow to a full index x timescale x calibration-window matrix? This decides whether asset lineage earns its footprint.
2. Is a vendor control plane acceptable for a public nonprofit service at all, or is self-hosting a requirement? This removes Dagster+ and MWAA Serverless from consideration.
3. Do the always-on control-plane pods share the API's small spot pool, or need a separate system pool (which changes the ADR-0005 floor)?
4. Approve the SQS interface endpoint (about $14.60/month for two AZs) for SNS -> SQS ingest, or accept a poll-based design for M2?
5. Where does the freshness SLO get computed: orchestrator, Prometheus, or both? ADR-0007 suggests provenance plus Prometheus.
6. Is the calibration window an orchestrator partition dimension or pipeline config (ADR-0006 makes it a distinct Published Dataset)?
7. What does the maintainer's own dated job-posting search show?

## Sources Consulted

Project ground truth (worktree and repository): `AGENTS.md`, `CONTEXT.md`, `docs/capstone/brief.md`, `docs/adr/0001` to `0006`; ADR-0007 from PR #32 (`origin/docs/observability-slo`); issues [#1](https://github.com/climate-indices/climate-indices-cloud/issues/1), [#18](https://github.com/climate-indices/climate-indices-cloud/issues/18), [#27](https://github.com/climate-indices/climate-indices-cloud/issues/27); [nClimGrid report](https://github.com/climate-indices/climate-indices-cloud/blob/research/nclimgrid-aws/docs/research/nclimgrid-aws.md).

Dagster
- https://dagster.io/pricing
- https://docs.dagster.io/deployment/oss/deployment-options/kubernetes/deploying-to-kubernetes
- https://docs.dagster.io/deployment/oss/deployment-options/kubernetes/customizing-your-deployment
- https://raw.githubusercontent.com/dagster-io/dagster/master/helm/dagster/values.yaml
- https://docs.dagster.io/deployment/dagster-plus/hybrid/architecture
- https://docs.dagster.io/deployment/dagster-plus/hybrid/kubernetes/setup
- https://docs.dagster.io/guides/observe/asset-freshness-policies
- https://docs.dagster.io/guides/test/asset-checks
- https://docs.dagster.io/guides/build/partitions-and-backfills/backfilling-data
- https://docs.dagster.io/guides/build/partitions-and-backfills/partitioning-assets
- https://docs.dagster.io/guides/automate/sensors
- https://docs.dagster.io/deployment/execution/dagster-daemon
- https://docs.dagster.io/deployment/execution/run-monitoring
- https://docs.dagster.io/api/libraries/dagster-aws
- https://docs.dagster.io/api/libraries/dagster-k8s
- https://docs.dagster.io/api/libraries/dagster-dask
- https://docs.dagster.io/deployment/dagster-plus/management/terraform
- https://github.com/dagster-io/terraform-provider-dagsterplus
- https://registry.terraform.io/v1/providers/dagster-io/dagsterplus
- https://pypi.org/pypi/dagster/json

Airflow and MWAA
- https://airflow.apache.org/docs/helm-chart/stable/index.html
- https://airflow.apache.org/docs/apache-airflow/stable/core-concepts/overview.html
- https://airflow.apache.org/docs/apache-airflow/stable/core-concepts/backfill.html
- https://airflow.apache.org/docs/apache-airflow/stable/best-practices.html
- https://airflow.apache.org/docs/apache-airflow/stable/authoring-and-scheduling/event-scheduling.html
- https://airflow.apache.org/docs/apache-airflow/stable/authoring-and-scheduling/asset-scheduling.html
- https://airflow.apache.org/docs/apache-airflow/stable/howto/deadline-alerts.html
- https://airflow.apache.org/docs/apache-airflow-providers-amazon/stable/message-queues/index.html
- https://airflow.apache.org/docs/apache-airflow-providers-cncf-kubernetes/stable/kubernetes_executor.html
- https://pypi.org/pypi/apache-airflow/json
- https://pypi.org/pypi/apache-airflow-providers-daskexecutor/json
- https://github.com/apache/airflow/releases
- https://pricing.us-east-1.amazonaws.com/offers/v1.0/aws/AmazonMWAA/current/us-east-1/index.json
- https://aws.amazon.com/managed-workflows-for-apache-airflow/pricing/
- https://docs.aws.amazon.com/mwaa/latest/userguide/airflow-versions.html
- https://docs.aws.amazon.com/mwaa/latest/userguide/vpc-vpe-create-access.html
- https://docs.aws.amazon.com/mwaa/latest/userguide/mwaa-eks-example.html
- https://docs.aws.amazon.com/mwaa/latest/mwaa-serverless-userguide/what-is-mwaa-serverless.html
- https://docs.aws.amazon.com/mwaa/latest/mwaa-serverless-userguide/mwaas-concepts.html
- https://docs.aws.amazon.com/mwaa/latest/mwaa-serverless-userguide/workflows.html
- https://docs.aws.amazon.com/mwaa/latest/mwaa-serverless-userguide/operators.html
- https://docs.aws.amazon.com/mwaa/latest/mwaa-serverless-userguide/operators-python-bash-detail.html
- https://docs.aws.amazon.com/mwaa/latest/mwaa-serverless-userguide/supported-airflow-parameters.html

Argo, Argo CD, Karpenter, Dask, AWS networking
- https://argo-workflows.readthedocs.io/en/stable/ (and /installation/, /workflow-archive/, /retries/, /cron-workflows/, /cron-backfill/, /memoization/, /metrics/, /workflow-events/)
- https://github.com/argoproj/argo-workflows/releases
- https://argoproj.github.io/argo-events/eventsources/setup/aws-sqs/
- https://argoproj.github.io/argo-events/eventsources/setup/aws-sns/
- https://argoproj.github.io/argo-events/eventbus/eventbus/
- https://argoproj.github.io/argo-events/eventbus/jetstream/
- https://github.com/argoproj/argo-events/releases
- https://argo-cd.readthedocs.io/en/stable/user-guide/helm/
- https://raw.githubusercontent.com/argoproj/argo-cd/stable/docs/user-guide/sync-waves.md
- https://karpenter.sh/docs/concepts/disruption/
- https://github.com/aws/karpenter-provider-aws/releases
- https://kubernetes.dask.org/en/latest/
- https://pypi.org/pypi/dask-kubernetes/json
- https://argo-workflows.readthedocs.io/en/stable/fields/ and /synchronization/
- https://docs.aws.amazon.com/eks/latest/userguide/capabilities.html
- https://docs.aws.amazon.com/AmazonECR/latest/userguide/pull-through-cache.md
- https://github.com/hashicorp/terraform-provider-aws/blob/main/website/docs/r/mwaa_environment.html.markdown
- https://registry.terraform.io/v1/providers/hashicorp/aws
- https://pricing.us-east-1.amazonaws.com/offers/v1.0/aws/AmazonVPC/current/us-east-1/index.json
- https://aws.amazon.com/privatelink/pricing/

## Gaps Requiring Manual Verification

1. **Job-posting market signal:** not measured, no ranking asserted.
2. **Dagster+ PrivateLink:** which plan includes it, its price, and the need to "contact the Dagster team" for regional-style S3 URLs are not stated on the pages read.
3. **Dagster+ pricing page:** its HTML also contains a second block ($120/month with 7.5k credits; $1200/month with 30k credits) that conflicts with the FAQ; I used the FAQ. How partition materializations count as credits, the Pro price, and which plans include the Terraform provider and Hybrid are not readable from the extracted page.
4. **Self-hosted footprint cost:** resource requests of the Dagster, Airflow and Argo Workflows control-plane pods, and RDS or EBS prices, were not read, so the self-hosted always-on cost is unquantified.
5. **MWAA:** the micro class's limits and MWAA Serverless details (private EKS reachability from its VPC, Terraform support, backfill by API, SQS-triggered starts) were not verified. Only the existence of the `aws_mwaa_environment` resource was checked, not its full argument coverage.
6. **NOAA SNS topic access policy:** whether our SQS queue may subscribe cross-account to `NewNClimGridMonthlyObject` was not verified; the topic ARN itself is from the repo's report, not re-read at the registry.
7. **Argo Workflows:** whether a Karpenter drain surfaces as `Error` or `Failed` under `retryPolicy`; whether CronWorkflow-created Workflows inherit Argo CD tracking metadata; and the differences between 3.x and 4.x behind the "stable" docs (the pages cite "version 3.5 or later" and "v3.6 and after" while releases are 4.x).
8. **Dagster:** Prometheus metrics exposure, whether freshness alerts work in OSS, and asset lineage UI details were not read.
9. **Airflow:** Dag delivery options in the OSS chart (Dag bundles), the custom `DeadlineReference` API, and `KubernetesJobOperator` were not read.
10. **AWS managed Argo:** the EKS Capabilities page lists Argo CD, ACK and kro only; absence of a managed Argo Workflows product elsewhere at AWS (for example Marketplace) was not searched.
11. **Default image registries:** the registries used by the Airflow and Argo Workflows chart or manifest images, and whether each resolves through an ECR pull-through cache rule, were not read (ADR-0007 assigns the check to the spec).
12. **Not evaluated:** Prefect and AWS Step Functions with EventBridge Pipes. Step Functions in particular would have to be checked for private-EKS-endpoint support before it could be a serious fourth option.
13. **MWAA cost floor:** the figures use the environment rate only; additional workers, schedulers, web servers, metadata storage growth and the SQS and KMS endpoints are excluded.
