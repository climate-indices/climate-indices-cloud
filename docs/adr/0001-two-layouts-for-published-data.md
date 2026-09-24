# Published data is stored in two layouts: a compute-optimized Zarr store and a derived serve surface

`climate_indices` 3.x requires the time dimension to be one unbroken Dask chunk on any
compute input ([library ADR-0003](https://github.com/monocongo/climate_indices/blob/main/docs/adr/0003-dask-time-dimension-single-chunk.md)),
because distribution fitting and calibration need a cell's entire series in one place.
That constraint is about *compute*, not about *reading*. CONUS monthly nClimGrid is
825,460 cells over ~1,560 months, so a time-single-chunk Zarr tile is multi-megabyte: a
point time-series request would read it in full to return a few hundred values. We
therefore keep two layouts derived from one compute pass — `analysis/` and `published/`
Zarr stay compute-optimized (time as a single chunk, spatially tiled), and a **serve
surface** is derived alongside each publish for the readers that actually exist:
per-month Cloud-Optimized GeoTIFFs and GeoParquet for maps and latest-value queries,
Iceberg aggregate tables for division/county/HUC rollups, and the Zarr store itself for
bulk subset downloads. M1 builds only as much of the serve surface as its single
endpoint needs (a latest-month COG); the split is recorded now so M2–M4 fill in the
remainder instead of rediscovering the tension.

## Considered options

**One layout, two access patterns.** A single time-single-chunk Zarr store serves both
compute and the API. Simpler: one artifact, one provenance trail, one thing to version.
Rejected because every point and area read moves far more bytes than it returns — and
CloudFront cannot cache a partial-chunk read usefully — so the cost and latency penalty
lands on the public, most-used path forever, in exchange for saving one derived artifact.

## Consequences

- Every publish derives its serve surface from the same compute pass and must record that
  derivation in [output provenance](../../CONTEXT.md); the two layouts are never allowed to
  drift independently.
- Index outputs are path- and attribute-tagged with the calibration window
  (`published/<index>/<timescale>/cal<start>-<end>/`) because the same index computed over
  a different calibration period is a different published product, not a revision of one.
- Published Zarr uses **Zarr v2 with consolidated metadata** for now — the mature
  `xarray`/`zarr-python`/Dask path. Transactional, object-store-native versioning
  (`icechunk`, or Zarr v3) is revisited when it earns its keep; the first real candidate is
  handling nClimGrid's ~13-month preliminary→final revisions without republishing a whole
  store.
- Rechunking for serving is a derived-data concern. Compute code never rechunks the
  analysis store to satisfy a reader.
