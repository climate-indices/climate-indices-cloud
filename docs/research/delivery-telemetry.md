# Delivery-Telemetry Capture: Claude Code OTel, pi, herdr, the pi-jev gate, GitHub

**Research ticket:** [#6](https://github.com/climate-indices/climate-indices-cloud/issues/6)
**Feeds:** [#26](https://github.com/climate-indices/climate-indices-cloud/issues/26) (telemetry schema and metric definitions; this report is input, not a schema)
**Date:** 2026-09-24 (every source below was read on this date unless a row says otherwise)

## Summary

- All five sources exist and their capture interfaces are real, verified from primary sources (official docs, tool source, on-disk logs). No source carries the ticket number natively: attribution has to be injected at launch (Claude Code `OTEL_RESOURCE_ATTRIBUTES`, pi `--name`/`--session-id` or `cwd`, herdr `agent_session` + `cwd`, GitHub commit trailers and closing references).
- Claude Code OTLP export is real (`grpc`, `http/json`, `http/protobuf`; metrics, logs/events, beta traces) but has **no file or S3 exporter**. With no in-cluster collector until M4 (ADR-0007), the only verified route is a collector on the developer machine (OTel Collector contrib `file`/`awss3` exporters, both alpha). Nothing was run end to end.
- pi session JSONL is the richest source (per-message tokens and cost; 30,843 assistant messages across 620 local sessions) but has no ticket field, its cost is a list-price estimate, and subagent usage is absent from the parent log.
- herdr emits agent state events over a Unix socket, but the event payload has **no timestamp** and there is no replay, and for pi the `blocked` state is reported only if an extension emits `herdr:blocked`. Human attention minutes are computable only approximately, and only if a subscriber runs continuously.
- The "pi-jev tool-call gate" is ambiguous: the npm package named `pi-jev` is a compaction/routing tool, not a gate. The gate is `pi-jev-guard` (and a compact copy in `pi-jev-harness`). Neither records whether a hold was the right call, nor the human's confirm/decline; neither has been run on this machine in a way that produced usable data.
- GitHub supplies lead time, PR cycle time, throughput, PR size, and reopen rate from documented fields. CI first-pass rate is **not computable today** (the repo has 0 workflows), and revert rate has no first-class field.

## Source Verification

| Source | Exists? | Evidence (primary) | Version / date read | Verified? |
|---|---|---|---|---|
| Claude Code OpenTelemetry export | Yes | <https://code.claude.com/docs/en/monitoring-usage.md> (official docs; line numbers below refer to this file as fetched) | Claude Code 2.1.282 installed (`claude --version`); doc read 2026-09-24 | VERIFIED from docs. Not exercised: this machine has no `OTEL_*`/`CLAUDE_CODE_ENABLE_TELEMETRY` set in env, `~/.claude/settings.json`, or `~/.claude.json` |
| Claude Code local transcripts (fallback source) | Yes | `~/.claude/projects/*/*.jsonl` (220 files); docs call the format internal and version-unstable (monitoring-usage.md L661-663) | 2.1.282 | VERIFIED (field names observed), format not a stable contract |
| pi coding agent | Yes | <https://github.com/earendil-works/pi> (MIT); npm `@earendil-works/pi-coding-agent`; docs shipped in the package under `docs/` | 0.87.1 (npm latest = installed) | VERIFIED |
| pi session logs | Yes | `docs/session-format.md` (packaged) plus 620 real files under `~/.pi/agent/sessions/` (header version 3 in 620/620) | 0.87.1; files dated 2026-08-04..2026-09-24 | VERIFIED (docs and on-disk schema agree) |
| herdr | Yes | <https://herdr.dev>; <https://github.com/herdrdev/herdr> (Apache-2.0, master pushed 2026-09-24); docs at `https://raw.githubusercontent.com/herdrdev/herdr/v0.9.1/docs/next/website/src/content/docs/{socket-api,agents,integrations}.mdx`; `herdr api schema --json` (protocol 22, schema_version 1) | 0.9.1 (brew stable) | VERIFIED (docs + bundled schema + live `herdr agent list`). The `events.subscribe` stream itself was not opened |
| herdr Pi integration | Yes | `~/.pi/agent/extensions/herdr-agent-state.ts` (integration v8; `herdr integration status` reports v9 available); same file in upstream `src/integration/assets/pi/herdr-agent-state.ts` | herdr 0.9.1 | VERIFIED |
| `pi-jev` (npm) | Yes | <https://github.com/iefnaf/pi-jev> (MIT, main@cd16845); npm `@alexlikevibe/pi-jev` 0.2.1, installed at `~/.pi/agent/npm/node_modules/@alexlikevibe/pi-jev` | 0.2.1 | VERIFIED to exist. VERIFIED **not a gate**: README lists only compaction, routing, and `/jev` settings extensions |
| `pi-jev-guard` (the actual gate) | Yes | <https://github.com/MoonTory/pi-jev-guard> (no license file; main@804778f, 2026-09-17), `classify.ts`, `index.ts` read in full | 2026-09-17 | VERIFIED from source. Not installed locally: `~/.jev-guard/` does not exist |
| `pi-jev-harness` (compact guard + loop control) | Yes | <https://github.com/MoonTory/pi-jev-harness> (no license file; origin/main@8b05776) | 2026-09-24 | VERIFIED from source and from the on-disk log `~/.jev-harness/log.jsonl` (2 entries, 2026-09-23). How it is loaded into pi on this machine was not determined (not in `~/.pi/agent/settings.json` packages, not in `~/.pi/agent/extensions/`) |
| `claude-jev-guard` (same gate as a Claude Code hook) | Yes | <https://github.com/MoonTory/claude-jev-guard> (main@02d9d99); README and `hook.ts` (stdin fields, log path) | 2026-09-17 | VERIFIED exists; interface read from README/source only, not run |
| Jev model service (TypeSafe / OpenRouter Decisions API) | Client code only | Called by the three repos above; `typesafe.ai` and OpenRouter docs not fetched | n/a | UNVERIFIED as an independent service. Only the client side is verified |
| GitHub REST and GraphQL fields | Yes | OpenAPI description `github/rest-api-description` main@c624b95 (`api.github.com.json`, version 1.1.4); live `gh api` and GraphQL calls against `climate-indices/climate-indices-cloud`; <https://docs.github.com/api/article/body?pathname=/en/rest/using-the-rest-api/issue-event-types> | 2026-09-24 | VERIFIED |
| OTel Collector contrib `fileexporter`, `awss3exporter` | Yes | `open-telemetry/opentelemetry-collector-contrib` main@b4428fb, `exporter/fileexporter/README.md`, `exporter/awss3exporter/README.md` | 2026-09-24 | VERIFIED to exist (both stability `alpha` for traces/metrics/logs). NOT verified end to end with Claude Code |

## 1. Claude Code OpenTelemetry export

### 1.1 Enabling it and choosing an endpoint

Enable with environment variables (monitoring-usage.md L11-36, L92-122):

```bash
export CLAUDE_CODE_ENABLE_TELEMETRY=1
export OTEL_METRICS_EXPORTER=otlp        # otlp | prometheus | console | none
export OTEL_LOGS_EXPORTER=otlp           # otlp | console | none   (logs carry the events)
export OTEL_EXPORTER_OTLP_PROTOCOL=grpc  # grpc | http/json | http/protobuf ; NO default, must be set
export OTEL_EXPORTER_OTLP_ENDPOINT=http://localhost:4317
export OTEL_RESOURCE_ATTRIBUTES="ticket=6,agent=claude-code"   # the only documented way to add a ticket key
```

Verified interface facts:

- **Protocols:** `grpc`, `http/json`, `http/protobuf`. "Claude Code has no default protocol" (L101). Per-signal endpoint/protocol/header overrides exist (L103-109). Static headers via `OTEL_EXPORTER_OTLP_HEADERS`; dynamic headers via `otelHeadersHelper` apply to the `http/*` protocols only (L338-340).
- **Signals:** metrics, logs/events, and traces (beta; needs `CLAUDE_CODE_ENHANCED_TELEMETRY_BETA=1` plus `OTEL_TRACES_EXPORTER`, L150-165). Traces are not needed for E8 and are excluded from the mapping.
- **Intervals:** metrics 60 s default (`OTEL_METRIC_EXPORT_INTERVAL`), logs 5 s (`OTEL_LOGS_EXPORT_INTERVAL`); metrics temporality is `delta` by default (L110-111, L119), so each landed datapoint is an increment, not a running total.
- **Exporters other than OTLP:** `prometheus` (metrics only; scrape at `http://localhost:9464/metrics`, L440-445), `console` (named as an option, L20-21, L423-429; the docs do not say which stream it writes to, so that is UNVERIFIED and it is unusable under the interactive TUI in any case). **There is no `file`, S3, or JSONL exporter in Claude Code itself.** The only file output is `OTEL_LOG_RAW_API_BODIES=file:<dir>` (raw request/response bodies plus an `index.jsonl`, L117, L836-837), which is a content dump, off by default, and out of scope.
- **Managed settings can pin the destination:** setting `OTEL_EXPORTER_OTLP_ENDPOINT` in managed settings removes developer-set per-signal endpoints (L65-88). Irrelevant for a single-owner repo, but it means a laptop-local collector endpoint set in `~/.claude/settings.json` `env` is honoured. Project-level `.claude/settings.json` cannot set `OTEL_LOG_RAW_API_BODIES` (L2798+ of `settings-reference.md`), so per-repo settings are not a safe carrier for content-bearing flags.
- **Subprocesses do not inherit `OTEL_*`** (L63), so a launch wrapper must set the attribute on the `claude` process itself.
- **Verification signal:** `claude_code.session.count` arrives at session start (L38).

### 1.2 Endpoint options at M1 (ADR-0007 has no in-cluster collector until M4; #26 requires an endpoint reachable from outside the VPC)

| Option | What is verified | What is not | Fits ADR-0003 / ADR-0005 |
|---|---|---|---|
| A. OTel Collector on the developer machine: `otlp` receiver, then `file` and/or `awss3` exporter to S3 | `fileexporter`: JSON or proto, rotation, zstd compression, `otlpjsonfilereceiver` reads it back (README). `awss3exporter`: contrib distribution only, marshalers `otlp_json`/`otlp_proto`, `s3_partition_format` (strftime), `s3_bucket`, compression (README). Both `alpha` | Not run with Claude Code; AWS credential handling and flush-on-exit behaviour not tested; the collector must be running whenever `claude` runs or that window is not exported (the docs describe exporter failures as `[3P telemetry]` errors visible under `claude --debug`, L40, and a failed headers helper additionally warns in `/status`, L364-368) | Yes: laptop to S3 is outside the VPC and needs no cluster egress. S3 storage cost is small but unmeasured |
| B. Claude Code `prometheus` exporter scraped locally | Documented (L440-447) | Metrics only: no `api_request`, `tool_result`, `tool_decision` events, so no per-request cost/duration and no `prompt.id` | Yes, but strictly weaker than A |
| C. `console` exporter | Named in docs | Destination stream UNVERIFIED | Not viable for capture |
| D. OTLP/HTTP straight to a hosted ingest (for example a Lambda or API Gateway writing to S3) | Claude Code can send `http/protobuf` or `http/json` with static or helper-generated headers | No first-party or reference implementation found; would create a public ingest surface and an auth story. UNVERIFIED | Cost fine; adds a public endpoint the ADRs do not yet contemplate |
| E. In-cluster collector | ADR-0007 defers any collector to M4; the cluster has no public ingress for OTLP | n/a | Rejected by ADR-0007 at M1 |
| F. No OTLP; parse local transcripts `~/.claude/projects/*/*.jsonl` | Observed fields: `sessionId`, `timestamp`, `cwd`, `gitBranch`, `version`, `message.model`, `message.usage.{input_tokens, output_tokens, cache_creation_input_tokens, cache_read_input_tokens}`, `requestId`, `promptId`, `pr-link` entries with `prNumber`/`prUrl`/`prRepository` | No cost field. `usage` is repeated per content block: in one sampled session 78 assistant entries carried 38 distinct `requestId`s, so a naive sum overcounts about 2x; dedupe on `requestId`. Format "internal to Claude Code and changes between versions" (L661-663). Files are swept after `cleanupPeriodDays` (default 30) | Yes, but lossy and fragile; keep only as backfill |

ADR-0003 check: none of A, B, F needs the cluster to reach the internet. Any capture path that polls GitHub or a laptop from inside the cluster would need egress (NAT, proxy, or a CI/batch path outside the VPC, per ADR-0003 Consequences); the GitHub pull in section 5 should run from GitHub Actions or the laptop, not from a cluster job.

### 1.3 Fields (all from monitoring-usage.md; `event.timestamp` is ISO 8601 on every event)

| Field | Type | Meaning | Join key to ticket | Landed-storage notes |
|---|---|---|---|---|
| `session.id` (standard attr, default on; `OTEL_METRICS_INCLUDE_SESSION_ID`) | string | Unique session identifier (L495) | Indirect: join to launch-time `ticket` attribute, or to transcript `sessionId` (`cwd`, `gitBranch`). Equality with the `session_id` the herdr hook receives is expected but UNVERIFIED | Part of every grain. `/clear` assigns a new `session.id` inside the same process (L661) |
| custom keys from `OTEL_RESOURCE_ATTRIBUTES` (for example `ticket`, `agent`) | string | Copied onto every datapoint and event and into the OTLP resource block; cannot override standard attributes (L375-393). No spaces; percent-encode (L395-417) | **Direct, but process-scoped**: fixed at launch, cannot change when the ticket changes mid-session | The primary ticket join. A session started without it is unattributable except via transcript `cwd`/`gitBranch` |
| `vcs.repository.url.full`, `vcs.owner.name`, `vcs.repository.name`, `vcs.provider.name` | string | Repository identity from `origin` (L516-533) | Repo only, not ticket | Opt-in `OTEL_METRICS_INCLUDE_REPOSITORY=true`, needs Claude Code 2.1.269+ |
| `user.id`, `user.account_uuid`, `user.account_id`, `organization.id`, `user.email`, `terminal.type`, `app.version`, `app.entrypoint` | string | Identity and environment (L491-505) | none | `user.email` is PII (L1471); drop or hash it in the collector before landing |
| `claude_code.token.usage` | counter (tokens, delta) | Tokens per API request, with `type` in `input`, `output`, `cacheRead`, `cacheCreation`, plus `model`, `query_source` (`main`/`subagent`/`auxiliary`), `speed`, `effort`, `agent.name`, `skill.name` (L609-621) | `session.id` + custom `ticket` | Land datapoints, not pre-aggregated sums. Cardinality grows with every custom key (L393) |
| `claude_code.cost.usage` | counter (USD, delta) | Cost per API request, same attributes as tokens (L591-607). Docs: "Cost metrics are approximations" (L1316) | same | Estimated cost, not billed. Whether it is populated under a subscription login is UNVERIFIED |
| `claude_code.active_time.total` | counter (s) | Active use, excluding idle; `type` `user` (keyboard, reading) or `cli` (tool execution, model) (L635-642) | same | Not "blocked waiting on a human": `user` time is the human being active, not the agent waiting |
| `claude_code.lines_of_code.count` | counter | Lines `added`/`removed`, plus `model` (L565-573) | same | Agent-reported; PR size from GitHub is the vendor-neutral figure |
| `claude_code.commit.count`, `claude_code.pull_request.count` | counter | Commits and PRs Claude Code created (L575-589) | same | Counts only Claude Code's own actions |
| `claude_code.session.count` | counter | Sessions started; `start_type` `fresh`/`resume`/`continue`/`agents_view` (L556-563) | same | Filter `agents_view` out |
| `claude_code.code_edit_tool.decision` | counter | Edit/Write/NotebookEdit accept/reject with `source` (`config`, `hook`, `user_permanent`, `user_temporary`, `user_abort`, `user_reject`) and `language` (L623-633) | same | Counts human decisions, gives no wait duration |
| event `claude_code.api_request` | log record | Per request: `model`, `cost_usd`, `cost_usd_micros` (integer), `duration_ms`, `input_tokens`, `output_tokens`, `cache_read_tokens`, `cache_creation_tokens`, `request_id`, `query_source`, `prompt.id`, `event.sequence` (L738-763) | `session.id` + `ticket` | Best grain for token/cost per ticket: exact per request. `event.sequence` is per process, not per session, so it repeats after `--resume` (L661); order by `event.timestamp`, then `event.sequence` |
| event `claude_code.tool_result` | log record | `tool_name`, `success`, `duration_ms`, `tool_use_id`, `decision_source`; with `OTEL_LOG_TOOL_DETAILS=1` also `vcs.ref.head.revision`/`.name` for a successful `git commit` (2.1.269+) and the full Bash command (L706-736) | `vcs.ref.head.name` gives the branch on commit events only | The details flag also exports Bash commands and file paths; enable only if that exposure is accepted (L1474-1478) |
| event `claude_code.tool_decision` | log record | `decision`, `source`, `tool_name`, `tool_use_id` (L858-889) | `session.id` | Records who decided, not how long the prompt waited (no prompt-shown timestamp), so it cannot give blocked minutes exactly |
| event `claude_code.user_prompt` | log record | `prompt_length`, `prompt.id`, `command_name`; prompt text only if `OTEL_LOG_USER_PROMPTS=1` (off by default) (L669-685) | `prompt.id` correlates all events for one prompt | Keep prompt logging off |
| events `subagent_completed`, `compaction`, `api_error`, `permission_mode_changed`, `retention_sweep` | log records | Subagent duration and tool uses; compaction `pre_tokens`/`post_tokens`; retries exhausted; permission-mode escalation; transcript deletion counts (L1146-1237, L765-788, L891-905) | `session.id` | Useful for misses (errors, refusals) and for auditing the 30-day sweep |

Not exposed: cwd, worktree path, git branch (except `vcs.ref.head.name` on commit tool results), issue number, PR number for merged work. The standard-attribute list (L491-505) contains none of them, so **OTel alone cannot attribute a session to a worktree**; the launch-time attribute is the only reliable join.

### 1.4 Retention implications

- Claude Code does not retain exported telemetry; retention is whatever the backend or S3 lifecycle rule is. The docs describe no buffering or replay to disk, so if the collector is down that window is lost (whether the final 60 s metric interval is flushed on exit is UNVERIFIED).
- The local fallback is short-lived: transcripts are deleted after `cleanupPeriodDays`, default 30, minimum 1 (`https://code.claude.com/docs/en/claude-directory.md` L1534; the `retention_sweep` event reports deletions, L1208-1237). The oldest transcript on this machine is dated 2026-08-27, consistent with the default.
- Content flags (`OTEL_LOG_USER_PROMPTS`, `OTEL_LOG_TOOL_DETAILS`, `OTEL_LOG_TOOL_CONTENT`, `OTEL_LOG_RAW_API_BODIES`) all default off. The published Engineering page and S3 landing should assume only the default (metadata-only) stream so that no prompt text, command, or code is ever landed (L1467-1484).

## 2. pi session logs

pi (`@earendil-works/pi-coding-agent` 0.87.1, MIT) persists every session as append-only JSONL. Source of truth for the format: `docs/session-format.md` and `docs/message-types.md` shipped in the package (mirrored at <https://github.com/earendil-works/pi/tree/main/packages/coding-agent/docs>), confirmed against 620 real files.

- **Location:** `~/.pi/agent/sessions/--<cwd with / \ : replaced by ->--/<timestamp>_<session-id>.jsonl` (session-format.md L8-14). Override with `--session-dir`, `PI_CODING_AGENT_SESSION_DIR`, or the `sessionDir` setting (sessions.md L50). `--no-session` disables persistence. No automatic expiry is documented; the oldest local file is 2026-08-04 (this is "not documented", not "verified absent").
- **Format:** line 1 is a header; every later line is an entry with `id`, `parentId`, ISO `timestamp` (tree structure, so branches and forks share one file). Observed entry types across 620 files: `message` (74,255), `model_change` (1,044), `thinking_level_change` (831), `custom_message` (473), `custom` (10, all `chisle-mode`), `compaction` (6), `context_edit` (5). The documented `usage`, `branch_summary`, `label`, and `session_info` types did not occur locally.
- **Header fields observed:** `type`, `version` (3 in 620/620), `id`, `timestamp`, `cwd`. No branch, worktree, ticket, or repo field. `parentSession` appears only for forks (0 locally).

| Field | Type | Meaning | Join key to ticket | Landed-storage notes |
|---|---|---|---|---|
| header `id` | uuid string | Session id (also the file-name suffix) | herdr `agent_session.value` for pi is the **file path** (live `herdr agent list`: kind `path`, source `herdr:pi`), which embeds this id | Session grain key |
| header `cwd` | path | Working directory the session started in | **Best available join**: `cwd` to `git worktree list` to branch to ticket. Lossy if a worktree path is reused across tickets (needs a time window) or the session starts in the primary checkout | The sessions directory name is a lossy slug of it (`/`, `\`, `:` all become `-`); use the header, not the slug |
| `session_info.name` (set with `--name`/`/name`) | string | User-defined session name (session-format.md L195-203) | **Direct if the launcher passes `--name "ticket-6"`** | Documented but 0 occurrences locally, so it is not currently used |
| `custom` entry (`customType`, `data`) written by an extension via `pi.appendEntry` | object | Extension state, not in LLM context (L162-170) | A small extension could write `{ticket, agent}` at `session_start`; not built | Would be the cleanest in-band key; UNVERIFIED as a pattern for this repo |
| `message.role="assistant"` `timestamp` (ms) and entry `timestamp` (ISO) | int / string | Response time | time-window join to herdr transitions and Jev log | Both clocks are the local machine's |
| `message.provider`, `message.model`, `message.api`, `message.responseModel` | string | Model that answered (30,843/30,843 assistant messages carry provider/model/api) | none | Dimension. `model_change` entries add mid-session switches |
| `message.usage.input`, `.output`, `.cacheRead`, `.cacheWrite`, `.totalTokens` | int | Tokens per model call (present on 30,843/30,843 assistant messages) | session (`cwd`) | Grain: one assistant message. Sum by session, then by ticket |
| `message.usage.reasoning` | int, optional | Reasoning tokens, **already included in `output`; do not add** (message-types.md L90). Present on 30,504 | none | Do not double count |
| `message.usage.cacheWrite1h` | int, optional | Subset of `cacheWrite` written with 1-hour retention (message-types.md L90) | none | Optional column |
| `message.usage.cost.{input,output,cacheRead,cacheWrite,total}` | float USD | Cost per model call (present on 30,843/30,843) | session | Computed from the model's configured price per million tokens (rpc-commands.md L832: "Costs are in US dollars per million tokens"); a **list-price estimate**. Whether it equals billed spend is UNVERIFIED, and for subscription logins it cannot be a metered charge |
| `message.stopReason` | enum | `stop`, `toolUse`, `length`, `error`, `aborted`, `pending`, `deferred`; locally 29,097 `toolUse`, 1,407 `stop`, 309 `error`, 30 `aborted` | none | Misses signal: errors and aborts still carry cost fields |
| `message.errorMessage` | string | Present on 339 messages | none | Do not land raw text; land a flag |
| `usage` **entry** (`kind`, `provider`, `model`, `usage`) | object | Model usage that is not an assistant message, for example cache warming; "contribute[s] to session token and cost totals" (L111-119) | session | Must be summed with message usage or totals are understated. 0 occurrences locally |
| `compaction.usage`, `branch_summary.usage` | object, optional | Usage from generating a summary (L131-160) | session | Same: include in session totals |
| `toolResult.usage` | object, optional | "Nested model work performed by the tool" (message-types.md L170-176) | session | **0 of ~41,677 local tool results carry it, including 575 `subagent` results**, so subagent model spend does not appear in the parent log. Where subagent spend is recorded, if anywhere, is UNVERIFIED |
| `toolResult.toolName`, `isError`, `details.diff`/`patch`/`firstChangedLine` (edit) | mixed | Tool outcome; `edit` results carry a diff in 903 of 945 sampled results, `write` carries no details, `bash` details only `truncation`/`fullOutputPath` | none | Lines changed are derivable for `edit` only; use GitHub PR additions/deletions instead |
| `bashExecution`, `custom_message`, user `content` | mixed | Prompts and outputs | none | **Never land**: contains prompts, file contents, possible secrets |

Streaming alternative: `pi --mode json` emits the same records to stdout, and RPC mode is bidirectional (json.md, rpc.md), but neither is required because the JSONL file already has per-message usage and cost. pi has no OTLP exporter: the docs and CHANGELOG mention only anonymous install telemetry (`PI_TELEMETRY`, `enableInstallTelemetry`) and a vendor-neutral `@earendil-works/pi-telemetry` contract package (0.87.1) that is a library, not an exporter; "no OTLP export" is inferred from absence, so treat it as UNVERIFIED negative.

Capture path (verified locally available): a periodic batch reads new lines from session files by byte offset and lands one row per assistant message; the files are on the same machine as herdr, which also gives the session path directly (section 3).

## 3. herdr

herdr (`herdr` 0.9.1, Apache-2.0, homebrew; <https://herdr.dev>) is a terminal workspace manager that classifies each pane's agent state and exposes a local socket API. Primary sources: `socket-api.mdx`, `agents.mdx`, `integrations.mdx` (v0.9.1 docs), the bundled JSON schema (`herdr api schema --json`, protocol 22), and the installed integrations.

**Transport.** Newline-delimited JSON over a Unix domain socket (a named pipe on Windows), one request per line; `events.subscribe` keeps the connection open after its acknowledgement (socket-api.mdx "Socket transport"). Default socket `~/.config/herdr/herdr.sock` (mode 0600 locally); named sessions use `~/.config/herdr/sessions/<name>/herdr.sock`. The socket is local-only, so the subscriber must run on the machine that runs herdr.

```json
{"id":"sub_1","method":"events.subscribe","params":{"subscriptions":[{"type":"pane.agent_status_changed","pane_id":"w1:p1","agent_status":"blocked"}]}}
```

- In the request schema the `pane.agent_status_changed` subscription **requires `pane_id`** (`required: ["type","pane_id"]`); `agent_status` is an optional (nullable) filter. A subscriber therefore needs one subscription per pane, and must discover panes through the lifecycle subscriptions (`pane.created`, `pane.agent_detected`, which take no `pane_id`) or `agent.list`. A wildcard status subscription is not in the schema.
- "Lifecycle subscriptions start when the request is accepted and do not replay events retained before that point." `session.snapshot` (CLI `herdr api snapshot`) is a one-time bootstrap: subscribe first, buffer, then snapshot, per the docs.

**Agent status set** (schema `AgentStatus`): `idle`, `working`, `blocked`, `done`, `unknown`. `idle` and `done` both mean ready for input (`done` = finished and unseen; "seen" is tracked per TUI client). `blocked` "means Herdr recognized an approval or question UI" (`herdr --skill` output; agents.mdx). `unknown` = agent present but unclassifiable. Reported state (`pane.report_agent`) accepts only `idle`, `working`, `blocked`, `unknown`.

**Event set** (schema `EventKind`, 26 kinds): workspace, worktree, tab, and pane lifecycle (`workspace_created/updated/metadata_updated/closed/renamed/moved/reordered/focused`, `worktree_created/opened/removed`, `tab_*`, `pane_created/closed/updated/focused/moved/exited`), `pane_output_changed`, `pane_agent_detected`, **`pane_agent_status_changed`**, `layout_updated`. Subscription kinds are `pane.output_matched`, `pane.agent_status_changed`, `pane.scroll_changed` (plus the lifecycle set).

| Field | Type | Meaning | Join key to ticket | Landed-storage notes |
|---|---|---|---|---|
| event `pane_agent_status_changed`: `pane_id`, `workspace_id`, `agent`, `display_agent`, `agent_status`, `title`, `state_labels` | strings / enum | One state transition for one pane | `pane_id` to `agent.get`/snapshot `agent_session` and `cwd` | Grain: one transition. **The payload has no timestamp and no sequence number** (schema `PaneAgentStatusChangedEvent`); the subscriber must stamp `observed_at` on receipt |
| `AgentInfo.agent_session` (`source`, `agent`, `kind` `id`|`path`, `value`) | object | Native session reference; live: pi panes report `kind=path` (the pi session JSONL path), Claude panes `kind=id` (Claude session id), from the herdr hooks | **The join to pi/Claude session logs**, hence to their `cwd` and usage | Read from `agent.list`/snapshot, not from the status event; refresh on `pane.agent_detected` |
| `AgentInfo.cwd`, `foreground_cwd`, `WorkspaceInfo.worktree.{checkout_path, repo_root, is_linked_worktree}` | strings | Where the pane runs; worktree provenance | `checkout_path` to branch to ticket | Same lossy worktree-reuse caveat as pi |
| `AgentInfo.state_change_seq` | uint64 | Monotonic per-server counter (observed live: 2353, 3592, 4105) | none | Available on `agent.get/list`, not in the pushed event. It orders transitions but is not a clock |
| `AgentInfo.screen_detection_skipped`, `interactive_ready`, `revision`, `tokens` | mixed | Detection authority flag and user metadata tokens | `tokens` (map, max 32 keys, `pane.report_metadata`) could carry `ticket=N` | `tokens` is a herdr-native place to stamp the ticket on a pane, if the launcher sets it; not used today |

**Who decides `blocked` (this determines whether human attention minutes are computable):**

- **pi:** state authority is the lifecycle-hook extension (`~/.pi/agent/extensions/herdr-agent-state.ts`, source read in full): `working` while an agent run is active, `idle` when `agent_settled` fires, and `blocked` **only while another extension has emitted a `herdr:blocked` event** on pi's event bus. When the hook is authoritative, herdr does not also run screen detection for that pane (agents.mdx "Status authority"). Neither `pi-jev-guard` nor `pi-jev-harness` emits `herdr:blocked` (searched: the only file in `~/.pi`, the pi package tree, and `~/git/pi-jev-harness` containing that string is herdr's own extension), so **a Jev confirm dialog shows as `working` in herdr**. pi itself "does not ask before every tool call" (usage.md L27), so pi produces few natural `blocked` periods.
- **Claude Code:** state comes from herdr's **screen manifest** detection; herdr's Claude hook reports only session identity (`pane.report_agent_session`, script read in `~/.claude/hooks/herdr-agent-state.sh`). `blocked` is set "only when the live bottom-buffer snapshot matches known visible approval, question, or permission UI"; unknown prompt shapes "may initially show as `idle` instead of `blocked`" (agents.mdx). The installed Claude integration is v7 (`herdr integration status`: "outdated (v7 < v10)"); the installed Pi integration is v8 (< v9).
- **Duration.** "Blocked duration" is the interval between a `blocked` observation and the next `pane_agent_status_changed` for that pane, using subscriber-stamped times. herdr's own state is ephemeral: the server log `~/.config/herdr/herdr-server.log` (14,791 lines) records tracing events such as `tab.focus`, `pane.spawned`, and `agent changed` (process detection), not status transitions (no `blocked` lines at all), and `~/.config/herdr/session.json` is a layout restore file. So there is **no on-disk history to backfill**.
- herdr also offers plugin event hooks (`plugin.*`, docs "Plugins") that run a command on matching events; that is an alternative to a long-lived subscriber, with `HERDR_PLUGIN_EVENT_JSON` supplied to the command. Not exercised; UNVERIFIED for status events (the docs' example hook is `worktree.created`).

## 4. The pi-jev tool-call gate

**Which tool.** The brief's description ("fast typed judgments on whether a pending command is irreversible, off-task, mutating, or out of scope") matches **`MoonTory/pi-jev-guard`**, not the npm package `@alexlikevibe/pi-jev` (0.2.1), which does compaction and per-turn model routing only (README, verified). Jev is TypeSafe's typed-answer model; the guard sends tool input (trimmed, about 2,000 chars) and the last user message (about 600 chars) to TypeSafe or OpenRouter, so gate use itself exports command text off-machine (harness README "Limits"). Three implementations exist:

| Implementation | Classifier outputs | Decision | Log |
|---|---|---|---|
| `pi-jev-guard` (`classify.ts`, `index.ts`) | `risk` Score (`read_only`, `reversible`, `hard_to_reverse`, `destructive`) + confidence; `category` Choice (read, search, edit, test_or_build, git, package_manager, network, process, system_config, other); `secrets` Noul; `outside_project` Noul; `in_scope` Noul | code-derived `allow`/`ask`/`deny` (`decide()`); `deny` only for destructive AND `in_scope` below 0.4 | `~/.jev-guard/log.jsonl` |
| `claude-jev-guard` (Claude Code `PreToolUse` hook) | same five questions | same policy, expressed as hook permission decision | same path per README |
| `pi-jev-harness` (compact guard) | `risk` Score and `secrets` Noul only (plus loop control `stuck`/`wrong_approach`) | hard-to-reverse/destructive, secret, or unjudged calls get a confirm dialog, or a block when there is no UI | `~/.jev-harness/log.jsonl` |

**What each log records (source read, and the harness log inspected on disk).**

| Field | Type | Meaning | Join key to ticket | Landed-storage notes |
|---|---|---|---|---|
| `at` | ISO time | Write time of the log line (consumer-independent, machine clock) | time window only | Only clock in either log |
| `harness` (guard log) | string | `pi` for `pi-jev-guard` | none | |
| `mode` (guard log) | `enforce`/`log` | Whether the call could be blocked | none | Filter `log` mode out of hold counts: no hold occurred |
| `tool`, `input` (guard log; input is a truncated summary, not raw) | string | Tool name and shortened input | none | Summary can still contain command fragments; treat as sensitive |
| `risk`, `riskScore`, `riskConfidence`, `category`, `categoryConfidence`, `secrets`, `outsideProject`, `inScope`, `ms`, `inputTokens` (guard log) | enum / float | The classification | none | Grain: one classified call. `inScope` is the only "off-task/out-of-scope" signal |
| `decision`, `reason` (guard log) | `allow`/`ask`/`deny` + text | The verdict | none | `ask` means a hold was raised; it does **not** say whether the human approved |
| `what`, `ms`, `tokens`, `answers` (harness log; verified on disk: 2 lines, keys `at, what, ms, tokens, answers`; answers hold `risk` `{type, score, legend, probabilities, confidence}` and `secrets` `{type, noul}`) | mixed | Raw Jev answers only | none | **No verdict, no tool name, no input, no session, no cwd.** The hold decision is recomputed from thresholds in code, and `guardAsked`/`guardBlocked` counts live only in memory (`/jev-harness` stats) |

Answers to the ticket's two questions:

1. **Is there a log of holds/judgments?** Yes for classifications and `allow/ask/deny` (guard log; not present on this machine: `~/.jev-guard/` does not exist, so the guard has never run here). The harness log has classifications but not the resulting hold. Neither log carries a session id, tool-call id, cwd, or ticket; the only join is a time window against pi session message timestamps.
2. **Are outcomes (right/wrong call) recorded?** **No.** In `pi-jev-guard/index.ts` the decision is logged (`logClassification`) before `askHuman`, and nothing is logged after the human answers; the confirm result (approve/decline) is not persisted. A decline is recoverable only from the pi session `toolResult` text ("The user declined this call ..."), and an approved hold is indistinguishable from an allowed call. Whether a hold was correct needs a human label that no tool captures. (The local pi sessions contain no `jev-guard`/`jev-harness` block messages, consistent with the guard not having produced holds on this machine.)

Category mapping to the brief's four classes (an interpretation, to be fixed in #26): irreversible ~ `risk` in `hard_to_reverse`/`destructive`; mutating ~ `risk` >= `reversible` or `category` in edit/git/package_manager; off-task and out-of-scope are **not separable**: `in_scope` (serves the current request) and `outside_project` (touches files outside cwd) are the two nearest outputs. The harness guard cannot produce the last two at all.

## 5. GitHub

Fields verified against the OpenAPI description (`github/rest-api-description` main@c624b95, v1.1.4) and live calls on `climate-indices/climate-indices-cloud` (public, default branch `main`).

| Field / endpoint | Type | Meaning | Join key to ticket | Landed-storage notes |
|---|---|---|---|---|
| `GET /repos/{o}/{r}/issues/{n}`: `number`, `created_at`, `closed_at`, `state`, `state_reason` (`completed`, `reopened`, `not_planned`, `duplicate`), `parent_issue_url`, `sub_issues_summary`, `issue_dependencies_summary` | mixed | Issue lead time = `closed_at - created_at`; `state_reason` distinguishes completed from not planned | the issue number is the ticket | Snapshot per issue per day; `closed_at` is overwritten on re-close |
| `GET /repos/{o}/{r}/issues/{n}/events` and `/issues/events` (`event`, `created_at`, `actor`, `commit_id`) | mixed | `closed`, `reopened`, `merged`, `ready_for_review`, `review_requested`, `head_ref_force_pushed`, `referenced`, `cross-referenced` are on the documented event-types page (`reopened` confirmed there). The live API also returns `blocked_by_added`, `sub_issue_added`, `parent_issue_added`, `added_to_project_v2`, `project_v2_item_status_changed`, which are **not on that page** | issue number | Reopen count = number of `reopened` events; treat the undocumented types as unstable |
| GraphQL `Issue.timelineItems(itemTypes:[PROJECT_V2_ITEM_STATUS_CHANGED_EVENT])` -> `ProjectV2ItemStatusChangedEvent{createdAt, previousStatus, status}` | object | Board Status history with values (the REST `project_v2_item_status_changed` event carries none: keys are only `actor, commit_id, commit_url, created_at, event, id, issue, node_id, url`) | issue number | Verified live. **Coverage caveat:** issue #6 shows Status "In Progress" on the board but its timeline holds only the initial `Todo` event, so this is not a complete history (cause UNVERIFIED) |
| GraphQL `ProjectV2Item.fieldValues`: `Agent` (single select), `Estimate` (number), `Actual` (number), `Status`, `Epic`, `Milestone (M1-M5)`, each with `updatedAt` | mixed | Board attribution and estimates; field set confirmed live | issue number | `updatedAt` is only the last edit, so "Estimate recorded before start" is checkable only if the Estimate was not edited later |
| `GET /repos/{o}/{r}/pulls/{n}`: `created_at`, `merged_at`, `closed_at`, `additions`, `deletions`, `changed_files`, `commits`, `draft`, `merged_by`, `merge_commit_sha`, `head.ref` | mixed | PR cycle time = `merged_at - created_at`; PR size = `additions + deletions`, `changed_files` | `head.ref` (branch), closing references (`closingIssuesReferences`, live), commit trailers | Snapshot at merge. Merging stays human (brief), so cycle time includes the maintainer's wait |
| `GET /repos/{o}/{r}/pulls/{n}/commits` then commit message trailers `Ticket: #N`, `Agent: <...>` | text | Per-commit ticket and agent attribution | trailer | Merge commits made by GitHub carry no trailers (5 of 15 commits on `origin/main` at ab7d7f5 are merge commits with none; 9 carry `Ticket: #N`; 1 bootstrap commit says "none (repo bootstrap)"); attribute from the PR's own commits, not the merge commit |
| `GET /repos/{o}/{r}/pulls/{n}/reviews`, `requested_reviewers`, events `ready_for_review`, `review_requested` | mixed | Review latency and draft-to-ready time | PR number | Optional |
| `GET /repos/{o}/{r}/actions/runs` (`run_attempt`, `conclusion`, `head_sha`, `event`, `created_at`, `run_started_at`, `pull_requests`), `.../actions/runs/{id}/attempts/{n}`, `GET /commits/{ref}/check-runs` (`conclusion` enum `success`, `failure`, `neutral`, `cancelled`, `skipped`, `timed_out`, `action_required`; `started_at`, `completed_at`) | mixed | CI first-pass = PR whose first pushed head SHA had `run_attempt == 1` and `conclusion == success` | `head_sha` to PR | **Nothing to read today: 0 workflows, 0 runs, empty `statusCheckRollup` on all sampled PRs.** See retention below |
| Revert detection: `GET /commits/{sha}/pulls`; commit subject `Revert "<subject>"` and body `This reverts commit <sha>` (git `sequencer.c` L5782-5797); GitHub's Revert button creates a new PR (docs "Reverting a pull request") | text | No `reverted` event or boolean exists in the REST schema or the event-types page | PR number of the reverted change | Heuristic only: string match, then map the reverted SHA to its PR |

**Retention (time-critical).** GitHub docs (fetched 2026-09-24, `configuring-the-retention-period-...`): checks, workflow runs, commit statuses, artifacts, and logs default to 90 days; **from 2026-10-01 the policy applies to checks, workflow runs, and commit statuses too** (until then 400+ days), and a public repository may set at most 90 days. The library repo `monocongo/climate_indices` has 2,969 workflow runs going back to 2025-12-24, which is the brief's baseline dataset for the 3.0.0 cycle; whether runs older than 90 days are purged on 2026-10-01 is UNVERIFIED, but the CI first-pass history for that baseline should be snapshotted before then. The Events API feed is limited to 30 days and 300 events (`/en/rest/activity/events`), so land from the per-issue and per-repo event endpoints, not the activity feed.

## Metric Derivation

"Today" means: computable from fields that exist and are captured or capturable now, with no new tool.

| E8 metric (brief) | Computed from | Computable today? | Caveats |
|---|---|---|---|
| Issue lead time | GitHub issue `closed_at - created_at`; work-start variant from board `Status` history (`ProjectV2ItemStatusChangedEvent`) | Yes (creation-to-close). Start-to-close only partly | Board status timeline was incomplete for #6 (see section 5); definition of "start" belongs to #26. Reopened issues need a rule (first close vs last close) |
| PR cycle time | PR `merged_at - created_at`; optionally `ready_for_review` event, first review | Yes | Merging is human, so the number includes maintainer wait; not an agent-only figure |
| Weekly throughput | Count of PRs by ISO week of `merged_at`; issues by `closed_at` with `state_reason=completed` | Yes | Week boundary and time zone are #26 decisions |
| PR size | `additions`, `deletions`, `changed_files`, `commits` on `GET /pulls/{n}` | Yes | Docs-only PRs dominate today; generated files inflate size. Agent-reported lines (`lines_of_code.count`, pi `edit` diffs) are not comparable across tools, so GitHub is the metric of record |
| CI first-pass rate | Workflow run `run_attempt == 1` and `conclusion` for the PR's first-pushed `head_sha`; or check runs per SHA | **No.** 0 workflows and 0 runs in this repo (E1 has not delivered GitHub Actions); PR `statusCheckRollup` is empty | Once CI exists: define "first pass" as attempt 1 of the first push, so force-pushes and reruns are handled. Data older than 90 days is deleted (public repo, from 2026-10-01) |
| Reopen rate | Count of `reopened` issue events (and `state_reason=reopened`) over issues closed | Yes | Zero `reopened` events in this repo so far, so the rate is 0/N until a real one occurs |
| Revert rate | Heuristic: commit subject `Revert "..."` or body `This reverts commit <sha>`, mapped to the original PR with `GET /commits/{sha}/pulls` | **Only heuristically** | No structured field; a manual revert with a free-form message is missed |
| Bugs traced to closed stories | Would need a convention (for example `Fixes #N` on a bug that names the story, or a label) | **No** | No native field or link type; needs a #26 convention |
| Tokens per ticket | Claude: `claude_code.token.usage` or `api_request` events; pi: `message.usage.*` per assistant message plus `usage`/`compaction`/`branch_summary` usage; joined via ticket attribution map | Partly | Claude needs `OTEL_RESOURCE_ATTRIBUTES` at launch and a laptop collector (none built); pi needs a `cwd`-to-ticket map; pi subagent tokens are missing; vendor token types differ (`cacheCreation` vs `cacheWrite`; pi `reasoning` is inside `output`), so normalise before summing. Jev gate tokens are in its own logs (`inputTokens`/`tokens`) |
| Cost per ticket | Claude `cost.usage` / `api_request.cost_usd_micros`; pi `usage.cost.total`; Jev cost = `tokens * $0.042 / 1e6` (constant hard-coded in `pi-jev-harness/index.ts`, README) | Partly | Both vendor figures are estimates, not billed spend (docs: "approximations"; pi computes from configured $/M-token); label the metric "estimated model cost". Subscription logins are not metered per token |
| Active time | Claude `active_time.total` (`user` + `cli`); herdr `working` durations | Claude: partly. pi: not natively | pi has no active-time field; message-timestamp gaps are a guess. The two vendors' definitions differ, so do not add them |
| Human attention minutes per ticket | herdr `blocked` intervals (subscriber-stamped), attributed to a ticket through pane -> `agent_session` -> `cwd` -> branch | **Approximately, and only if a subscriber runs continuously** | (1) no timestamps in events, no replay, no on-disk history; (2) pi shows Jev confirm dialogs as `working`; (3) Claude `blocked` is screen-matched and misses unusual prompts; (4) `idle`/`done` (waiting for the next instruction) is not `blocked`, and CONTEXT.md defines the metric as time "blocked waiting on a human", so idle time is excluded by definition unless #26 widens it; (5) Claude `tool_decision` gives who decided, not wait time |
| Tool-call gate holds | Guard log `decision == ask|deny` (`mode == enforce`) per classified call | Count of holds: partly (needs the guard actually installed; none has run here). Right/wrong outcome: **No** | Harness log has no verdict; neither log stores the human's answer or a ticket |
| Commits and PRs by agent | Trailers `Agent:` on PR commits; Claude `commit.count`/`pull_request.count` as a cross-check | Yes for commits that carry trailers | Trailers depend on the agent following AGENTS.md; merge commits carry none |

## Proposed Landing Mapping

Input to the Iceberg schema decision in #26, not a schema. Assumed target per the brief and ADR-0005: raw files land in S3 (cheap), then Iceberg tables. Every capture point below runs on the maintainer's machine or in GitHub Actions; **none needs the EKS cluster or cluster egress** (ADR-0003).

| # | Source | Fields kept | Landed grain | Natural key | Ticket attribution | Capture point |
|---|---|---|---|---|---|---|
| 1 | Claude Code OTLP metrics | metric name, value, unit, interval start/end, `session.id`, `model`, `type`, `query_source`, `speed`, `effort`, `start_type`, custom resource attributes | one datapoint per series per export interval (delta) | (metric, series attributes, interval end) | custom `ticket` attribute (launch time) | laptop OTel Collector, `awss3`/`file` exporter (option A) |
| 2 | Claude Code OTLP events | `event.name`, `event.timestamp`, `event.sequence`, `session.id`, `prompt.id`, plus per event: `api_request` (model, tokens, cost, duration, request_id), `tool_result` (tool_name, success, duration_ms), `tool_decision` (decision, source), `subagent_completed`, `compaction`, `api_error`, `permission_mode_changed`. **Excluded:** prompt text, `tool_parameters`, `tool_input`, `user.email` | one event | (session.id, event.timestamp, event.sequence) | custom `ticket`; `vcs.ref.head.name` on commit events only if the details flag is accepted | same collector |
| 3 | pi session header | `id`, `cwd`, `timestamp`, file path, `session_info.name` if present | one session | session id | `--name`, else `cwd` -> worktree -> branch | laptop batch reading `~/.pi/agent/sessions/` |
| 4 | pi assistant messages | session id, entry `id`, `parentId`, `timestamp`, provider, model, api, `responseModel`, `stopReason`, error flag, `usage.*`, `usage.cost.*` | one model call | (session id, entry id) | via row 3 | same batch, incremental by byte offset |
| 5 | pi non-message usage | `usage` entries, `compaction.usage`, `branch_summary.usage` (kind, provider, model, usage) | one usage record | (session id, entry id) | via row 3 | same batch |
| 6 | herdr state transitions | `observed_at` (stamped by subscriber), `pane_id`, `workspace_id`, `agent`, `agent_status`, and, resolved at observation, `agent_session` (kind, value), `cwd`, `worktree.checkout_path` | one observed transition | (observed_at, pane_id) | `agent_session` -> row 3 / Claude session; `cwd` -> branch | laptop subscriber daemon on the herdr socket |
| 7 | Jev gate log | `at`, implementation (`guard`, `claude-guard`, `harness`), `tool`, risk/category/secrets/outsideProject/inScope fields, `decision`, `reason`, `inputTokens` or `tokens`. Exclude the `input` summary | one classified call | (at, tool, implementation) | time window against row 4 timestamps; no direct key | laptop batch reading `~/.jev-guard/log.jsonl`, `~/.jev-harness/log.jsonl` |
| 8 | GitHub issues and events | issue fields and event rows from section 5, board field values (`Agent`, `Estimate`, `Actual`, `Status`) and status timeline | issue snapshot; issue event; board field history | issue number (+ event id / snapshot date) | the issue number is the ticket | GitHub Actions scheduled job or laptop `gh`, not in-cluster |
| 9 | GitHub PRs and commits | PR fields, per-commit SHA, parsed `Ticket`/`Agent` trailers, closing references, review events | PR snapshot; PR commit | PR number; (PR number, SHA) | trailers, `head.ref`, closing references | same |
| 10 | GitHub CI | workflow run id, `run_attempt`, `conclusion`, `head_sha`, timestamps; check runs | one run attempt | (run id, attempt) | `head_sha` -> PR -> ticket | same; **snapshot within 90 days** |
| 11 | Derived: attribution map (not a source) | session id (Claude or pi) -> ticket, method (`attribute`, `name`, `branch`, `manual`), valid_from/valid_to | one session-to-ticket assignment | (session id, valid_from) | is the join | built by batch; #26 owns the rule for unattributed work |

`metrics/runs.jsonl` (one per ticket, AGENTS.md convention 3) is a per-ticket rollup of rows 4-6 and 8-9, not a source; its shape and relationship to the Iceberg tables belong to #26.

## Gaps

What cannot be captured today, and why:

1. **No native ticket key in any agent source.** Claude Code OTel needs `OTEL_RESOURCE_ATTRIBUTES` set on the `claude` process at launch; it cannot change mid-session, and OTel exposes no cwd, worktree, or branch (except `vcs.ref.head.name` on commit results with the tool-details flag). pi sessions carry only `cwd`; `--name` and in-band `custom` entries exist but are unused. herdr can carry `ticket` in pane `tokens` but nothing sets it. Work started without a ticket, or two tickets in one session, is unattributable or lossy.
2. **No OTLP endpoint at M1.** ADR-0007 defers any collector to M4 and #26 needs an out-of-VPC endpoint. Claude Code has no file or S3 exporter. The laptop-collector route (option A) is unverified end to end; a hosted ingest (option D) has no reference implementation.
3. **Retention races.** Claude transcripts are swept at 30 days by default; GitHub checks/runs/statuses default to 90 days from 2026-10-01 (public repo max 90); herdr keeps no state history; the GitHub Events feed keeps 30 days. Data not landed inside those windows is gone, including the CI history of the 3.0.0 baseline dataset (2,969 runs since 2025-12-24; purge behaviour on 2026-10-01 UNVERIFIED).
4. **CI first-pass rate is not computable:** the repo has no workflows.
5. **Revert rate and "bugs traced to closed stories"** have no structured GitHub field; revert is a string heuristic, bug-to-story needs a convention.
6. **Cost is an estimate everywhere.** Claude "approximations" (docs); pi computes from configured price per million tokens; subscription logins have no per-token charge. Whether `claude_code.cost.usage` is populated for a subscription login is UNVERIFIED.
7. **pi subagent tokens and cost are missing** from the parent session (0 of 575 local `subagent` tool results carry `usage`); ticket spend is understated wherever subagents are used. Where that spend is logged, if anywhere, is UNVERIFIED.
8. **herdr human-attention capture is approximate:** payload has no timestamp; no replay; a subscriber must run continuously and per pane (`pane_id` required); pi reports `blocked` only via `herdr:blocked` and no Jev extension emits it (guard confirmations count as `working`); Claude `blocked` relies on strict screen matching; `idle` time waiting for the human is not `blocked` by the CONTEXT.md definition.
9. **Jev gate outcomes are not recorded.** No right/wrong label, and the human's approve/decline is not persisted (guard logs before asking; harness logs raw answers only and keeps guard counts in memory). Neither log has a session id, tool-call id, cwd, or ticket. The brief's four classes do not map one-to-one: off-task and out-of-scope are one `in_scope` score. No guard log exists on this machine, so no real hold data exists yet.
10. **"pi-jev" is ambiguous.** The npm package `@alexlikevibe/pi-jev` is not a gate. The brief, AGENTS.md, and #26 should name `pi-jev-guard` (or the harness) explicitly. Both gate repos have no license file.
11. **Jev egress and privacy:** the gate sends command text to TypeSafe or OpenRouter; the Jev service itself was not independently verified.
12. **GitHub event coverage:** `blocked_by_added`, `sub_issue_added`, `added_to_project_v2`, `project_v2_item_status_changed` are returned by the live API but absent from the documented event-types page; the REST status-change event has no status value; the GraphQL status timeline was incomplete for #6. "Estimate before start" is verifiable only if the field was not edited afterwards.
13. **Claude/pi token semantics differ** (cache-write naming, reasoning included in `output` for pi; whether Claude thinking tokens are inside `output_tokens` is not stated in the docs, UNVERIFIED), so cross-tool token totals need a normalisation rule.
14. **Cross-source identity:** whether Claude OTel `session.id` equals the `session_id` given to hooks (and to herdr) is expected but UNVERIFIED.
15. **Volume and cost of S3 landing were not measured** (ADR-0005 headroom is assumed adequate for metadata-only OTLP and JSONL; unmeasured).

## Open Questions

1. Which route lands Claude Code OTLP at M1: laptop collector (A), or accept transcripts only (F) until M4? If A, who guarantees the collector is running?
2. Does the launcher set `OTEL_RESOURCE_ATTRIBUTES=ticket=N` and `pi --name ticket-N` (and herdr pane tokens), and what is the rule for work with no ticket?
3. Is human attention minutes strictly `blocked`, or `blocked` plus `idle`/`done` waiting for a human instruction? This decides whether herdr is sufficient.
4. Does a Jev extension get a small change to emit `herdr:blocked` during confirmation, and to log the human's answer? Who owns changes to `MoonTory` repos?
5. Which of the guard implementations is the E8 source, and is a right/wrong label captured by manual review, and where?
6. Is `Actual` recorded from the board field, the sum of session durations, or both, and how are estimates presented without an "N x faster" claim?
7. Should the 3.0.0-cycle CI history in `monocongo/climate_indices` be snapshotted before 2026-10-01?
8. Confirm `session.id` equality between Claude OTel, hook input, and herdr `agent_session`.

## Sources Consulted

Web and API (read 2026-09-24):

- Claude Code monitoring: <https://code.claude.com/docs/en/monitoring-usage.md>; retention: <https://code.claude.com/docs/en/claude-directory.md>; env in project settings: <https://code.claude.com/docs/en/settings-reference.md>
- pi: <https://github.com/earendil-works/pi>, npm `@earendil-works/pi-coding-agent` 0.87.1, npm `@alexlikevibe/pi-jev` 0.2.1
- herdr: <https://herdr.dev/llms.txt> and the v0.9.1 docs it links (`socket-api.mdx`, `agents.mdx`, `integrations.mdx`, `concepts.mdx`, `session-state.mdx` under `https://raw.githubusercontent.com/herdrdev/herdr/v0.9.1/docs/next/website/src/content/docs/`); <https://github.com/herdrdev/herdr>
- Jev gate: <https://github.com/MoonTory/pi-jev-guard>, <https://github.com/MoonTory/claude-jev-guard>, <https://github.com/MoonTory/pi-jev-harness>, <https://github.com/iefnaf/pi-jev>
- GitHub: <https://github.com/github/rest-api-description> (`descriptions/api.github.com/api.github.com.json`); <https://docs.github.com/en/rest/using-the-rest-api/issue-event-types>; <https://docs.github.com/en/organizations/managing-organization-settings/configuring-the-retention-period-for-github-actions-artifacts-and-logs-in-your-organization>; <https://docs.github.com/en/rest/activity/events>; <https://docs.github.com/en/pull-requests/collaborating-with-pull-requests/incorporating-changes-from-a-pull-request/reverting-a-pull-request>; git `sequencer.c` at <https://github.com/git/git/blob/master/sequencer.c#L5782-L5797>
- OpenTelemetry Collector contrib: <https://github.com/open-telemetry/opentelemetry-collector-contrib/tree/main/exporter/fileexporter>, `.../awss3exporter`
- Note: an automated page summary (WebFetch) wrongly reported `reopened` as absent from the event-types page; the raw page confirms it. No claim here rests on a summarised page.

Local read-only inspection (schema and field names only; no prompt text, commands, secrets, or tokens copied):

- `~/.pi/agent/sessions/**/*.jsonl` (620 files), `~/.pi/agent/extensions/herdr-agent-state.ts`, `~/.pi/agent/settings.json`, `~/.pi/agent/jev*.json`
- `~/.jev-harness/log.jsonl` (2 lines), `~/git/pi-jev-harness/`, `~/.pi/agent/npm/node_modules/@alexlikevibe/pi-jev/`
- `~/.config/herdr/{config.toml,herdr-server.log,session.json}`, `herdr --help`, `herdr api schema --json`, `herdr agent list`, `herdr integration status`, `~/.claude/hooks/herdr-agent-state.sh`
- `~/.claude/projects/*/*.jsonl` (220 files), `~/.claude/settings.json`, `~/.claude.json` (keys only)
- Project ground truth: `AGENTS.md`, `CONTEXT.md`, `docs/capstone/brief.md` (E8 section), `docs/adr/0001`-`0006`, ADR-0007 from `origin/docs/observability-slo` (PR #32, unmerged), issues #6, #15, #16, #18, #26 and the #20 constraint comment quoted in #26.

## Gaps Requiring Manual Verification

1. Run Claude Code against a laptop OTel Collector (`awss3` or `file` exporter) and confirm: `session.count` and `api_request` arrive, `ticket` appears on metrics and events, the final metric interval flushes on exit, and the S3 object volume per day.
2. Open an `events.subscribe` stream on the herdr socket and confirm, per pane, `blocked` transitions for Claude Code (screen detection) and for pi with a confirm dialog, and measure how many transitions are missed or delayed.
3. Install `pi-jev-guard`, force an `ask` and a `deny`, and confirm what is logged and what a decline looks like in the pi session.
4. Confirm whether `claude_code.cost.usage` is emitted for the maintainer's subscription login, and whether Claude thinking tokens are inside `output_tokens`.
5. Confirm where pi subagent (`subagent` tool) model spend is recorded, if anywhere.
6. Confirm whether GitHub purges workflow runs older than 90 days on 2026-10-01 for public repositories, and snapshot `monocongo/climate_indices` CI history first.
7. Determine why the GraphQL status timeline for issue #6 lacks the move to "In Progress", and whether all board status changes are recoverable.
8. Confirm `session.id` (OTel) equals the `session_id` given to Claude hooks and reported to herdr.
9. Verify the Jev service (TypeSafe / OpenRouter Decisions API) terms, data handling, and pricing from its own documentation.
10. Determine how `pi-jev-harness` is loaded into pi on this machine (it is not in `settings.json` packages or `~/.pi/agent/extensions/`).
11. Confirm the herdr plugin event-hook route (`plugin.*`) supports `pane.agent_status_changed` as an alternative to a long-lived subscriber.

