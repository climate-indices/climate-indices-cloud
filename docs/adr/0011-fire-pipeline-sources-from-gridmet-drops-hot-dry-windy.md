# Fire-danger indices source from gridMET alone; Hot-Dry-Windy drops out of scope

KBDI, Fosberg, and CFFWIS all compute from gridMET's own daily fields (`tmmx`, `rmin`/`rmax`,
`vs`, `pr`); Hot-Dry-Windy needs a vertical profile in the lowest 500 m AGL that none of the
sources [#2](https://github.com/climate-indices/climate-indices-cloud/issues/2)'s research
compared provide directly.
[#21](https://github.com/climate-indices/climate-indices-cloud/issues/21) settles what each of
these four indices actually ships with, closing the two questions that research left open.

KBDI and Fosberg need nothing beyond gridMET — both take only surface fields gridMET already
carries; this was never contested.

CFFWIS needs noon-local temperature, RH, 10 m wind, and 24-hour precipitation
([`cffwis()`](https://github.com/monocongo/climate_indices/blob/main/src/climate_indices/fire/_cffwis.py),
confirmed against source, not just its docstring). No current AWS-hosted ERA5 mirror can supply
that on a daily cadence: `era5-pds` is deprecated, its maintained successor `nsf-ncar-era5`
updates monthly with a 3–4 month lag, and Icechunk ERA5's forward-currency is unverified. None of
that turns on [ADR-0003](0003-serving-on-eks-and-no-nat.md)'s no-NAT posture — every option here
is plain S3, no NAT needed — the blocker is staleness, not egress. Since `cffwis()` only *warns*
(does not reject) when its input isn't sampled at noon, CFFWIS ships computed from gridMET's own
daily aggregates as a noon approximation, published under the `characterization-only` evidence
class ([ADR-0002](0002-validation-as-a-publishing-gate.md)) rather than under a claim of true
noon fidelity.

Hot-Dry-Windy is out of scope. The compute engine does implement it (`hot_dry_windy()`; the
[daily-fire-weather-source research](https://github.com/climate-indices/climate-indices-cloud/blob/research/daily-fire-weather-source/docs/research/daily-fire-weather-source.md)
only checked data-source availability, not the engine, and missed this), so the gap is entirely
the vertical-profile input: HRRR is confirmed AWS-accessible (`noaa-hrrr-bdp-pds`, plain S3,
archive since 2014) but has no single "lowest 500 m AGL" field — the surface product gives 2 m RH
and 10 m wind, the native-level product gives wind and specific humidity across 50 hybrid
levels, and getting a true boundary-layer profile out of either means deriving RH from specific
humidity plus temperature and pressure, then selecting levels by geopotential height. That is a
bespoke GRIB2 ingestion pipeline for one secondary index, disproportionate to a project
optimizing for production realism over feature count. No replacement index is substituted.

## Considered options

**CFFWIS sourcing**

- **Approximate noon values from gridMET (adopted).** No second source, no added latency,
  disclosed as `characterization-only`. Loses true noon fidelity.
- **Add `nsf-ncar-era5` for true noon values.** Rejected: a 3–4 month publication lag makes it
  unusable for anything called "daily"; it would need its own delayed sub-pipeline for one index.
- **Ship without CFFWIS.** Rejected: gridMET's approximation is available today at no extra
  engineering cost, and `characterization-only` already exists as the honest label for it.

**Hot-Dry-Windy**

- **Drop from scope (adopted).** No new source, no new pipeline.
- **Build an HRRR ingestion and derivation pipeline.** Rejected for now: real engineering (GRIB2
  parsing, RH derivation, geopotential-height level selection) for one index the brief doesn't
  hinge on. Revisit if HDW becomes load-bearing later.
- **Approximate from a 2 m/10 m surface proxy.** Rejected: misrepresents what HDW measures (max
  VPD × wind over an actual vertical profile), which is worse than not shipping it.

## Consequences

- **Spin-up.** The compute engine ships a recursive `spin_up` state machine for KBDI and CFFWIS
  but defaults it to 0 and declines to recommend a length ("no universal nonzero default is
  scientifically justified" —
  [the engine's ADR-0006](https://github.com/monocongo/climate_indices/blob/main/docs/adr/0006-fire-recursive-state-and-execution.md)).
  This project adopts a flat one-year buffer before each cell's usable start date, applied
  uniformly rather than tuned per local wet season.
- **Backfill depth.** The daily pipeline collects forward from its M3 launch date plus the
  one-year spin-up buffer; it does not reprocess gridMET's full 1979–present record. Matches
  M1's SPI tracer bullet, which also ships a `latest`-only endpoint with no historical backfill.
- **Trigger.** A plain daily schedule, not
  [ADR-0009](0009-dagster-oss-orchestrates-the-pipeline.md)'s hourly S3-manifest polling sensor
  built for nClimGrid. gridMET publishes no notification either, but its ~1–2 day lag is steady,
  not unpredictable, so the sensor pattern solves a problem this source doesn't have.
- **Fire family boundary.** Whether Haines or any index beyond KBDI/CFFWIS/Fosberg is in scope
  stays open (the map's Not yet specified); this decision only resolves CFFWIS and HDW.
- Not verified: gridMET's own UTC-vs-local-day aggregation window (flagged by #2's research as
  needing author contact). This decision proceeds without it since the CFFWIS approximation is
  already disclosed as `characterization-only`.
