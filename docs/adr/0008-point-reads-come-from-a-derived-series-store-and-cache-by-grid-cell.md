# Point reads come from a derived point-series store and are cached by grid cell at the edge

[ADR-0001](0001-two-layouts-for-published-data.md) derives a serve surface so that a point read
never pulls a calibration-sized chunk, but its list of readers has none for "every month at one
location", which is what the API's `series` route (M2) returns. Reading per-month COGs would
take about 1,560 range reads per request. A time-single-chunk Zarr tile is about 25.6 MB at
64×64 cells and about 1.6 MB at 16×16 (float32, uncompressed; the grid is 1385×596 cells over
about 1,560 months). We therefore derive a **point-series Zarr** at each Publish from the same
compute pass, chunked `[all months, 16, 16]` (about 3,300 chunks), and the API reads one chunk
per request. Public reads are also cached by CloudFront on the grid cell: a CloudFront Function
snaps `lat`/`lon` to the nearest cell before the cache key is built, so every caller in a cell
shares one entry, and each Publish invalidates `/v1/{index}/{timescale}/*`. One entry serves
every caller in a cell, so a response cannot echo the caller's coordinates: `requested{lat,lon}`
is dropped from the [M1 envelope](https://github.com/climate-indices/climate-indices-cloud/issues/18#issuecomment-5821779808)
and `cell{lat,lon}` is the authoritative location.

## Considered options

**Read the published Zarr directly, with small spatial tiles.** Fewer artifacts. Rejected
because ADR-0001 keeps published Zarr compute-optimized and never rechunked for a reader, so
this would reverse ADR-0001 instead of extending it.

**Per-month COG range reads.** Reuses the latest-value artifact. Rejected: about 1,560 requests
per series, against the 500 ms point-read SLO.

**Cache on the exact query string and keep `requested`.** Raw floats fragment the cache, so only
callers repeating identical coordinates would hit it. The site could snap client-side; API
callers could not.

**A short TTL with no invalidation.** Simpler. Rejected because it sends more traffic to the
origin and can serve stale data for up to a TTL after a Publish.

## Consequences

- A fourth serve-surface artifact per index, timescale, and Dataset Version. Its derivation is
  recorded in the run's provenance like the others, and it must never diverge from the
  Published Dataset. It holds a few GB per version; storage cost is small but was not measured.
- The M2 spec measures the `series` route's p95 against the 500 ms SLO ([#20](https://github.com/climate-indices/climate-indices-cloud/issues/20))
  and re-tiles the derived store if it misses. The tile size belongs to the serve surface, not
  to compute, so it can change without touching the analysis store.
- The snapping rule depends on the Upstream's grid. nClimGrid is a fixed 1/24° CONUS grid; a
  later Upstream on a different grid needs its own rule, so the Function is configured per
  route.
- Dropping `requested` changes a contract that was never exposed: M1's endpoint is private, so
  no client depends on it. After M4 the envelope is public under `/v1`.
- Invalidation is one wildcard path per index and timescale per Publish; the pricing page
  lists the first 1,000 paths per month as free (read 2026-09-24).
- Not verified: a CloudFront Function's execution time for the snapping arithmetic (the docs
  say "submillisecond" with no figure), and that a rewritten query string forms the cache key
  as documented. The spec confirms both before M4.
