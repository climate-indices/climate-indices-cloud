# nClimGrid on AWS: Research Findings

**Date:** 2026-09-08  
**Ticket:** [#3](https://github.com/monocongo/climate_indices-cloud/issues/3)

## Summary

NOAA's Monthly U.S. Climate Gridded Dataset (nClimGrid) is available on AWS as a public dataset with no access charges. The dataset provides four climate variables (precipitation, average/max/min temperature) on a 1/24° grid (~5km resolution) covering CONUS from 1895 to present. Data is available both as consolidated NetCDF4 files (full period of record) and as individual monthly text files. New monthly data typically appears within 1-2 weeks after month end, with SNS notifications available. The dataset undergoes annual revision where preliminary data is replaced with final quality-controlled versions approximately one year later. Data is free to read with standard AWS egress charges only; full historical backfill is ~6.7 GB across all four variables.

**M1 Recommendation:** Use consolidated NetCDF4 files from AWS S3 (`noaa-nclimgrid-monthly-pds` bucket) with SNS subscription for new-object notifications. Ingest monthly; subset spatially during read if testing with tracer-bullet grid.

## Source and Access Paths

### AWS Open Data (Primary M1 source)

**Bucket:** `noaa-nclimgrid-monthly-pds`  
**Region:** `us-east-1`  
**Access:** Public, no AWS account required (`--no-sign-request`)  
**SNS Topic (new objects):** `arn:aws:sns:us-east-1:123901341784:NewNClimGridMonthlyObject`

**Source:** [AWS Open Data Registry - NOAA nClimGrid](https://registry.opendata.aws/noaa-nclimgrid/)

### NCEI Direct Access (Secondary/verification)

**HTTPS/THREDDS:** `https://www.ncei.noaa.gov/data/nclimgrid-monthly/access/`  
**Documentation:** `https://www.ncei.noaa.gov/data/nclimgrid-monthly/doc/gridded-readme.txt`  
**Metadata:** [ISO 19115-2 record](https://www.ncei.noaa.gov/access/metadata/landing-page/bin/iso?id=gov.noaa.ncdc:C00332)

**Source:** [NCEI nClimGrid Product Page](https://www.ncei.noaa.gov/products/land-based-station/us-climate-gridded-dataset)

## Format and Variables

### NetCDF4 Files (Consolidated Period of Record)

Four files, one per variable:
- `nclimgrid_prcp.nc` — precipitation (1.67 GB)
- `nclimgrid_tavg.nc` — average temperature (1.52 GB)
- `nclimgrid_tmax.nc` — maximum temperature (1.53 GB)
- `nclimgrid_tmin.nc` — minimum temperature (1.61 GB)

**Total size:** 6.69 GB (all four variables, 1895–present)

**Structure:** Time-series NetCDF with monthly time steps appended as new data becomes available.

### Point Text Files (Individual Months)

**Filename pattern:** `YYYYMM.{elem}.conus.pnt`  
Where `elem` ∈ {`prcp`, `tave`, `tmax`, `tmin`}

**Format:**
```
Field 1: Latitude (decimal degrees)
Field 2: Longitude (decimal degrees)
Field 3: Month value
```

**Size per month (CONUS):** ~13 MB per variable, ~52 MB for all four

### Units and Precision

- **Temperature** (`tave`, `tmax`, `tmin`): degrees Celsius × 100 (i.e., stored as integer hundredths)
- **Precipitation** (`prcp`): millimeters × 100 (i.e., stored as integer hundredths)
- **Non-land cells:** Filled with NaN

**Source:** [NCEI gridded-readme.txt](https://www.ncei.noaa.gov/data/nclimgrid-monthly/doc/gridded-readme.txt)

## Grid

**Resolution:** 1/24° = 0.041667° (~5 km at mid-latitudes)  
**Dimensions:** 1385 (longitude) × 596 (latitude) = 825,460 grid cells  
**Coverage:** Continental United States (CONUS)  
**Approximate bounds:**
- Latitude: 24.8°N to 49.9°N
- Longitude: 125°W to 67°W

**Projection:** Regular lat/lon grid (WGS84 implied, typical for NOAA gridded products; exact datum not specified in accessed documentation)

**Temporal constancy:** Grid geometry is fixed; cell definitions do not change over time.

**Source:** [NCEI gridded-readme.txt](https://www.ncei.noaa.gov/data/nclimgrid-monthly/doc/gridded-readme.txt)  
*Note: readme explicitly states "The 1385x596 grid covers CONUS but the non-land points are filled with NaN."*

## History and Revisions

### Historical Depth

**Period of record:** January 1895 to present (continuously updated)

**Source dataset:** Derived from GHCN-D (Global Historical Climatology Network – Daily) station observations, gridded using statistical interpolation.

### Versioning and Revisions

**Preliminary data:** New monthly files are published initially as "preliminary" within 1-2 weeks of month end (exact latency not documented; inferred from file timestamps).

**Final data:** Approximately one year after initial publication, preliminary data is replaced with "final" quality-controlled data. The annual replacement process updates the prior year's 12 months.

**Implication for M1:** Pipeline must tolerate in-place updates to past months. Zarr compaction or versioned object keys recommended to avoid data integrity issues during backfills.

**Source:** [AWS Open Data Registry description](https://registry.opendata.aws/noaa-nclimgrid/):
> "On an annual basis, approximately one year of 'final' nClimGrid will be submitted to replace the initially supplied 'preliminary' data for the same time period. Users should be sure to ascertain which level of data is required for their research."

## Latency

**Update frequency:** Monthly

**Publication latency:** Not explicitly documented in primary sources. Empirical evidence from file timestamps suggests preliminary data typically appears within **1-2 weeks** after month end. For example, August 2026 data files show a modification timestamp of September 8, 2026.

**Operational assumption for M1:** Budget 2-3 weeks latency for preliminary monthly data; final data lags by approximately 13 months.

**Source:** Inferred from `aws s3 ls` output (file timestamps) and [AWS Open Data Registry update frequency](https://registry.opendata.aws/noaa-nclimgrid/) ("Monthly").

## Notifications

### SNS Topic

**ARN:** `arn:aws:sns:us-east-1:123901341784:NewNClimGridMonthlyObject`  
**Region:** `us-east-1`  
**Event type:** S3 object creation notifications (new monthly files and NetCDF updates)

**Subscription pattern:**
1. Subscribe SQS queue or Lambda to SNS topic
2. Filter messages by object key prefix if needed (e.g., `.nc` files only)
3. Trigger ingest pipeline on notification

**No polling required.** Event-driven architecture fully supported.

**Source:** [AWS Open Data Registry - Resources section](https://registry.opendata.aws/noaa-nclimgrid/)

**Daily dataset note:** A separate SNS topic exists for daily nClimGrid data (`NewNClimGridDailyObject`), but M1 targets monthly indices only.

## Licence

**Type:** Open data, public domain (U.S. Government work)

**Terms:**
- Free to use for any purpose
- Attribution requested but not required
- Modifications must not be represented as original NOAA data
- No endorsement or affiliation with NOAA may be implied

**Verbatim from source:**
> "NOAA data disseminated through NODD are open to the public and can be used as desired. NOAA makes data openly available to ensure maximum use of our data, and to spur and encourage exploration and innovation throughout the industry. NOAA requests attribution for the use or dissemination of unaltered NOAA data. However, it is not permissible to state or imply endorsement by or affiliation with NOAA. If you modify NOAA data, you may not state or imply that it is original, unaltered NOAA data."

**Source:** [AWS Open Data Registry - License section](https://registry.opendata.aws/noaa-nclimgrid/)

**Redistribution:** Allowed. Derived products (e.g., computed SPI/SPEI from nClimGrid) are not restricted.

## Cost

### Read Operations

**S3 GET requests:** $0 (public dataset exception, `--no-sign-request` access)

### Data Transfer (Egress)

| Destination | Cost (per GB) | Full backfill (6.69 GB) |
|-------------|---------------|--------------------------|
| Within AWS us-east-1 (same region) | $0 | $0 |
| AWS to Internet (first 100 GB/month) | $0.09 | $0.60 |
| CloudFront to Internet (first 1 TB/month) | $0.085 | $0.57 |

**Single month (incremental):** ~52 MB (all four variables) → negligible cost (<$0.01)

**M1 strategy:**
- **Development/testing:** Run ingest in us-east-1 Lambda/Fargate → zero egress
- **Production:** Cache in S3 or CloudFront; egress only for API responses to end users
- **Backfill:** One-time $0.60 cost if computed outside AWS; $0 if run in us-east-1

**Source:** [AWS S3 Pricing](https://aws.amazon.com/s3/pricing/) (standard public dataset access model)

## Recommendation for M1

### Use NetCDF Files from AWS

**Rationale:**
1. **Complete history in single object:** No per-month file retrieval loop
2. **SNS notifications:** Real-time awareness of updates without polling
3. **Zero-cost same-region access:** Ingest in us-east-1 Lambda/Fargate
4. **NetCDF subsetting:** Read spatial slices (region of interest) without full download using libraries like `xarray` + `h5netcdf` or `zarr` with remote access
5. **Tracer-bullet friendly:** Subset grid at read time for M1 validation

### Ingest Pipeline Sketch

1. **Subscribe SQS to SNS:** `arn:aws:sns:us-east-1:123901341784:NewNClimGridMonthlyObject`
2. **Filter:** NetCDF updates only (`.nc` suffix)
3. **Lambda trigger:** On new SQS message, fetch updated NetCDF via S3 API
4. **Read:** Use `xarray.open_dataset()` with S3 remote access (`s3fs` backend)
5. **Compute:** Run `climate_indices` SPI/SPEI calculations
6. **Write:** Store results to Zarr in project S3 bucket
7. **Validate:** Compare against nClimDiv known values (first few months)

### Preliminary vs. Final Data

**For M1 (tracer bullet):** Use preliminary data as-is. Defer handling of annual revisions to M2/M3 epic (versioning strategy).

**For production:** Implement either:
- **Optimistic locking:** Zarr version keys, recompute indices if base data changes
- **Snapshot isolation:** Store monthly snapshots of input data; never update past months in output
- **Hybrid:** Preliminary data overwrites; final data freezes (flag in metadata)

## Open Questions

### 1. Exact datum/projection string

**Question:** NetCDF CF conventions attribute for grid mapping? WGS84 assumed but not confirmed.

**Action:** Download a sample NetCDF and inspect global attributes / coordinate variables (`lat`, `lon` CRS metadata).

**Workaround for M1:** Treat as WGS84 geographic; validation against nClimDiv will expose any mismatch.

### 2. NetCDF internal chunking

**Question:** How are the NetCDF4 files chunked? Optimal access pattern (time-slice vs. spatial-slice)?

**Action:** Inspect chunk cache settings with `ncdump -sh` or `h5ls`.

**Impact:** Determines whether reading single months (time slice) is efficient or requires scanning entire file.

### 3. SNS message schema

**Question:** What fields are present in SNS notifications? (S3 object key, size, timestamp?)

**Action:** Subscribe a test SQS queue and capture sample message.

**Impact:** Lambda filtering logic and retry/idempotency design.

### 4. Publication calendar

**Question:** Which day of the month does new data typically appear? (Affects SLO for data freshness.)

**Action:** Monitor SNS notifications for 2-3 months; log timestamps.

**Impact:** User-facing documentation ("indices updated by day X of each month").

### 5. Daily dataset relevance

**Question:** Does `climate_indices` (3.0+) support daily inputs for monthly indices, or is monthly aggregation required first?

**Action:** Review `climate_indices` [CHANGELOG](https://github.com/monocongo/climate_indices/blob/main/CHANGELOG.md) and API docs.

**Impact:** If daily inputs supported, `noaa-nclimgrid-daily-pds` bucket may offer lower-latency pipeline.

### 6. Grid edge cells

**Question:** Are coastal/border cells full 1/24° squares, or are they partial-area weighted?

**Action:** Visual inspection of a `.pnt` file row count vs. expected (1385×596 = 825,460) or check for irregular grid metadata.

**Impact:** Precipitation totals and area-averaging logic; affects validation against divisional data.

---

**Primary sources accessed:**
- https://registry.opendata.aws/noaa-nclimgrid/
- https://www.ncei.noaa.gov/data/nclimgrid-monthly/doc/gridded-readme.txt
- https://www.ncei.noaa.gov/products/land-based-station/us-climate-gridded-dataset
- AWS S3 bucket inspection: `s3://noaa-nclimgrid-monthly-pds/`

**Sources not retrieved (cited by NCEI but not directly accessed):**
- Vose, R. S., et al. (2014). *Improved Historical Temperature and Precipitation Time Series for U.S. Climate Divisions.* Journal of Applied Meteorology and Climatology. [DOI not confirmed; metadata landing page unreachable via direct fetch.]
