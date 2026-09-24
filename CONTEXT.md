# climate-indices-cloud

A service that turns public climate observations into validated drought and wildfire-danger
index datasets, and serves them to anyone. It is not the compute library: the indices
themselves — SPI, SPEI, EDDI, PNP, the Palmer family, and the fire indices — are defined by
[`climate-indices`](https://github.com/monocongo/climate_indices/blob/main/src/climate_indices/CONTEXT.md),
and that glossary is authoritative for their meaning. This file holds the vocabulary of the
*service* built around them.

## Language

### Datasets and time

**Upstream**:
A source dataset published by someone else — nClimGrid, gridMET — together with the moment
*they* published it. Data freshness is measured against that moment, not against when we
looked.
_Avoid_: Source (ambiguous with source code)

**Analysis Store**:
The ingested, quality-checked, compute-optimized copy of an upstream dataset: Zarr, with time
as one unbroken chunk so the compute engine's calibration can run. Its shape serves compute,
not readers.
_Avoid_: Raw (it is already cleaned and rechunked) 

**Timescale**:
As in the compute library: the accumulation window (SPI-3, SPI-12). A Published Dataset is
always qualified by it.

**Calibration Window**:
The years whose data defines "normal" for a dataset. Two datasets identical but for their
calibration window are different products, not versions of one another.

**Published Dataset**:
A versioned artifact for one index, one timescale, and one calibration window, over a stated
period — the thing a consumer cites. Created by a Publish.
_Avoid_: Output (a compute-run term, not something a consumer identifies)

**Dataset Version**:
Identifies a Published Dataset by the last month it covers and by how many times that coverage
has been published — a re-Publish of the same month is a new version, not an overwrite.

**Publish**:
The act of making a computed dataset live, after the Validation Gate passes and a Validation
Report is written. Distinct from computing: computing can happen any number of times, a
Publish happens once per version.

**Serve Surface**:
The derived artifacts shaped for readers rather than for calibration — map layers, aggregate
tables, bulk downloads. Derived from the same compute pass as the Published Dataset, never
maintained separately.

### Trust

**Validation Gate**:
The set of checks a Publish must pass. It asserts what can be proven, not what is believed.

**Validation Report**:
The machine-generated record accompanying every Publish, naming each index's Evidence Class
and the reference agreement achieved.

**Evidence Class**:
How well an index's numbers are externally corroborated — `external-validated`,
`reference-reproduced`, or `characterization-only`. A level of evidence, never a synonym for
"correct".
_Avoid_: Validated (bare — it hides which of the three is meant)

**Reference Ceiling**:
The largest disagreement with an index's operational reference that library validation
actually measured, with headroom. It is what the Validation Gate enforces, and it holds only
at the resolution and configuration it was measured at. Never widened to make a Publish pass.

**Data Freshness**:
The interval between an Upstream's publication and our Publish. The service's third SLO, and
the reason ingestion is event-driven where the upstream announces new data. Every new or revised
Upstream object starts its own clock, and a Publish delayed by a Validation Gate block is still
late: freshness is what a consumer experiences, not why it slipped.

### Delivery

**Decision Ticket**:
A ticket whose resolution is a decision — a research question, a grilling, a prototype, or a
task that unblocks one — rather than a slice of work to execute. Decision tickets are charted
on the wayfinder map.

**Epic**:
A parent issue covering one area of scope (E1–E9). An epic becomes ready for `/to-spec` once
its Decision Tickets are resolved.

**Spec**:
A sub-issue of an epic describing what to build, produced from `/to-spec`. Tickets are
sub-issues of a spec.

**Agent**:
Who did the work on a ticket — `claude-code`, `pi`, or `human`. Recorded on the board and in
commit trailers, because Delivery Telemetry depends on it.

**Estimate** / **Actual**:
Hours, in that order: Estimate is recorded before any agent starts a ticket, Actual when it
finishes. Estimates are biased by construction and are published as a reference point, never
as a speed claim.

**Delivery Telemetry**:
The measured record of how this project itself was built — throughput, cycle time, agent
attribution, Human Attention Minutes — published including its misses.

**Human Attention Minutes**:
Time an agent spent blocked waiting on a human, per ticket. The scarce resource the
telemetry exists to expose.
