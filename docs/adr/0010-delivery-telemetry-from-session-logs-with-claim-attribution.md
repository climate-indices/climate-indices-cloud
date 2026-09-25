# Delivery telemetry comes from local session logs and is joined to tickets by claim comments

The capstone brief has Claude Code export OpenTelemetry to the project's own collector and has
herdr's `blocked` state measure Human Attention Minutes. Delivery Telemetry is instead captured
from the agents' local session logs. A weekly batch on the maintainer's machine reads Claude
Code transcripts (including the subagent files, deduplicated on request id) and pi session
files, extracts an allowlist of fields (timestamps, ids, model, token counts, stop reason, tool
name, error and decline flags, never prompt text, tool input or output, commands, or paths), and
computes tokens, an estimated model cost, and handback gaps from them. A session is joined to a
ticket by a claim comment the agent posts right after assigning the ticket, carrying the agent,
the session id, and the Estimate. The batch is the only writer of `metrics/runs.jsonl`. The
tool-call gate is a hook in this repository that calls Jev through OpenRouter and logs every
judged call with its session id and tool-use id. The metric definitions themselves live in
`metrics/definitions.md`, written with the E8 spec, not here.

The logs are the better source for three reasons. Claude Code has no file or S3 exporter, and
OTLP needs an endpoint reachable from outside the VPC while [ADR-0007](https://github.com/climate-indices/climate-indices-cloud/pull/32)
defers any collector to M4; a laptop collector works only while it runs and cannot backfill.
The transcripts already carry the tokens, the timestamps, and the claim commands. And no
ticket key survives the other joins: every Claude Code transcript in this repository records the
main clone as its working directory and `main` as its branch, because sessions start there and
enter worktrees later, and a session usually starts before the ticket is chosen, so a launch-time
attribute cannot name it.

## Considered options

**A laptop OTel Collector with a launch-time ticket attribute.** The brief's design. Rejected
because a launch attribute cannot name a ticket chosen mid-session, and a collector loses
whatever happens while it is not running. It stays the fallback if the transcript format breaks.

**herdr `blocked` intervals for Human Attention Minutes.** Rejected because herdr's status events
carry no timestamp and cannot be replayed, and a question asked in chat shows as `idle` or
`done`, not `blocked`. Across this repository's first five sessions, two waits over half an hour
made up 3.9 of 5.5 hours of handback time, and strict `blocked` would have read near zero.

**Attributing by working directory, worktree, or branch.** Rejected: the transcripts record the
main clone and `main` for every session, worktree work included.

**An agent or a CI bot writing `runs.jsonl` lines.** Rejected because agents never push to
`main`, decision tickets have no pull request, and the merge time is not known until the
maintainer merges. A batch that opens a pull request the maintainer merges keeps the PR workflow.

**The existing `claude-jev-guard`.** Rejected because it calls only TypeSafe and needs a
TypeSafe key, so with only an OpenRouter key its hook returns before logging anything, it has
no licence, and it logs the session but not the tool-use id, so a hold can be joined to the
human's answer only by time window.

## Consequences

- The parser reads a format Claude Code documents as internal and version-unstable. It is keyed
  by the transcript's `version` field and tested against a fixture per version. If a release
  breaks it, the laptop collector above is the fallback.
- Claude Code deletes transcripts after `cleanupPeriodDays`, 30 by default. The maintainer sets
  it to 365 and the batch runs weekly. Without that, this repository's earliest sessions are swept
  from about 2026-10-24.
- The transcripts carry no cost field, so cost is computed from a versioned price table and is
  published as a list-price estimate, never spend. pi's own cost figure is ignored so the two
  agents stay comparable.
- Two gaps are published as coverage flags: pi's subagent spend is absent from the parent log,
  and an approval wait inside a turn is not a handback gap.
- A session that never posts a claim is Unattributed Work and is published. Sessions that
  predate the convention are backfilled from the `--add-assignee` commands in their transcripts.
- The gate sends a trimmed copy of the tool input and the last user prompt to OpenRouter. The
  spec and the engineering page state this, and the OpenRouter account excludes providers that
  log or train on prompts. OpenRouter's retention terms are unverified. The gate fails open and
  always logs. An allowed call that later needs a revert is not measured, and that gap is stated.
- This departs from the brief, which is a starting point, not a contract.
