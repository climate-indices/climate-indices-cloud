# climate-indices-cloud — Capstone Brief

> **Status:** starting point for `/wayfinder` and `/grill-with-docs` sessions. This brief is
> a proposal, not a contract — challenge it. Decisions that change it belong in `../adr`,
> and resolved terminology belongs in `CONTEXT.md`.

## Summary

**climate-indices-cloud** is an open, validated drought and wildfire-danger indices service
for the continental US (CONUS). It:

- ingests NOAA gridded observations from AWS open data (and other public sources);
- computes SPI, SPEI, EDDI, percentage of normal, PDSI/scPDSI, and the wildfire index family
  (KBDI, CFFWIS, Hot-Dry-Windy, Haines, Fosberg) with **climate_indices 3.x** on Kubernetes;
- publishes analysis-ready Zarr, Cloud-Optimized GeoTIFFs, and Iceberg tables;
- serves them through a public API, a lightweight map site, and a "bring your own time
  series" analysis endpoint.

Every published dataset must pass the library's validation evidence before it goes live.
Building the service is itself instrumented, so the repo doubles as evidence of how
quickly the project is delivered using AI-assisted development (Claude Code, pi, herdr, Jev).

The project serves two purposes at once:

1. A portfolio piece demonstrating production data engineering, cloud infrastructure,
   DevOps/SRE, and AI-assisted delivery to prospective employers.
2. A real, free, nonprofit public service.

Optimize for production realism, low steady-state cost, and clear evidence over feature count.

## Relationship to climate_indices 3.0.0

- The compute engine is `climate-indices>=3.0,<4`. See its `../../CHANGELOG.md` (3.0.0),
  `../../VALIDATION.md`, and ADRs.
- 3.0.0's time-major `(time, *cells)` block vectorization replaces per-cell Python loops
  with one NumPy kernel call per block (e.g., gridded PDSI 135.4 s → 1.2 s on the reference
  grid). This is what makes a cloud service economical, and it dictates the Zarr chunking
  strategy: **time-contiguous chunks**.
- 3.0.0 corrected daily calendar alignment in the xarray adapter (a breaking fix), so
  calendars must be asserted at ingest.
- The xarray DataArray API remains Beta through 3.0.0 (ADR-0012); pin carefully and track
  changes before 3.1.0.

## Architecture at a glance

```
NOAA open data (AWS open data buckets, THREDDS)
  │  event-driven + scheduled ingest (orchestrator on EKS)
  ▼
s3://raw → analysis-ready Zarr (time-contiguous chunks) → data-quality gates
  ▼
Index compute: climate_indices 3.x on Dask (EKS, Karpenter spot nodes)
  ▼
Validation gate (VALIDATION.md fixtures + NCEI divisional comparisons)
  ▼
s3://published: versioned Zarr/COGs + Iceberg tables (Glue catalog → Athena/DuckDB)
  ▼
FastAPI on EKS ── CloudFront ── static map site
  │
Fluent Bit + OTel Collector → logs/metrics/traces → SLO dashboards, alerts
```

## Epics

### E0 — Ship climate_indices 3.0.0 (prerequisite; tracked on the existing 3.0.0 board)

- Tag the release, publish to PyPI, rebuild Read the Docs, and announce it. Update the
  changelog release date at tag time.
- Mine the 3.0.0 cycle's issue and PR history as the first dataset for E8. This gives a
  baseline from before the cloud-native work starts.

### E1 — Foundations

- New repo (keeps the library clean), organized as a uv workspace:
  `pipelines/`, `api/`, `infra/`, `site/`, `metrics/`.
- `../../CLAUDE.md` plus `../../AGENTS.md` (pi reads `../../AGENTS.md`); `CONTEXT.md` glossary and `../adr`
  seeded by grilling sessions.
- GitHub Actions with OIDC into AWS (no long-lived keys). CI runs ruff, mypy, pytest,
  tflint, checkov, and Trivy.
- Terraform: separate dev and prod environments; S3 backend with native lockfile locking;
  modules for network, EKS, data buckets, and IAM. AWS Budgets alarms from day one.
- **Decisions to grill:**
  - monorepo vs. multi-repo;
  - EKS vs. Fargate/Lambda for steady-state serving;
  - GitOps approach: Argo CD vs. Flux vs. Helm-from-CI.

### E2 — Ingestion and analysis-ready data

- **Monthly drought indices:** nClimGrid (gridded CONUS precipitation and temperature;
  the parent of the nClimDiv data the library's validation already compares against).
- **Daily fire indices:** require relative humidity and wind in addition to temperature and
  precipitation. Candidate sources: gridMET, ERA5, RTMA/URMA. *(Research ticket: variables,
  latency, licensing, AWS availability.)*
- Event-driven ingestion where the source publishes new-object notifications; scheduled
  otherwise. Idempotent, incremental, backfill-capable.
- Write CF-compliant Zarr chunked along time to match 3.0.0's block path. Record provenance
  for every run: source version, checksums, run ID.
- Data-quality checks: coverage, units, calendars.
- **Decision to grill:** orchestrator.
  - Dagster: asset lineage and freshness policies map naturally onto data SLOs.
  - Airflow: appears in more job postings.
  - Argo Workflows: Kubernetes-native.

### E3 — Computing indices at scale

- Dask on EKS via the Dask Kubernetes Operator, with Karpenter spot node pools.
- Each index and scale is configured in YAML (calibration period, distribution).
- Outputs:
  - versioned Zarr;
  - Cloud-Optimized GeoTIFFs for maps;
  - Iceberg tables of aggregates by climate division, county, and watershed (HUC).
- Reproduce the library's benchmark harness in-cluster and publish the cost and wall-clock
  time of a full CONUS recompute.
- **Stretch** (if targeting Spark-heavy roles): tabular aggregation on EMR Serverless or
  Spark-on-Kubernetes, with an ADR comparing it to Dask.

### E4 — Validation as a publishing contract

- Promote the `../../VALIDATION.md` checks into a pipeline gate that runs on every publish and
  blocks publication on drift beyond tolerance (e.g., SPI vs. NCEI climate-divisional
  values; standard Palmer vs. nClimDiv).
- Publish a validation report alongside each data release.

### E5 — API and analysis services

- FastAPI endpoints:
  - point time series (lat/lon);
  - area aggregates (division, county, HUC);
  - latest map layers;
  - dataset subset downloads.
- OpenAPI documentation.
- **Bring your own series:** upload a CSV time series and receive indices back. Small
  requests run synchronously; larger requests are queued (SQS + worker). The library's
  exception hierarchy maps cleanly to 4xx responses.
- CloudFront caching, WAF, rate limiting, optional free API keys for heavy users.

### E6 — Public site (deliberately thin)

- Static site on S3 + CloudFront: MapLibre maps, time-series charts, methodology page,
  data license, and a "not for operational decisions" disclaimer.
- The site is the window into the service, not the product. Keep front-end scope minimal.

### E7 — Observability, SRE, and security

- Fluent Bit DaemonSet shipping logs to CloudWatch Logs or OpenSearch; OTel Collector for
  traces and metrics; Prometheus + Grafana.
- SLOs:
  - API availability;
  - p95 latency;
  - data freshness (published within N hours of the upstream update).
- Alerting, runbooks, a postmortem template, and at least one game day.
- Supply chain and access: SBOMs, cosign-signed images, Renovate, least-privilege
  EKS Pod Identity, External Secrets.

### E8 — Delivery telemetry

See [Measuring AI-assisted delivery](#measuring-ai-assisted-delivery).

### E9 — Launch and sustainability

- Domain, docs, Zenodo DOI for citation, public cost dashboard.
- Licensing: NOAA inputs are public domain; derived data under CC-BY-4.0.
- Apply to the AWS Open Data Sponsorship program to host the published Zarr.
  AWS nonprofit credit programs generally require 501(c)(3) status — a later step, if ever.
- Case-study blog post; AMS Annual Meeting abstract.

## Measuring AI-assisted delivery

**Principles:** define metrics before the first ticket so they can't be cherry-picked;
publish the raw data; include the misses (reverted PRs and reopened tickets make the
numbers credible).

**Sources:**

- **GitHub:** issue lead time, PR cycle time, weekly throughput, PR size, CI first-pass
  rate, reopen/revert rate, bugs traced to closed stories. Once production is running, add
  DORA metrics (deployment frequency, change-failure rate, MTTR).
- **Claude Code:** built-in OpenTelemetry export (tokens, cost, active time, lines changed,
  commits, PRs), sent to the project's own OTel Collector.
- **pi + Jev:** pi session logs for tokens and cost per ticket; the pi-jev tool-call gate
  (fast typed judgments on whether a pending command is irreversible, off-task, mutating,
  or out of scope). Log every hold and whether it was the right call.
- **herdr:** subscribe to agent state changes via its socket API. Time spent in the
  "blocked" state means waiting on the human → **human attention minutes per ticket**.

**Attribution:**

- Commit trailer: `Ticket: #N`.
- Board field `Agent`.
- A pre-work `Estimate` (hours) on every ticket before any agent starts it. Estimates are
  biased; present them as a reference point, not as an "N× faster" claim.

**Dogfooding:** telemetry is stored in Iceberg tables on the same stack and powers a public
"Engineering" page on the site. Per-ticket records are appended to `metrics/runs.jsonl`.

## Milestones

| Milestone | Scope |
|---|---|
| **M1 — Tracer bullet** | SPI-3 from monthly nClimGrid → Zarr → validated → one API endpoint on a dev cluster. Deployed by CI, logs through Fluent Bit, telemetry recording. Everything thin, everything real. |
| **M2 — Breadth** | SPEI, EDDI, percentage of normal, PDSI/scPDSI; area aggregates; Iceberg tables. |
| **M3 — Fire** | Daily pipeline; KBDI, CFFWIS, Hot-Dry-Windy. |
| **M4 — Production** | Prod environment, SLOs, security hardening, public site, bring-your-own-series service. |
| **M5 — Launch** | Launch, metrics report, write-up, talk. |

## Cost reality check

Rough figures; confirm with the AWS Pricing Calculator.

- EKS control plane: ~$73/month per cluster.
- NAT gateway: ~$33/month each plus data processing charges (the classic surprise). Use VPC
  endpoints for S3 and ECR.
- An always-on demo stack realistically costs a few hundred dollars per month.
- A steady-state mode — compute scaled to zero between runs (Karpenter), serving mostly from
  CloudFront — could cut that substantially. The serving tradeoff deserves its own ADR.

## Project management conventions

- Every issue (wayfinder map, decision tickets, epics, specs, tickets) appears on the
  **cloud-native** project board (owner: `monocongo`).
- Board fields: Status, Epic (E1–E9), Agent (claude-code / pi / human), Estimate (hours),
  Actual (hours), Milestone (M1–M5).
- Epics are parent issues labeled `epic`. Specs are sub-issues of their epic. Tickets are
  sub-issues of their spec, with native "blocked by" relationships.
- Merging stays human: agents open PRs and stop at green CI.
