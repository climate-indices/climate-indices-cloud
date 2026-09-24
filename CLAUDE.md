# Claude Code Instructions

Read [AGENTS.md](AGENTS.md) — it is the single source of project guidance for all
coding agents, including the standing conventions:

1. Every issue appears on the `cloud-native` project board (owner `monocongo`).
2. Epic → spec → ticket, using sub-issues and native blocked-by relationships.
3. Delivery telemetry from day one: `Ticket: #N` / `Agent: <claude-code|pi|human>`
   commit trailers, an `Estimate` before any agent starts a ticket, and records in
   `metrics/runs.jsonl`.
4. Prioritize decisions that unblock milestone M1 (the SPI-3 tracer bullet).

This repo is plan-first: the wayfinder map resolves decisions before implementation.
