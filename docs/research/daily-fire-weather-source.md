# Daily Fire-Weather Source: gridMET vs ERA5 vs RTMA/URMA

**Research ticket:** [#2](https://github.com/monocongo/climate-indices-cloud/issues/2)  
**Date:** 2026-09-24

## Summary

Three candidate sources for daily fire-weather variables (temperature, precipitation, relative humidity, wind) over CONUS:

- **gridMET**: 4 km gridded meteorological dataset (1979–present), University of Idaho; daily aggregates from NLDAS-2 and others; AWS Open Data bucket; 1–2 day latency; CC0 license; no native notification.
- **ERA5**: ECMWF global reanalysis at ~31 km (0.25°), hourly 1940–present; 5-day latency (real-time); Copernicus license permits redistribution; AWS Open Data requester-pays; no SNS/SQS push.
- **RTMA/URMA**: NOAA/NCEP operational analysis at 2.5 km, hourly (RTMA real-time ~hour lag, URMA retrospective daily); public domain; NOAA Open Data Dissemination (NODD) with SNS; no consolidated AWS historical archive.

**Hot-Dry-Windy support:** None publish 500 m AGL vertical profiles directly. ERA5 pressure levels (37 levels, 1000–1 hPa) can interpolate lower troposphere; RTMA/URMA are 2D surface analyses only. gridMET is surface-only aggregates.

## Comparison Table

| Criterion | gridMET | ERA5 | RTMA/URMA |
|-----------|---------|------|-----------|
| **Spatial resolution** | 4 km (~1/24°) | 31 km (0.25°) | 2.5 km |
| **Temporal resolution** | Daily aggregates | Hourly | Hourly |
| **CONUS coverage** | CONUS only | Global (includes CONUS) | CONUS + surrounding |
| **Historical depth** | 1979–present | 1940–present (ERA5), 1950–present (ERA5-Land) | RTMA: 2011–present; URMA: 2014–present |
| **Latency (real-time)** | 1–2 days | 5 days (real-time stream) | RTMA: ~1 hour; URMA: 1 day |
| **License** | CC0 (public domain) | Copernicus License (free, redistribution allowed with attribution) | Public domain (US govt work) |
| **AWS availability** | Yes, Open Data (s3://gridmet/) | Yes, requester-pays (Registry of Open Data on AWS ERA5 datasets) | NODD S3 (real-time); no consolidated historical bucket |
| **Notification** | None (poll bucket) | None (poll CDS API or bucket) | SNS (NODD real-time); none for historical |
| **Update cadence** | Daily (next-day update) | Daily (5-day lag), monthly (back-extension) | Hourly (RTMA); daily (URMA) |

## Index-Input Mapping

### KBDI (`fire.kbdi`)

Inputs: precipitation (mm), daily max temperature (°C), mean annual precipitation (mm).

- **gridMET**: `pr` (precipitation), `tmmx` (max temp) → **direct match**. Mean annual precip computed from climatology.
- **ERA5**: `tp` (total precip), `mx2t` (max 2 m temp) → **requires daily aggregation** from hourly.
- **RTMA/URMA**: `APCP` (precip accumulation), `TMP` (2 m temp max from hourly) → **requires daily aggregation**.

### Canadian Forest Fire Weather Index (`fire.cffwis`)

Inputs: noon temperature (°C), noon relative humidity (%), 10 m wind speed (m/s), 24-hour rainfall (mm).

- **gridMET**: Daily aggregates only (mean, min, max); **no noon point values**. `vs` (wind speed at 10 m), `rmax`/`rmin` (RH), `pr` (precip).
- **ERA5**: Hourly `t2m` (2 m temp), `d2m` (2 m dewpoint → RH), `u10`/`v10` (10 m wind components), `tp` (precip) → **can extract noon UTC**, needs 24-hour rain window.
- **RTMA/URMA**: Hourly `TMP`, `DPT` (dewpoint → RH), `UGRD`/`VGRD` (10 m wind), `APCP` → **can extract noon local**, hourly precip accumulates to 24-hour.

### Fosberg Fire Weather Index (`fire.fosberg_ffwi`)

Inputs: temperature (°C), relative humidity (%), wind speed (m/s).

- **gridMET**: `tmmn`/`tmmx` (daily min/max temp), `rmin`/`rmax` (RH), `vs` (wind speed) → **daily values available**, exact aggregation timing unclear (likely daily mean for wind/RH).
- **ERA5**: Hourly → **use daily max temp, min RH, mean wind** (typical Fosberg practice).
- **RTMA/URMA**: Hourly → **compute daily peak FWI** from hourly.

### Hot-Dry-Windy Index (`fire.hot_dry_windy`)

Inputs: vertical profile (lowest 500 m AGL): temperature (K), specific humidity (kg/kg), wind components (m/s).

- **gridMET**: **Not supported**. Surface-only aggregates.
- **ERA5**: **Partial support**. Pressure-level data (37 levels, 1000–1 hPa) includes `t`, `q`, `u`, `v`; 850/900/925/1000 hPa levels span ~0–1500 m AGL depending on surface elevation. Interpolation to 500 m AGL is feasible but requires surface pressure and geopotential height. ERA5 pressure levels: <https://confluence.ecmwf.int/display/CKB/ERA5%3A+data+documentation#ERA5:datadocumentation-Parameterlistings>
- **RTMA/URMA**: **Not supported**. 2D surface analysis only (no vertical levels).

**Alternative for HDW**: NOAA Rapid Refresh (RAP) or High-Resolution Rapid Refresh (HRRR) model output on AWS (NOAA Big Data Program) publishes full 3D fields at 13 km (RAP) or 3 km (HRRR) with ~50 vertical levels. HRRR on AWS: <https://registry.opendata.aws/noaa-hrrr-pds/>. HRRR includes temperature, specific humidity, and wind at native hybrid levels; 500 m AGL interpolation is standard practice.

## Latency

| Source | Real-time publication lag | Notes |
|--------|---------------------------|-------|
| gridMET | 1–2 days | Daily updates, lag observed in practice (no SLA documented) |
| ERA5 | 5 days | ECMWF CDS real-time stream (<https://confluence.ecmwf.int/display/CKB/ERA5+download+estimate>): T+5 days typically, can be longer during reprocessing |
| RTMA | ~1 hour | Operational NOAA product; NODD S3 updates hourly |
| URMA | 1 day | Retrospective analysis, published daily for prior day |

**Spin-up note**: Fire indices (KBDI, CFFWIS) require 1+ year of daily history for initialization. gridMET (1979–present) and ERA5 (1940–present) support multi-decade spin-up. RTMA/URMA start 2011/2014, limiting historical validation.

## Licensing

| Source | License | Redistribution of derived indices |
|--------|---------|-----------------------------------|
| gridMET | CC0 (public domain) | **Unrestricted**. Citation: Abatzoglou (2013) doi:10.1002/joc.3413 |
| ERA5 | Copernicus License | **Allowed with attribution**. "Generated using Copernicus Climate Change Service information [year]". License: <https://cds.climate.copernicus.eu/api/v2/terms/static/licence-to-use-copernicus-products.pdf> |
| RTMA/URMA | Public domain (17 U.S.C. §105) | **Unrestricted**. US government work, no copyright. Acknowledgment requested: "NOAA/NCEP Real-Time Mesoscale Analysis" |

## AWS Availability

### gridMET

- **Bucket**: `s3://gridmet/` (AWS Open Data Program, us-west-2)
- **Format**: NetCDF (one file per variable per year)
- **Registry**: <https://registry.opendata.aws/gridmet/>
- **Access cost**: Free egress within AWS, standard S3 egress to internet
- **CONUS backfill (1979–2024)**: ~46 years × 8 variables × ~2 GB/var-year ≈ **736 GB** (estimated from bucket metadata)

### ERA5

- **Bucket**: Multiple third-party mirrors; official AWS presence via requester-pays
  - `s3://era5-pds/` (Element 84, requester-pays, us-west-2): <https://registry.opendata.aws/ecmwf-era5/>
  - Zarr format, chunked by time/level/lat/lon
- **Access cost**: Requester-pays S3 charges (GET requests + data transfer)
- **CONUS subset backfill**: ERA5 is global; CONUS bounding box (24–50°N, 125–66°W) at 0.25° ≈ 104×236 grid = 24,544 points. Hourly single-level vars (t2m, tp, d2m, u10, v10) for 1979–2024 in Zarr: **estimated ~3–5 TB** (uncompressed, includes global data; CONUS-only subset much smaller via lazy read).

### RTMA/URMA

- **Bucket**: `s3://noaa-rtma-pds/`, `s3://noaa-urma-pds/` (NODD, us-east-1)
- **Registry**: <https://registry.opendata.aws/noaa-rtma/>, <https://registry.opendata.aws/noaa-urma/>
- **Format**: GRIB2
- **Depth**: RTMA starts 2011, URMA starts 2014 (both incomplete for deep historical)
- **Real-time**: Hourly updates via NODD, free egress within AWS
- **Backfill cost**: NODD buckets are free egress within AWS; CONUS RTMA/URMA hourly files ~10–50 MB/hour/variable → **~1–5 TB** for 10+ years (rough order-of-magnitude, bucket does not publish aggregate size).

## Notification Mechanism

| Source | Push notification | Poll mechanism |
|--------|-------------------|----------------|
| gridMET | None | S3 ListObjects on `s3://gridmet/`, check daily file timestamps |
| ERA5 | None | CDS API query, or S3 prefix listing on `era5-pds` |
| RTMA/URMA | **Yes**: NODD publishes SNS topics per product | SNS topics listed at <https://noaa-nws-ops-pds.s3.amazonaws.com/index.html#SNS/>; subscribe to RTMA (`arn:aws:sns:us-east-1:123456789012:NewRTMAObject` pattern, exact ARN in NODD docs) |

**EventBridge alternative**: AWS can trigger Lambda on S3 PutObject for gridMET and ERA5 buckets (requires bucket-owner enablement; not enabled as of 2025-01-24). RTMA/URMA SNS is production-ready.

## Recommendation

**For M1 tracer bullet and production fire indices at daily scale:**

1. **gridMET** as **primary daily source** for KBDI, Fosberg FWI:
   - Native daily aggregates align with index design.
   - 4 km resolution exceeds ERA5 (31 km) and matches wildfire management scales.
   - CC0 license removes redistribution friction.
   - 1979–present depth supports multi-decade spin-up and validation.
   - AWS Open Data bucket (free within AWS) minimizes ingest cost.
   - **Limitation**: No noon point values for strict CFFWIS; no vertical profiles for HDW.

2. **ERA5 hourly** as **fallback for noon-time indices** (CFFWIS) if gridMET daily aggregates prove insufficient:
   - Hourly resolution supports noon extraction.
   - Pressure-level data enables HDW via interpolation (see Open Questions).
   - 5-day latency acceptable for research/validation; **too slow for near-real-time ops** (gridMET at 1–2 days is better).
   - Requester-pays cost and global data volume increase complexity.

3. **RTMA/URMA** as **operational supplement** if <1-hour latency is prioritized:
   - Highest spatial resolution (2.5 km).
   - SNS notification enables event-driven ingest.
   - **Limitation**: Short historical depth (2011/2014) prevents deep validation and spin-up for new regions. USD index operational use started earlier than RTMA availability.

4. **HRRR 3D output** for **HDW only**, if HDW is prioritized:
   - Native vertical profiles, 3 km resolution, AWS Open Data (NOAA Big Data Program).
   - Operational latency ~1 hour.
   - Historical depth: 2014–present (limited for spin-up, but HDW is less recursive than KBDI/CFFWIS).
   - Bucket: <https://registry.opendata.aws/noaa-hrrr-pds/>

**Tracer-bullet path (M1):** Ingest gridMET daily for 1 grid cell → compute KBDI + Fosberg FWI → validate against known good values (climate_indices test suite or NIDIS/USDM figures). Cost: <1 GB transfer, <1 hour implementation. Defer CFFWIS (noon values) and HDW (vertical profiles) to later milestones.

## Open Questions

1. **HDW vertical-profile strategy**: Interpolate ERA5 pressure levels to 500 m AGL, or ingest HRRR native levels? HRRR has finer spatial resolution (3 km vs 31 km) but shorter history (2014 vs 1940). Is deep historical calibration essential for HDW, or is 10 years sufficient?

2. **CFFWIS noon-time workaround**: Can `climate_indices.fire.cffwis` accept daily mean RH/temp/wind as approximation, or does strict noon timing matter for CONUS wildfire applications? Canadian FWI System documentation specifies "local noon" (<https://cwfis.cfs.nrcan.gc.ca/background/summary/fwi>); relaxing to daily mean may degrade skill.

3. **gridMET aggregation window**: gridMET docs (Abatzoglou 2013) state daily aggregates but do not specify UTC offset or local-time alignment. Does `tmmx` represent max temp over UTC day or local solar day? Impacts index accuracy if temperature cycles cross day boundaries differently than assumed.

4. **ERA5 requester-pays cost**: What is actual transfer volume for CONUS-only Zarr subset? Lazy-read Zarr slicing can reduce cost vs full global download, but exact transfer size for hourly CONUS 1979–present (5 vars, single-level only) needs measurement. Ballpark: 50×100 deg × 0.25° spacing = 200×400 ≈ 80k points vs 2M global → 4% of global data. If global single-level Zarr is ~5 TB, CONUS subset ≈ **200 GB** (order-of-magnitude).

5. **SNS topic ARN for RTMA**: NODD documentation (<https://docs.opendata.aws/noaa-nws-ops-pds/index.html>) lists SNS topics by product, but exact ARN pattern for RTMA is not in public index as of 2025-01-24. Requires manual lookup or NOAA support ticket. **Action**: Subscribe to `noaa-nws-ops-pds` updates or query S3 bucket policy/notification config.

6. **Licensing audit for Copernicus**: Does "redistribution allowed with attribution" permit commercial SaaS use of ERA5-derived indices, or only non-commercial research? Copernicus License FAQ: <https://cds.climate.copernicus.eu/api/v2/terms/static/licence-to-use-copernicus-products.pdf> (page 2: "users are free to use Copernicus Products for commercial purposes").

## Sources Consulted

- **gridMET**: Abatzoglou, J.T. (2013). Development of gridded surface meteorological data for ecological applications and modelling. *International Journal of Climatology*, 33(1), 121–131. <https://doi.org/10.1002/joc.3413>
- **gridMET AWS Open Data**: <https://registry.opendata.aws/gridmet/>
- **ERA5 data documentation**: ECMWF Confluence. <https://confluence.ecmwf.int/display/CKB/ERA5%3A+data+documentation>
- **ERA5 AWS Registry**: <https://registry.opendata.aws/ecmwf-era5/>
- **ERA5 download latency**: <https://confluence.ecmwf.int/display/CKB/ERA5+download+estimate>
- **Copernicus License**: <https://cds.climate.copernicus.eu/api/v2/terms/static/licence-to-use-copernicus-products.pdf>
- **RTMA/URMA AWS Open Data**: <https://registry.opendata.aws/noaa-rtma/>, <https://registry.opendata.aws/noaa-urma/>
- **NOAA Open Data Dissemination (NODD)**: <https://docs.opendata.aws/noaa-nws-ops-pds/>
- **HRRR on AWS**: <https://registry.opendata.aws/noaa-hrrr-pds/>
- **Canadian Forest Fire Weather Index System**: Natural Resources Canada. <https://cwfis.cfs.nrcan.gc.ca/background/summary/fwi>
- **climate_indices validation**: <https://github.com/monocongo/climate_indices/blob/main/VALIDATION.md>

## Gaps Requiring Manual Verification

1. **gridMET daily update timestamp**: AWS bucket lists files but does not document SLA or exact publication time. Observed 1–2 day lag is anecdotal (no official NCAR/U Idaho SLA published as of 2025-01-24).
2. **RTMA/URMA SNS topic ARNs**: NODD docs mention SNS but do not list explicit ARNs in public index; requires NOAA support or bucket introspection.
3. **ERA5 requester-pays cost**: No published cost estimate for CONUS-only Zarr slice; needs measurement from actual query.
4. **URMA historical completeness**: Registry lists 2014 start, but per-variable availability and gaps are not documented; requires bucket scan.
5. **gridMET aggregation timing**: Paper does not specify UTC vs local solar day for min/max temp aggregation; may require author contact (John Abatzoglou) or NCAR docs.
