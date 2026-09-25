# Serving Cost Model: does the adopted EKS design hold the $250 dev and $500 prod ceilings?

**Date:** 2026-09-25  
**Ticket:** [#5](https://github.com/climate-indices/climate-indices-cloud/issues/5)

## Summary

**Verdict: ADR-0005's floor inventory is incomplete, and the recount leaves both ceilings with little or no room. At Central inputs dev is $18.21 under at M1, $20.81 (8.3%) over at M2, and prod is $7.90 (1.6%) over at M4; at Low inputs all three are under. The ceilings can hold, but only with a stated set of choices (endpoint count and AZs, Karpenter host, log volume, second ALB, node size), or with ADR-0005 amended.** ADR-0005's own inventory (control plane, one ALB, one small spot node, storage, logs) totals **$139/month in dev** and does leave about $110 of headroom. But that inventory omits line items the accepted ADRs themselves require, worth **$92 at M1 and $131 at M2**, and once they are counted the M2 dev floor and the M4 prod floor sit at or just over the ceiling *before any recompute runs*, while the M1 dev floor keeps about $18.

| Environment (us-east-1, 730 h) | Low | Central | Envelope high | Ceiling | Central vs ceiling |
| --- | ---: | ---: | ---: | ---: | ---: |
| Dev, ADR-0005 inventory only | $123.82 | $139.32 | $212.22 | $250 | $110.68 under |
| Dev at M1 (plain Jobs, complete floor) | $189.52 | **$231.79** | $426.95 | $250 | $18.21 under |
| Dev at M2 (Dagster, Prometheus, Grafana, Postgres) | $219.38 | **$270.81** | $442.73 | $250 | **$20.81 over** |
| Prod at M4, 1k / 10k / 100k requests per month | $327.09 | **$507.90** | $886.31 | $500 | **$7.90 over** |

"Envelope high" sums every pessimistic input at once; it is a sensitivity bound, not a forecast. The verdict is the interval, not a point: Low is under every ceiling and Central is over two of them. Prod's $7.90 overage is smaller than any one of dropping the second ALB (−$16.43), running one Karpenter host (−$30.37), or putting endpoints in one AZ (−$73.00).

What the model found, in order of dollars:

1. **Interface endpoints cost more than the NAT gateway ADR-0003 avoided.** Each is $7.30 per AZ per month; beyond 5 endpoints per AZ the endpoint bill exceeds a single NAT gateway ($36.50 with its address). The ADRs require at least 7. Dev pays $51–$146; prod at two AZs pays $146.
2. **Karpenter cannot run on a node it manages**, so the cluster needs a separate always-on host ($12–$61 dev, $30–$121 prod) that no ADR counts.
3. **ADR-0009's control plane does not fit the "small" spot node.** By AWS's pod limits and the component count, M2 needs about a 4 vCPU / 16 GiB node: +$36/month over the M1 node. ADR-0009 already says this "changes ADR-0005's floor and needs a recorded decision".
4. **Recompute bursts are not the problem.** A full-CONUS recompute is modelled at **$0.14–$0.45** under proportional scaling ($1.79 with a 4x margin), or $0.10–$0.30 at the measured per-cell scaling. The ceiling is decided by the always-on floor, not the burst.
5. **Traffic is not the problem either.** At 1k, 10k, and 100k requests per month every request-driven cost of `series`-sized responses (about 50 KB) is under $1; CloudFront stays inside its always-free tier until 10M requests or 1 TB out, so large static files (map layers, bulk downloads) are the exception.
6. **Two costs that grow or spike unless a policy exists:** per-Publish version storage (about $1.44–$2.87/month per dataset per year retained, all in Standard) and an EKS version left past standard support ($438/month instead of $73).

## Method and price basis

- **Region:** us-east-1. No ADR fixes the region; this one is chosen because the nClimGrid bucket and its SNS topic live there ([nclimgrid-aws report](https://github.com/climate-indices/climate-indices-cloud/blob/research/nclimgrid-aws/docs/research/nclimgrid-aws.md)) and the library's own EC2 benchmark runbook targets it. In-region S3 reads are free. Another region changes every price.
- **Hours:** 730 per month. **Prices:** AWS list prices from the AWS Price List bulk files, retrieved 2026-09-25 (index published 2026-09-25T09:39Z); file publication dates are in [Sources](#sources-consulted). No AWS credentials were used.
- **Spot:** the Spot Instance Advisor's 30-day "savings over On-Demand" per instance type, not a current spot price (that needs the EC2 API and credentials). See [Assumptions and unverified](#assumptions-and-unverified).
- **Reproducibility:** every total below is `hours × rate × count` with the arithmetic shown; the model was a stdlib script and is not committed.

### Price inputs

| Item | Price | Source | Retrieved |
| --- | --- | --- | --- |
| EKS control plane, standard support | $0.10/cluster-h = **$73.00** | Price List `AmazonEKS` `USE1-AmazonEKS-Hours:perCluster`; [EKS pricing](https://aws.amazon.com/eks/pricing/) | 2026-09-25 |
| EKS control plane, extended support | $0.60/cluster-h = **$438.00** (standard + $0.50) | EKS pricing page; `…Hours:extendedSupport` $0.50 | 2026-09-25 |
| Interface VPC endpoint | $0.01 per endpoint per AZ-h = **$7.30**; $0.01/GB processed | Price List `AmazonVPC` `USE1-VpcEndpoint-Hours`, `-Bytes` | 2026-09-25 |
| NAT gateway | $0.045/h = $32.85; $0.045/GB; address $0.005/h = $3.65 | Price List `AmazonEC2` `NatGateway-Hours`; `AmazonVPC` `PublicIPv4:InUseAddress` | 2026-09-25 |
| ALB | $0.0225/h = **$16.43**; $0.008/LCU-h = $5.84 per average LCU | Price List `AWSELB` | 2026-09-25 |
| m7i.large / m7i.xlarge / m7g.xlarge / r7i.xlarge / m7i.4xlarge on-demand | $0.1008 / $0.2016 / $0.1632 / $0.2646 / $0.8064 per h | Price List `AmazonEC2` | 2026-09-25 |
| t3.medium / t3.large on-demand | $0.0416 / $0.0832 per h | Price List `AmazonEC2` | 2026-09-25 |
| Spot savings (Advisor, us-east-1 Linux) | m7i.large 61%, m7i.xlarge 56%, m7g.xlarge 53%, r7i.xlarge 61%, m7i.4xlarge 55%, t3.medium 60% | [Spot Instance Advisor data](https://spot-bid-advisor.s3.amazonaws.com/spot-advisor-data.json) | 2026-09-25 |
| EBS gp3 | $0.08/GB-month | Price List `AmazonEC2` | 2026-09-25 |
| S3 Standard / Glacier Instant Retrieval | $0.023 / $0.004 per GB-month; PUT $0.005 per 1k, GET $0.0004 per 1k | Price List `AmazonS3` | 2026-09-25 |
| CloudWatch Logs ingestion / storage | $0.50/GB / $0.03/GB-month | Price List `AmazonCloudWatch` | 2026-09-25 |
| CloudWatch alarm / custom metric | $0.10 (first 10 free) / $0.30 | Price List `AmazonCloudWatch` | 2026-09-25 |
| Glue Data Catalog | first 1M objects and 1M requests free | Price List `AWSGlue` | 2026-09-25 |
| Secrets Manager / ECR storage | $0.40 per secret-month / $0.10 per GB-month | Price List `AWSSecretsManager`, `AmazonECR` | 2026-09-25 |
| Fargate (Karpenter host alternative) | $0.04048/vCPU-h, $0.004445/GB-h | Price List `AmazonECS` | 2026-09-25 |
| WAF | $5 per web ACL, $1 per rule or managed rule group, $0.60 per million requests up to 1,500 WCU | Price List `awswaf`; [WAF pricing](https://aws.amazon.com/waf/pricing/) | 2026-09-25 |
| CloudFront pay-as-you-go | always-free 1 TB out and 10M requests; then $0.085/GB (first tier), $0.0100 per 10k HTTPS requests; Functions $0.10/M (2M free); VPC-origin fetches free; 1,000 invalidation paths free | [CloudFront pay-as-you-go pricing](https://aws.amazon.com/cloudfront/pricing/pay-as-you-go/); Price List global `AmazonCloudFront/current/index.json` | 2026-09-25 |

## Dev floor

### What ADR-0005 counted

ADR-0005: "Dev's floor after ADR-0003 (no NAT) is roughly the EKS control plane plus an ALB, a small spot node, storage, and logs, leaving genuine headroom for recompute bursts; prod adds CloudFront, WAF, and a larger serving pool."

| Item | Arithmetic | Low | Central | High |
| --- | --- | ---: | ---: | ---: |
| EKS control plane | 0.10 × 730 | 73.00 | 73.00 | 73.00 |
| ALB ×1 (+ LCU 0 / $1 / $5.84) | 0.0225 × 730 = 16.43 | 16.43 | 17.43 | 22.27 |
| One "small" spot node, m7i.large (8 GiB) | 0.1008 × (1 − 0.61) × 730 | 28.70 | 28.70 | 64.75 (m7i.xlarge) |
| EBS, two 20 GB roots | 40 × 0.08 | 3.20 | 3.20 | 3.20 |
| S3 (about 30 GB) and requests | | 1.00 | 2.00 | 4.00 |
| Logs, 0.1 / 1 / 3 GB per day | GB × 30 × 0.50 (central = ADR-0007's 1 GB/day guard, $15) | 1.50 | 15.00 | 45.00 |
| Glue Data Catalog | free tier | 0.00 | 0.00 | 0.00 |
| **Total** | | **123.82** | **139.32** | **212.22** |

CloudFront is not in dev before M4 ([#19](https://github.com/climate-indices/climate-indices-cloud/issues/19): nothing is public before M4); it would cost $0 at these volumes inside the always-free tier if added.

### What the accepted ADRs add

| Item | Arithmetic | Low | Central | High |
| --- | --- | ---: | ---: | ---: |
| Interface endpoints, 7 / 8 / 10 in 1 / 1 / 2 AZ | 7.30 per endpoint per AZ | 51.10 | 58.40 | 146.00 |
| Karpenter host: t3.medium spot / t3.medium on-demand / t3.large on-demand | 0.0416 × (1 − 0.60) × 730 = 12.15; 0.0416 × 730 = 30.37; 60.74 | 12.15 | 30.37 | 60.74 |
| Secrets Manager, 3 / 3 / 5 | × 0.40 | 1.20 | 1.20 | 2.00 |
| ECR, 5 / 10 / 20 GB | × 0.10 | 0.50 | 1.00 | 2.00 |
| Alarms and metric filters | | 0.50 | 1.00 | 2.00 |
| Endpoint data processing, 25 / 50 / 200 GB | × 0.01 | 0.25 | 0.50 | 2.00 |
| **M1 additions** | | **65.70** | **92.47** | **214.74** |
| **Dev at M1 (ADR-0005 + additions)** | | **189.52** | **231.79** | **426.95** |
| Serving and control-plane node, M2: m7g.xlarge / m7i.xlarge / r7i.xlarge spot, minus that column's M1 node | 55.99 − 28.70; 64.75 − 28.70; 75.33 − 64.75 | 27.29 | 36.06 | 10.58 |
| EBS, Prometheus 20 + Postgres 10 + Grafana 2 GB | 32 × 0.08 (High: 60 GB, itemisation not retained) | 2.56 | 2.56 | 4.80 |
| Secrets, +1 pull-through cache credential | | 0.00 | 0.40 | 0.40 |
| **M2 delta** | | **29.86** | **39.02** | **15.78** |
| **Dev at M2** | | **219.38** | **270.81** | **442.73** |

Where each addition comes from:

- **Endpoints.** ADR-0003 lists ECR, Secrets Manager, CloudWatch, and STS; read as `ecr.api`, `ecr.dkr`, `secretsmanager`, `logs`, and `sts`, that is five interface endpoints (the S3 gateway endpoint is free). [AWS's private-cluster page](https://docs.aws.amazon.com/eks/latest/userguide/private-clusters.html) adds `ec2` and `elasticloadbalancing`, and `eks-auth` for Pod Identity. That makes 7, or 8 with either `eks-auth` or a Karpenter interruption queue (the SQS endpoint). The same page also lists `eks` and, for IRSA, `oidc-eks`, and Karpenter's [private-cluster guide](https://karpenter.sh/docs/getting-started/getting-started-with-karpenter/) requires `ec2`, `ssm` (resolving default AMIs), and `eks` (discovering the cluster endpoint). `ssm` is avoidable only by pinning AMI IDs. Neither `ssm` nor `eks` is in the counts here; each adds $7.30 per AZ. ADR-0009 already reports the gap; this prices it. Pod Identity swaps `sts` for `eks-auth`, so it does not save an endpoint. M4 adds SQS (Submission queue, [#19](https://github.com/climate-indices/climate-indices-cloud/issues/19)) and SNS (Alertmanager, ADR-0007), so prod carries about 10. Dev pins to one AZ in Low and Central; EKS itself needs subnets in two AZs, but nodes and endpoints do not.
- **Karpenter host.** The [EKS best-practices guide](https://aws.github.io/aws-eks-best-practices/karpenter/): "Do not run Karpenter on a node that is managed by Karpenter", with "one small node group with at least one worker node" or a Fargate profile as the alternatives. The [Karpenter getting-started guide](https://karpenter.sh/docs/getting-started/getting-started-with-karpenter/) uses a managed node group (`m5.large`, minimum 1) for the `kube-system` and `karpenter` namespaces and requests 1 vCPU / 1 GiB for the controller. On Fargate that request bills 1 vCPU + 2 GB, $36.04 a month, because Fargate [adds 256 MB per pod and rounds up to a supported size](https://docs.aws.amazon.com/eks/latest/userguide/fargate-pod-configuration.html); that is more than a t3.medium on demand. No ADR mentions this host. The API pool ADR-0003 describes is Karpenter-managed, so it cannot be the host.
- **M2 node size.** ADR-0009 puts the Dagster daemon, webserver, code server, and Postgres on the API's spot pool; ADR-0007 adds kube-prometheus-stack and Grafana; ADR-0004 adds Argo CD. By AWS's [max-pods table](https://github.com/aws/amazon-vpc-cni-k8s/blob/master/misc/eni-max-pods.txt) an m7i.large holds 29 pods and an m7i.xlarge 58. My count of those components, their DaemonSets, and two API replicas is 23–25 pods and about 6–8 GiB of requests; that is an assumption from upstream chart shapes, not a measurement (ADR-0009: "Pod sizes were not measured"). An 8 GiB node fails on memory; a 16 GiB, 4 vCPU node is the smallest plausible fit. If Argo CD instead lives on the Karpenter host, that host grows to a t3.large or larger.

## No-NAT versus a NAT gateway

ADR-0003 cites the brief's "classic surprise" NAT line item as a reason to go without. At the endpoint counts ADR-0003 and ADR-0009 require, the arithmetic reverses:

| Design (dev, one AZ) | Arithmetic | $/month |
| --- | --- | ---: |
| 5 endpoints (ADR-0003's list, read as above) | 5 × 7.30 | 36.50 |
| 8 endpoints | 8 × 7.30 | 58.40 |
| 10 endpoints | 10 × 7.30 | 73.00 |
| One NAT gateway, address, 50 GB | 32.85 + 3.65 + 50 × 0.045 | 38.75 |
| Break-even vs one NAT, no traffic | 36.50 / 7.30 | 5 endpoints per AZ |

In two AZs (prod): 10 endpoints cost $146.00; two NAT gateways with addresses and 100 GB cost 73.00 + 4.50 = $77.50, a difference of about $69/month (the endpoint data-processing line, $1.00, also disappears). The no-NAT posture may still be right for the egress-constraint reasons in ADR-0003 (ERA5 via CDS is already flagged there as the case that would need egress), but **it is not a saving**, and its cost is the largest single line in prod ($146.00 against $129.51 for the serving pool) and second only to the control plane in dev at M1. This is a decision for the maintainer, not one this ticket makes.

## The burst: one full-CONUS recompute

### What the library measured

Library [`benchmarks/README.md`](https://github.com/monocongo/climate_indices/blob/main/benchmarks/README.md), section "Legacy CLI multiprocessing vs xarray/Dask on CONUS nClimGrid (#1121)"; results in `benchmarks/results/nclimgrid_spi6_*.txt`. Full nClimGrid grid, 596 × 1385 (469,758 land of 825,460 cells), 528 months (1981–2024), SPI-6, calibration 1991–2020, Apple M5 machine, 10 CPUs, 32 GB, Python 3.14:

| Configuration | Compute (min of 3) |
| --- | ---: |
| xarray eager serial, gamma | 63.156 s (plus read 17.850 s, write 0.506 s) |
| xarray/Dask `processes`, gamma, 1 / 2 / 4 / 8 workers | 129.821 / 90.661 / 69.561 / 65.001 s |
| CLI `multiprocessing.Pool`, gamma, 9 workers | 28.679 s |
| CLI `multiprocessing.Pool`, **Pearson**, 9 workers | **104.726 s** |

Two facts limit what this can support:

- **No cluster benchmark exists.** The library's EC2 scale-out section (#1127) reads "Pending the maintainer's cluster run". Every number above is one machine, and Dask 8 workers reached only 2.0x over 1 worker ("barely reaching eager's serial time"), a negative result the library explains, as an interpretation it marks "not measured", by pickling across processes at this size.
- **The path ADR-0006 needs is the one not benchmarked.** ADR-0006 fixes Pearson III. The library states the xarray-path Pearson is not comparable because of [#1118](https://github.com/monocongo/climate_indices/issues/1118), **still open at retrieval**: the block Pearson kernel returns all-NaN once half or more of a block's cells are entirely missing. nClimGrid is 43.1% masked overall, so coastal and border tiles at typical tile sizes will cross that line. The only working Pearson timing is the CLI's per-cell path.

### The model

Anchor to the one working Pearson number: 104.726 s × 9 workers = 942.5 core-seconds for 528 months and a 30-year calibration. The M1 shape (SPI-3, Pearson III, calibration 1895–2022, 1,580 months) has 2.99x the months and 4.27x the calibration years. Two scalings bracket it:

- **Proportional, the conservative bound used in the first table row:** 942.5 × 4.27 = 4,021 core-s (**1.12 core-h**), cost growing with calibration years. The months-only scaling, 942.5 × 2.99 = 2,820 core-s (0.78 core-h), is smaller and unused.
- **Measured:** timing the library's per-cell Pearson III path (`compute.transform_fitted_pearson`, one thread, synthetic gamma data, not the block path) at both shapes gives 1.13 ms per cell for 528 months and a 30-year calibration and 1.42 ms for 1,584 months and a 128-year calibration, x1.26. Fixed per-call work dominates, so cost is far from proportional. At x1.3, 942.5 × 1.3 = 1,225 core-s (**0.34 core-h**). The timing script is not committed, and it is one machine and one path: it shows the shape of the scaling, not cluster throughput.
- On one m7i.4xlarge (16 vCPU, 64 GiB), proportional scaling: 7.4 min if parallel efficiency matches the CLI's shared-memory path (9x), 33.5 min if it matches Dask-8's measured 2.0x. At the measured scaling: 2.3 and 10.2 min.
- Plus ingest read, write, gate, derived point-series, and publish, assumed 15–25 min (the benchmark's read and write scale to about 1 minute; the rest is unmeasured), plus 15 min for node start, image pull, and warm-down in the worst case.
- Node-hours: proportional 0.38 best, 1.23 worst; measured scaling 0.29 best, 0.84 worst. Memory: 469,758 land cells × 1,580 × 4 B = 2.97 GB float32 (5.94 GB float64; the full grid is 5.22 GB float32), which fits 64 GiB.

| | Best | Worst | Worst × 4 margin |
| --- | ---: | ---: | ---: |
| Proportional scaling, m7i.4xlarge spot, 0.8064 × (1 − 0.55) = $0.3629/h | 0.38 h → **$0.14** | 1.23 h → **$0.45** | **$1.79** |
| Measured scaling (x1.3), same spot node | 0.29 h → $0.10 | 0.84 h → $0.30 | $1.22 |
| Same node on-demand | | $0.99 | |

**Recomputes per month the ceiling allows:** headroom ÷ per-recompute cost. At Central dev M2 the headroom is negative, so none; at Low ($219.38) the $30.62 of headroom buys about 68 recomputes at $0.45 or 17 at $1.79. Cost per recompute is small enough that the count is limited by wall-clock, not money (see the next two paragraphs).

**A monthly upstream tick recomputes every Published Dataset that shares the upstream.** With N datasets (an illustrative 30; [#23](https://github.com/climate-indices/climate-indices-cloud/issues/23) decides N) that is 30 × $0.14–$0.45 = **$4.20–$13.50 per month**, or at most $53.70 with the 4x margin on every run.

**Wall-clock, not dollars, is what the recompute count can threaten.** ADR-0009 allows "one compute run cluster-wide until #23 sets the pool ceilings", and ADR-0007's freshness SLO is 24 hours. N serialized runs at 0.38–1.23 h each (proportional scaling) take 3.8–12.3 h at N = 10 and **about 11–37 h** at the illustrative N = 30, so the worst case breaches the 24 h objective from about N = 20 on a cost-free path. That charges 15 min of start and warm-down to every run, which serialized runs on a warm node would not pay. At the measured scaling (0.29–0.84 h per run) N = 30 is 8.7–25.2 h. The result rests on the unmeasured 15–25 min I/O assumption. This is for #23, not this ticket.

### Which #23 choices move this number

| #23 choice | Effect on the burst |
| --- | --- |
| Dask topology: LocalCluster in one pod (M1) vs operator across nodes | The 2.0x versus 9x parallel-efficiency gap is the whole 7–34 minute range (2–10 minutes at the measured scaling); #1127 is the missing measurement. |
| Tile size against #1118 | Tiles at or over 50% missing break the block Pearson kernel; the fallback is the per-cell path whose timing the model already uses. |
| Number of Published Datasets, calibration windows, Palmer and scPDSI | Multiplies the per-month sweep; scPDSI's per-location calibration has no timing anywhere in the library's results. |
| Node shape and warm policy | m7i.2xlarge (half the memory and vCPU) roughly halves the hourly price; a longer idle window before consolidation adds warm hours. |
| Pool ceiling and concurrency | Determines whether N runs serialize (above) or overlap, and how many burst nodes exist at once. |

## Storage growth: per-Publish versions

ADR-0001 and ADR-0009 give the published path as `published/<index>/<timescale>/cal<start>-<end>/<YYYY-MM>.r<N>/`, ADR-0009 recomputes the whole series per Publish, and #19 makes a `version`-pinned request "immutable and caches without expiry". Each monthly Publish is therefore a full new store plus its derived point-series Zarr (ADR-0008: "a few GB per version"). ADR-0001 gives 825,460 cells over about 1,560 months; at the M1 shape's 1,580 months ([#18](https://github.com/climate-indices/climate-indices-cloud/issues/18): from 1895-01 to the latest available month) one float32 store is 5.22 GB uncompressed (5.15 GB at 1,560); taking 5.2–10.4 GB per version set (store plus point series; compression unmeasured):

| Retained, all in S3 Standard | Arithmetic | $/month |
| --- | --- | ---: |
| 1 dataset, 12 Publishes/year | 62.4–124.8 GB × 0.023 | 1.44–2.87 per year retained |
| 10 datasets, 1 / 3 years | | 14.35–28.70 / 43.06–86.11 |
| 30 datasets, 1 / 3 years | | 43.06–86.11 / 129.17–258.34 |
| Same, after transition to Glacier Instant Retrieval | × 0.004 (retrieval $0.03/GB) | about 17% of the above |

This is the one large cost that grows without any change in traffic or code, and it is invisible until a policy exists. Three years of 30 datasets retained in Standard would consume half to slightly more than all of the dev ceiling ($129–$258 against $250). A lifecycle rule (Standard for the last few versions, Glacier Instant Retrieval for older ones) is the knob; nothing in the ADRs sets one, and ADR-0001 defers structural sharing (`icechunk`) that would avoid the copies.

## Prod at M4

Prod is a separate Terraform root (ADR-0005), so it has its own control plane, endpoints, and nodes. Its ceiling is $500.

| Item | Arithmetic | Low | Central | High |
| --- | --- | ---: | ---: | ---: |
| EKS control plane | 0.10 × 730 | 73.00 | 73.00 | 73.00 |
| Interface endpoints, 8 / 10 / 12 in 1 / 2 / 2 AZ | 7.30 each | 58.40 | 146.00 | 175.20 |
| ALB ×1 / ×2 / ×2 (API via VPC origin; Grafana allowlist) | 16.43 each + LCU at 0.5 / 1 / 2 average LCUs in total (2.92 / 5.84 / 11.68) | 19.34 | 38.69 | 44.53 |
| WAF: ACL + Core rule set + IP reputation + 3 rate rules | 5 + 5 × 1, + $0.06 at 100k requests (High: 7 rules, the two extra unspecified) | 10.06 | 10.06 | 12.06 |
| CloudFront | inside always-free tier at ≤ 100k requests | 0.00 | 0.00 | 0.00 |
| Serving pool: 2 × m7g.xlarge spot / 2 × m7i.xlarge spot / 2 × m7i.xlarge on-demand | 2 × 55.99 / 2 × 64.75 / 2 × 147.17 | 111.99 | 129.51 | 294.34 |
| Karpenter host: 1 × t3.medium / 2 × t3.medium / 2 × t3.large, on-demand | 30.37 each / 60.74 each | 30.37 | 60.74 | 121.47 |
| EBS | (4 / 5 / 6 nodes × 20 GB + 32 / 32 / 60 GB stateful) × 0.08; Central 5 × 20 + 32 = 132 GB | 8.96 | 10.56 | 14.40 |
| Logs 0.5 / 1 / 3 GB/day + EKS audit and authenticator logs 1 / 5 / 10 GB | × 0.50 | 8.00 | 17.50 | 50.00 |
| S3, N = 1 / 10 / 30 datasets after 1 year | storage table above: Low the top of the 1-dataset range, Central the bottom of the 10-dataset range, High the top of the 30-dataset range | 2.87 | 14.35 | 86.11 |
| ECR, Secrets Manager, alarms and metric filters, endpoint data | 1.00 + 1.60 + 1.00 + 0.50 (Low); High: ECR 30 GB 3.00 + 8 secrets 3.20 + alarms 6.00 (no count retained) + endpoint data 300 GB 3.00 | 4.10 | 7.50 | 15.20 |
| **Total** | | **327.09** | **507.90** | **886.31** |

Central check: 73.00 + 146.00 + 38.69 + 10.06 + 129.51 + 60.74 + 10.56 + 17.50 + 14.35 + 1.50 + 2.00 + 3.00 + 1.00 = 507.91 (rounding).

Two AZ endpoints are 29% of the Central total. Prod at Central is $7.90 over, with no storage growth or burst in it.

### Request-driven cost at 1k / 10k / 100k requests per month

Assumptions: the `series` response is about 50 KB raw (about 1,580 monthly values in JSON) or 15 KB gzip; cache hit 0% (worst case for origin cost) to 50%; ADR-0008 caches per grid cell, and 100k random points over about 470k land cells will mostly miss.

| Requests/month | WAF ($0.60/M, charged on cache hits too) | CloudFront requests and transfer | S3 GETs at 100% miss | ALB LCU |
| ---: | ---: | ---: | ---: | ---: |
| 1,000 | $0.0006 | $0.00 (0.05 GB out) | $0.000 | about 0 |
| 10,000 | $0.0060 | $0.00 (0.50 GB out) | $0.004 | about 0 |
| 100,000 | $0.0600 | $0.00 (5.00 GB out) | $0.040 | about 0 |

Traffic does not move the total until it passes the free tiers: 10M HTTPS requests per month (the request tier ends before the 1 TB transfer tier does, at 50 KB per response). Beyond them the marginal cost is **about $3.08 per million requests** at 15 KB gzip and a 50% cache hit: WAF 0.60 + CloudFront HTTPS 1.00 + transfer 15 GB × 0.085 = 1.275 + S3 GET 0.50M × $0.0004 per 1k = 0.20. At 50 KB raw and no cache hits it is $6.25: 0.60 + 1.00 + 50 GB × 0.085 = 4.25 + S3 GET 1M × $0.0004 per 1k = 0.40. Origin compute is not modelled. At the Low total ($327.09) that is about $172.91 ÷ 3.08 = 56M requests per month of headroom (27.7M at $6.25); at Central, none.

## What breaches each ceiling, and the knob to turn

| Trigger | Monthly effect | Environment | Knob |
| --- | ---: | --- | --- |
| Interface endpoints in 2 AZs instead of 1 | +$58.40 (8 endpoints) | dev | Pin dev nodes and endpoints to one AZ |
| Interface endpoints, 2 AZs, 10 endpoints | $146.00 | prod | Fewer endpoints; one AZ (loses AZ resilience); or a NAT (about −$69 versus 10 endpoints in two AZs) |
| M2 control plane sized to a 16 GiB node | +$36.06 | dev | Measure the pods before sizing ([#27](https://github.com/climate-indices/climate-indices-cloud/issues/27): "Requests are sized before M2"); Graviton −$8.76 |
| Karpenter host on-demand t3.medium | $30.37 | dev, prod | Managed-group node on spot −$18.22 (Advisor interruption band above 20%). Fargate is not cheaper at the guide's 1 vCPU / 1 GiB request ($36.04, +$5.67); it saves only if the controller's requests are lowered to 0.5 vCPU / 1 GiB, billed as 0.5 vCPU + 2 GB = $21.26 (−$9.10) |
| Logs at ADR-0007's own 1 GB/day guard, per group | $15.00 | dev, prod | Lower the guard; 1 to 0.2 GB/day −$12.00 |
| A second ALB | +$16.43 | dev, prod | Share one ALB via an Ingress group; prod's VPC-origin ALB cannot share with an IP-allowlisted Grafana ALB, so use port-forward |
| Serving pool on on-demand instead of spot | +$164.83 (2 × m7i.xlarge) | prod | Stay on spot; spot interruption is an SLO risk ADR-0007 owns |
| An EKS cluster past standard support (14 months) | +$365.00 per cluster (438.00 − 73.00) | dev, prod | Upgrade cadence at least every 14 months; extended support lasts 12 more |
| Version retention with no lifecycle | +$1.44–$2.87 per dataset per year retained | dev, prod | Glacier Instant Retrieval lifecycle for older versions |
| Requests beyond the free tiers | about $3.08 per million at 15 KB gzip and 50% cache hit ($6.25 at 50 KB raw and 0% hit) | prod | WAF per-IP rate limits (#19 already plans them) |
| Burst pool left warm (minimum nodes at 1 or more, or no consolidation) | +$264.90 (m7i.4xlarge spot 24×7; $588.67 on-demand) | dev, prod | Scale the burst pool to zero, keep a short consolidation delay, and cap it with a NodePool `limits` value (the worker ceiling) |
| Serving pool size (prod, 2 to 1 × m7i.xlarge spot) | −$64.75 | prod | Not free: ADR-0005 says prod adds "a larger serving pool", and one node is a single point of failure for a public API |
| Log retention (7 to 30 days at 1 GB/day) | +$0.69 (storage $0.03/GB-month: about $0.21 at 7 days, $0.90 at 30) | dev, prod | Not a lever: ingestion at $0.50/GB is the cost, so lower the volume, not the retention |
| Large static objects over CloudFront (map layers, bulk downloads) | $0.085 per GB past the 1 TB free tier, which equals an average of 10 MB per request at 100k requests; one bulk Zarr set (about 5.2 GB) costs about $0.44 per download past it | prod | WAF per-IP request limits do not bound bytes; size caps or a gated path for bulk files |
| Environment existing 24×7 | $243.95 of dev M2 Central is hour-billed (73.00 + 58.40 + 17.43 + 30.37 + 64.75) | dev | Existence schedule: up 50% of hours saves $121.98; 25% saves $182.96. Needs the cluster destroyed and re-created, since the control plane bills only while it exists |

**What it takes to bring dev M2 under $250 from $270.81 (needs −$20.81):**

- Karpenter host on a spot managed-group node (−$18.22) plus logs at 0.2 GB/day (−$12.00) gives $240.59.
- One NAT in place of the endpoints (−$20.15, counting the $0.50 endpoint data line) alone gives $250.66, not enough.
- Combined, the host on spot (−$18.22), logs at 0.2 GB/day (−$12.00), Graviton (−$8.76), and one fewer endpoint (−$7.30) reach $224.53, close to the Low column ($219.38), with about $25 of room for bursts and growth. More than that takes an existence schedule (dev up half the time, about −$122) or a recorded ceiling change to about $300.

## Assumptions and unverified

Values here move a total by more than about 10% unless marked.

| Assumption | Value used | Moves the result by | Basis |
| --- | --- | --- | --- |
| Interface-endpoint count and AZ count | 7 / 8 / 10 in 1 / 1 / 2 AZ (dev) | $51–$146 | AWS's private-cluster list versus ADR-0003's list; whether Karpenter's interruption queue is used is undecided, and `ssm` and `eks` are not counted |
| AZ count in prod | 1 / 2 / 2 AZs | $73.00 (endpoints) | No ADR fixes an AZ count; EKS needs subnets in two AZs, but nodes and endpoints do not. Central takes the costlier choice |
| Second ALB in prod | 1 / 2 / 2 ALBs | $16.43 | ADR-0007 allows port-forward or an IP-allowlisted internal ALB for Grafana; Central takes the ALB |
| Karpenter host | t3.medium spot / t3.medium on-demand / t3.large on-demand | $12–$61 | AWS and Karpenter guidance require one; which is a spec choice. Fargate at the guide's 1 vCPU / 1 GiB request bills 1 vCPU + 2 GB ($36.04), so it is the cheap option only if the controller's requests are lowered |
| M2 node size | m7i.xlarge (16 GiB, 58 pods) | +$36 | Component counts from upstream chart shapes; ADR-0009 states pod sizes were not measured; **not** a measurement |
| Log volume | 0.1 / 1 / 3 GB per day | $1.50–$45 | ADR-0007's 1 GB/day alarm threshold, which it calls "a first guess" ("revisit once a full-CONUS recompute gives a measured volume"); Central uses the threshold as the expected volume, so it is pessimistic here |
| Spot discount | Advisor "savings over On-Demand", 53–61% | about $15 per m7i.xlarge per 10 points | The [Advisor page](https://aws.amazon.com/ec2/spot/instance-advisor/) defines it as calculated over the last 30 days and averaged across AZs; the data file is an AWS-owned static file behind that page, not a documented API; current spot price needs credentials |
| Spot interruption | not costed | | Advisor reclaim-rate bands (trailing month) for these types run from 10–15% (m7g.xlarge) to above 20% (m7i.xlarge, r7i.xlarge, m7i.4xlarge, t3.medium); reclaim of the single dev node means an outage until Karpenter replaces it |
| Publish version-set size | 5.2–10.4 GB | storage table | Derived from ADR-0001 and ADR-0008 figures; compression not measured |
| Number of Published Datasets | 1 / 10 / 30 | storage and burst sums | Illustrative; #23 decides |
| Dev S3 growth at M2 | about 30 GB at M1; no growth counted | $1.44–$2.87 per dev dataset per year retained | If dev runs the sensor, it also accumulates Publish versions (ADR-0009) |
| Recompute time | 0.38–1.23 node-hours proportional; 0.29–0.84 at the measured per-cell scaling | under $2 per run | Scaled from the CLI Pearson benchmark; the x1.3 scaling is one machine, one path, synthetic data; no cluster benchmark (#1127) and #1118 open |
| I/O, publish, and warm-down minutes | 15–25 and 15 | under $0.10 per run | Assumed |
| ALB LCU | dev, per ALB: $0 / $1 / $5.84; prod, in total: 0.5 / 1 / 2 average LCUs ($2.92 / $5.84 / $11.68) | under $12 | Traffic is near zero; not measured |
| Unitemised High cells | dev M2 EBS 60 GB; prod WAF 7 rules; prod EBS 4 to 6 nodes and up to 60 GB stateful; prod alarms $6.00 | under $8 each | High is a sensitivity bound; the itemisation of these cells was not retained |
| Prod S3 point in each range | Low top of N=1, Central bottom of N=10, High top of N=30 | Low −$1.43 at the bottom; Central +$7.18 at the midpoint | The storage table's 5.2–10.4 GB per version set is itself unmeasured |
| Response size and cache-hit rate | 50 KB raw / 15 KB gzip; 0–50% | under $1 at the stated volumes | Assumed from the `series` shape |

Not costed, each small or undecided: Route 53, KMS, the M4 Submission worker on the compute pool ([#19](https://github.com/climate-indices/climate-indices-cloud/issues/19)), ALB access-log storage in S3 (ADR-0007), ACM (free), domain registration, cross-AZ data transfer ($0.01/GB), CloudFront Function invocations ($0.10 per million, first 2M free), SQS and SNS request charges, EBS snapshots, Athena ($5 per TB scanned, [#22](https://github.com/climate-indices/climate-indices-cloud/issues/22) is open and a public query surface has no cost cap), and the Cost Explorer API calls behind the public cost dashboard ([#25](https://github.com/climate-indices/climate-indices-cloud/issues/25)). Whether a NAT gateway's address is billed under the public IPv4 charge is assumed, not verified (at most $3.65). The ALBs are internal ([#18](https://github.com/climate-indices/climate-indices-cloud/issues/18), [#19](https://github.com/climate-indices/climate-indices-cloud/issues/19)), so no public IPv4 charge applies to them; an internet-facing ALB would add about $7.30 each (2 AZs × $3.65).

**CloudFront** figures (always-free tier, $0.085 per GB, $0.0100 per 10k HTTPS requests, Functions, invalidation) were read from the pay-as-you-go page and agree with the global Price List file, `https://pricing.us-east-1.amazonaws.com/offers/v1.0/aws/AmazonCloudFront/current/index.json`, published 2026-09-16; the `us-east-1` file holds only Origin Shield and Lambda@Edge items. "VPC-origin fetches free" has no Price List entry and rests on the pricing page. The WAF, EKS, ELB, VPC, EC2, S3, CloudWatch, Glue, ECR, and Secrets Manager prices were read from the regional bulk files.

**Resolved from earlier notes:**

- [#19](https://github.com/climate-indices/climate-indices-cloud/issues/19) "not verified": WAF managed rule groups carry the $1 per-rule-group charge and no other fee that the pricing page mentions; the Core rule set is 700 WCU, the IP reputation list 25, and a rate-based rule 2 (plus 30 per custom aggregation key), all under the 1,500-WCU threshold above which the request price rises by $0.20 per million for each additional 500. Inspection is 16 KB by default for CloudFront ([body inspection limit](https://docs.aws.amazon.com/waf/latest/developerguide/web-acl-setting-body-inspection-limit.html)).
- [#20](https://github.com/climate-indices/climate-indices-cloud/issues/20) and ADR-0007 "not verified": an SNS interface endpoint carries the same $0.01 per AZ-hour as every other interface endpoint in the Price List; the file has no service-specific rate.
- ADR-0008 says the first 1,000 invalidation paths per month are free; the CloudFront page still says so.

## Handed to other tickets

Suggestions only; nothing was created.

- **ADR-0005 (reopen or amend).** The dev floor at M2 is $270.81 against $250 and prod is $507.90 against $500 at Central. The maintainer either records a higher ceiling (about $300 dev, $550 prod covers Central with about $29–$42 of room for storage growth), or adopts a named set of knobs, or both; at Low inputs the current ceilings already hold. Its "genuine headroom for recompute bursts" sentence holds at M1 (about $18 of headroom against $0.14–$1.79 per burst) and fails at M2 and M4 because of the floor, not the burst.
- **ADR-0003 (cost rationale only).** Interface endpoints exceed a NAT gateway beyond 5 per AZ; the endpoint list also needs the `ec2`, `elasticloadbalancing`, and `eks-auth` (or `oidc-eks`) additions ADR-0009 already found, plus `sqs` if Karpenter's interruption queue is used and `ssm` and `eks` from Karpenter's private-cluster guide.
- **#23 (compute topology).** Serialized runs times N datasets versus the 24 h freshness objective; #1118 versus tile size; the missing #1127 cluster benchmark, which is a maintainer-run task in the library repo and would replace the single-machine-derived range above; scPDSI timing.
- **E1 spec.** A dev-environment existence schedule; Karpenter host choice; EKS upgrade cadence tied to the 14-month standard-support window; a cost-allocation tag check (ADR-0005 says an untagged resource is a defect).
- **E3 or E5 spec.** A version-retention and lifecycle policy for Publish versions; without it storage is the only line that grows unattended.
- **M2 spec.** Measure the Dagster, kube-prometheus-stack, and Argo CD pod requests on a real cluster before fixing node size ([#27](https://github.com/climate-indices/climate-indices-cloud/issues/27): "Requests are sized before M2"); this report supplies only the dollar sensitivity.
- **Possible fog:** the Spark/EMR comparison stretch (E3) and the public Athena surface (#22) have no cost model at all.

## Sources consulted

**AWS Price List bulk files** (`https://pricing.us-east-1.amazonaws.com/offers/v1.0/aws/<service>/current/us-east-1/index.json`), retrieved 2026-09-25; file publication dates: AmazonEC2 2026-09-24, AmazonCloudWatch 2026-09-22, AmazonEKS and AmazonS3 2026-09-18, AmazonVPC 2026-09-17, AmazonSNS 2026-09-15, awswaf 2026-09-14, AWSELB / AWSGlue / AWSSecretsManager / AmazonECR / AmazonECS / AmazonAthena 2026-09-11; AmazonCloudFront (global file) 2026-09-16.

**AWS pages and docs**

- [EKS pricing](https://aws.amazon.com/eks/pricing/): standard $0.10, extended $0.60 per cluster-hour; 14 months of standard support then 12 of extended.
- [WAF pricing](https://aws.amazon.com/waf/pricing/) and the WAF developer guide for the [Core rule set](https://docs.aws.amazon.com/waf/latest/developerguide/aws-managed-rule-groups-baseline.html) (700 WCU), [Amazon IP reputation list](https://docs.aws.amazon.com/waf/latest/developerguide/aws-managed-rule-groups-ip-rep.html) (25 WCU), and [rate-based rules](https://docs.aws.amazon.com/waf/latest/developerguide/waf-rule-statement-type-rate-based.html) (2 WCU base).
- [CloudFront pay-as-you-go pricing](https://aws.amazon.com/cloudfront/pricing/pay-as-you-go/).
- [Deploy private clusters with limited internet access](https://docs.aws.amazon.com/eks/latest/userguide/private-clusters.html) (endpoint list).
- [EKS best practices: Karpenter](https://aws.github.io/aws-eks-best-practices/karpenter/) and the [Karpenter getting-started guide](https://karpenter.sh/docs/getting-started/getting-started-with-karpenter/) and [settings](https://karpenter.sh/docs/reference/settings/) (`ISOLATED_VPC` disables on-demand pricing lookups; `INTERRUPTION_QUEUE`).
- [Spot Instance Advisor data](https://spot-bid-advisor.s3.amazonaws.com/spot-advisor-data.json) (savings percentage and interruption band per instance type).
- [AWS VPC CNI max-pods table](https://github.com/aws/amazon-vpc-cni-k8s/blob/master/misc/eni-max-pods.txt).

**Library (`monocongo/climate_indices`)**

- [`benchmarks/README.md`](https://github.com/monocongo/climate_indices/blob/main/benchmarks/README.md): #1121 CONUS nClimGrid results, #1127 EC2 runbook ("Pending the maintainer's cluster run").
- `benchmarks/results/nclimgrid_spi6_gamma_xarray.txt`, `nclimgrid_spi6_cli.txt`, `nclimgrid_fixture_provenance.txt`.
- [Issue #1118](https://github.com/monocongo/climate_indices/issues/1118) (open at retrieval).

**This repository:** [ADR-0001](../adr/0001-two-layouts-for-published-data.md), [0003](../adr/0003-serving-on-eks-and-no-nat.md), [0004](../adr/0004-terraform-owns-aws-argocd-owns-the-cluster.md), [0005](../adr/0005-one-account-two-environments-with-a-ceiling.md), [0006](../adr/0006-spi-calibrates-pearson-iii-on-a-fixed-1895-2022-window.md), [0007](../adr/0007-in-cluster-prometheus-cloudwatch-for-logs-and-aws-native-alarms.md), [0008](../adr/0008-point-reads-come-from-a-derived-series-store-and-cache-by-grid-cell.md), [0009](../adr/0009-dagster-oss-orchestrates-the-pipeline.md); [`CONTEXT.md`](../../CONTEXT.md); the resolution comments on tickets [#18](https://github.com/climate-indices/climate-indices-cloud/issues/18), [#19](https://github.com/climate-indices/climate-indices-cloud/issues/19), [#20](https://github.com/climate-indices/climate-indices-cloud/issues/20), and [#27](https://github.com/climate-indices/climate-indices-cloud/issues/27); the capstone brief's cost section.
