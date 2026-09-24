# climate-indices-cloud

An open, validated drought and wildfire-danger indices service for the continental
US (CONUS). Ingests NOAA gridded observations from AWS open data, computes SPI, SPEI,
EDDI, percentage of normal, the Palmer family, and the wildfire index family with
[`climate-indices`](https://github.com/monocongo/climate_indices) `>=3.0,<4`, and
publishes analysis-ready Zarr, Cloud-Optimized GeoTIFFs, and Iceberg tables through a
public API and map site.

Two purposes at once: a portfolio piece demonstrating production data engineering,
cloud infrastructure, DevOps/SRE, and AI-assisted delivery; and a real, free public
service. Optimize for production realism, low steady-state cost, and clear evidence
over feature count.

**Status:** planning. The delivery plan lives in the
[`cloud-native` project board](https://github.com/users/monocongo/projects/11) and the
wayfinder map issue. The scope proposal is [docs/capstone/brief.md](docs/capstone/brief.md).

**Not for operational decisions.** Every published dataset is validated against the
compute engine's documented evidence before release; see
[`climate_indices` VALIDATION.md](https://github.com/monocongo/climate_indices/blob/main/VALIDATION.md).

## Layout

```text
pipelines/   ingestion, analysis-ready storage, index compute, validation gates
api/         FastAPI service
infra/       Terraform (dev and prod)
site/        static map site
metrics/     delivery-telemetry records (runs.jsonl and derived tables)
docs/        capstone brief, ADRs, agent guides
```

Nothing here is implemented yet; the plan is being charted first.
