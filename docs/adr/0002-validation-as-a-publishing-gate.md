# A publish is gated on reproducible checks plus reference agreement inside measured ceilings, and every release states its evidence class

The compute library's `VALIDATION.md` distinguishes *external scientific validation* from
*regression coverage*, and most indices sit somewhere in between: SPI is a characterization
against NCEI's climate-divisional product whose independent lineage cannot be confirmed and
whose actual calibration window differs from its documentation; EDDI is validated against
NOAA PSL on a single lat/lon subset; Palmer and scPDSI are regression-covered against
library-generated references; KBDI is reference-reproduced; CFFWIS matches NRCan on one
latitude band. There is no single certificate to inherit. The publishing gate therefore
blocks a release on three things it can actually prove — the library's committed fixture
suite still passing against the shipped engine, CONUS-wide agreement with each index's
operational reference staying inside the ceilings that library validation already measured,
and coverage/units/calendar checks passing on the published grid — and it refuses to let the
word "validated" stand in for evidence class. Each release publishes a machine-generated
validation report, and each per-index verdict names its class: `external-validated`,
`reference-reproduced`, or `characterization-only`. The API and site surface that class next
to the data.

## Considered options

**Gate on numeric agreement alone.** Cheaper, but it hides the difference between "we match
NCEI on all 344 divisions" and "we reproduce our own fixtures" — the exact conflation the
library's `VALIDATION.md` exists to prevent.

**Require true independent validation per index before any publish.** Most rigorous, but it
would block M1's SPI on research the library itself could not complete, and Palmer has no
independent reference in existence today; a gate nobody can pass is not a gate.

## Consequences

- Raising the evidence class of an index is a separate, publishable piece of work (it changes
  what the report claims), not a silent improvement in the same report.
- The gate needs, per index, a machine-readable record of its reference source, tolerance,
  and observed ceiling. Mirroring `VALIDATION.md` is the starting point; a published dataset
  with no ceiling recorded cannot be gated and therefore cannot ship.
- Tolerance values are inputs to the pipeline, not test constants — promoting VALIDATION.md's
  checks into "a pipeline gate that runs on every publish" means those numbers are versioned
  with the pipeline and cannot be relaxed without a recorded decision.
- The "not for operational decisions" disclaimer on the site stays regardless of class: real
  agreement with an operational product is still not a mandate to act on it.
