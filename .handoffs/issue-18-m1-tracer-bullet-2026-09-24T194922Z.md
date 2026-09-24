# Handoff — resolve decision ticket #18 (M1 tracer-bullet slice)

**Next session's job:** work the wayfinder map's next decision ticket,
[#18 Grilling: M1 tracer-bullet slice definition](https://github.com/climate-indices/climate-indices-cloud/issues/18).
One ticket, and only one ticket, per session — that is the wayfinder rule.

**Repository:** `climate-indices/climate-indices-cloud` (moved out of `monocongo` on
2026-09-24; the compute library stays at `monocongo/climate_indices` **on purpose**).
Local main clone: `/Users/jadams/git/climate_indices-cloud`.

## Do this, in order

1. Read [AGENTS.md](../AGENTS.md) — it holds the standing rules, and they are not
   repeated here.
2. Load the map: [issue #1](https://github.com/climate-indices/climate-indices-cloud/issues/1)
   (`gh issue view 1 --repo climate-indices/climate-indices-cloud`). Read its **Notes** and
   **Decisions so far** — those are the constraints the answer must fit.
3. Fetch #18's body; it states the question and is the specification for this session.
4. **Claim it first**, before any other write: `gh issue edit 18 --repo climate-indices/climate-indices-cloud --add-assignee @me`.
5. Resolve it with `/grilling` and `/domain-modeling`, one question at a time. This is a
   **HITL** ticket: the maintainer answers, the agent never answers for them. Facts that can
   be looked up belong in the repo, not in a question.
6. Record the result: a resolution comment on #18, close it, then append one line to the
   map's **Decisions so far** (gist + link). If the answer makes fog specifiable, create
   those tickets as map sub-issues and clear each patch from **Not yet specified**. If it
   invalidates another ticket, update or close that ticket.
7. If the outcome is a load-bearing, hard-to-reverse decision, write it as an ADR in
   `docs/adr/` — sequence continues from `0005`. Follow the format of the existing five.

## Where things stand (as of 2026-09-24)

**Charting is complete.** The map's destination is an approved, decision-complete plan:
every epic ready for `/to-spec`, every load-bearing decision an ADR, domain terms in
`CONTEXT.md`. Seven decisions are already recorded and five ADRs written:

| ADR | Decision |
| --- | --- |
| [0001](https://github.com/climate-indices/climate-indices-cloud/pull/8) | Two layouts — compute-optimized Zarr plus a derived serve surface |
| [0002](https://github.com/climate-indices/climate-indices-cloud/pull/8) | Publishing gate = library fixtures + reference agreement inside measured ceilings + coverage/units/calendar; publishes its Evidence Class |
| [0003](https://github.com/climate-indices/climate-indices-cloud/pull/8) | FastAPI on the EKS cluster (Lambda rejected on cold start despite cost), no NAT gateway |
| [0004](https://github.com/climate-indices/climate-indices-cloud/pull/8) | Terraform owns AWS APIs, Argo CD owns in-cluster state |
| [0005](https://github.com/climate-indices/climate-indices-cloud/pull/8) | One AWS account, `infra/envs/dev` + `infra/envs/prod`, ceilings $250 dev / $500 prod |

The ADRs and the first `CONTEXT.md` sit on **[PR #8](https://github.com/climate-indices/climate-indices-cloud/pull/8)
(still draft, needs the maintainer's merge)**. Read the ADR text from that branch or from
`docs/adr/` after it merges; do not re-litigate what they settled.

**Epics** exist as parent issues [#9](https://github.com/climate-indices/climate-indices-cloud/issues/9)–[#17](https://github.com/climate-indices/climate-indices-cloud/issues/17).
No specs exist yet — `/to-spec` runs per epic once its decisions are done.

**Open decision tickets (the frontier):** #18, #19 API surface, #20 observability backend,
#21 fire-pipeline scope, #22 Iceberg catalog, #23 compute topology, #24 site scope,
#25 launch. **Blocked:** #27 orchestrator ← #4, #26 telemetry schema ← #6.

**Research state:** #2 (fire sources) and #3 (nClimGrid) are resolved and closed with
reports on `research/daily-fire-weather-source` and `research/nclimgrid-aws`. #4
(orchestrator), #5 (now a cost-model confirmation of ADR-0003, not a comparison), and #6
(telemetry capture) are open because the research subagent pool
(`lane-research-openrouter`) was refusing calls with `Codex error: The usage limit has been
reached`. Re-fire them when quota allows; do not re-do #2/#3.

**Blocking prerequisite:** `climate_indices` **3.0.0 is not on PyPI** (latest is 2.4.0) —
the engine pin is uninstallable. [Task #7](https://github.com/climate-indices/climate-indices-cloud/issues/7)
tracks it, assigned to `monocongo`; it is maintainer-owned. Do not attempt it.

## Facts the answer to #18 must respect

- The library's [ADR-0003](https://github.com/monocongo/climate_indices/blob/main/docs/adr/0003-dask-time-dimension-single-chunk.md)
  requires time as one Dask chunk on compute inputs — that is why the analysis store is
  shaped the way ADR-0001 describes.
- nClimGrid comes from S3 `noaa-nclimgrid-monthly-pds`, `us-east-1`, free read, ~6.7 GB,
  fixed 1/24° (1385×596) CONUS grid, integer hundredths, 1–2 week latency, SNS topic
  `NewNClimGridMonthlyObject` for new objects.
- The library enforces a **30-year minimum** calibration window; the brief and the ADR-0002
  validation fixtures both assume a 1931–1990-style window — #18 must state the exact one.
- `VALIDATION.md`'s evidence classes are the vocabulary the published report uses; SPI's
  NCEI comparison is a *characterization*, and #18 should not quietly upgrade it.
- #18 will likely become the input to `/to-spec` for M1 — write it so an implementer needs
  no further decisions.

## Board coordinates (recreated under the org; numbers differ from earlier sessions)

- Project: `cloud-native`, owner `climate-indices`, **number 1**, id `PVT_kwDOE9_JlM4BkltX`.
- Fields: `Epic` `PVTSSF_lADOE9_JlM4BkltXzhjVxag` (E0 `f0cb7824`, E1 `2d46ea6a`,
  E2 `19e835c8`, E3 `c87c6f56`, E4 `6db16591`, E5 `1ebe8439`, E6 `f1deb156`, E7 `ffe567bf`,
  E8 `93933e65`, E9 `402dfa90`); `Agent` `PVTSSF_lADOE9_JlM4BkltXzhjVxak`;
  `Estimate` `PVTF_lADOE9_JlM4BkltXzhjVxas`; `Actual` `PVTF_lADOE9_JlM4BkltXzhjVxaw`;
  `Milestone (M1-M5)` `PVTSSF_lADOE9_JlM4BkltXzhjVxco`.
  Verify ids with `gh project field-list 1 --owner climate-indices --format json` before
  relying on them; GitHub ids did change once already during the migration.
- The old personal board still exists, renamed "(superseded)"; ignore it.
- `docs/agent/issue-tracker.md` has the fuller command set — but its board/field ids
  predate the org move, so prefer the values above.

## Suggested skills

- `/wayfinder` — the protocol this session follows; #18 is a `wayfinder:grilling` ticket.
- `/grilling` and `/domain-modeling` — mandatory for a HITL decision ticket; update
  `CONTEXT.md` inline if a term crystallises.
- `/handoff` — at the end, for whatever comes after #18.
- `climate-indices-conventions` skill — for the compute library's module boundaries and
  terminology, so questions to the maintainer aren't ones the library already answers.
- `/research` (via a `lane-research-openrouter` subagent) — only to re-fire #4/#5/#6, and
  only when the pool accepts calls.

## Do not

- Merge PR #8 or PR #28, push to `main`, or tag anything — merges are the maintainer's.
- Resolve more than one decision ticket.
- Rewrite the closed research tickets #2/#3, or reopen the settled decisions in ADR-0001..0005
  without new evidence.
- Work outside your own worktree.
