#!/usr/bin/env bash
# Snapshot a public repository's CI metadata before GitHub's Actions retention cleanup
# evicts it (from 2026-10-01). Metadata only: no logs, artifacts, or job output.
# Needs an authenticated `gh` and `jq`; no other secrets, because the repository is public.
#
# usage, from the repository root: metrics/baseline/snapshot-ci-runs.sh [owner/repo]
#
# ponytail: sequential calls, three tries each (about 3,100 requests for the library, roughly
# 25 minutes). A call that still fails is recorded under `errors`; rerun if any appear.
set -euo pipefail

repo="${1:-monocongo/climate_indices}"
out="metrics/baseline/ci-runs-${repo//\//-}-$(date -u +%F).json.gz"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
mkdir -p "$(dirname "$out")"
touch "$work"/{runs,first_attempts,check_runs,statuses,errors}.jsonl

# allowlisted fields only, so author emails and other payload never reach a public file
run_fields='{id, run_number, run_attempt, name, workflow_id, event, head_branch, head_sha, status,
  conclusion, created_at, run_started_at, updated_at, pull_requests: [.pull_requests[].number]}'
check_fields='{id, head_sha, name, app: .app.slug, status, conclusion, started_at, completed_at}'
status_fields='id, context, state, target_url, created_at, updated_at'

# fetch <endpoint> <jq filter> <jsonl name>: append the filtered rows, or an error row
# after three tries (the first full run lost two calls to connection resets)
fetch() {
  local raw try
  for try in 1 2 3; do
    if raw="$(gh api --paginate "repos/$repo/$1" 2>"$work/stderr")"; then
      printf '%s' "$raw" | jq -c "$2" >>"$work/$3.jsonl"
      return
    fi
    sleep 2
  done
  jq -cn --arg endpoint "$1" --arg error "$(head -c 300 "$work/stderr")" \
    '{endpoint: $endpoint, error: $error}' >>"$work/errors.jsonl"
}

echo "core rate limit remaining: $(gh api rate_limit --jq .resources.core.remaining)" >&2
total="$(gh api "repos/$repo/actions/runs?per_page=1" --jq .total_count)"
gh api --paginate "repos/$repo/actions/runs?per_page=100" \
  --jq ".workflow_runs[] | $run_fields" >"$work/runs.jsonl"
echo "runs listed: $(wc -l <"$work/runs.jsonl") of $total" >&2

# CI first-pass needs the first attempt's conclusion, not the latest
for id in $(jq -r 'select(.run_attempt > 1) | .id' "$work/runs.jsonl" | sort -un); do
  fetch "actions/runs/$id/attempts/1" "$run_fields" first_attempts
done

# check runs and commit statuses are purged with the runs, so keep both for every head SHA
n=0
for sha in $(jq -r .head_sha "$work/runs.jsonl" | sort -u); do
  fetch "commits/$sha/check-runs?per_page=100" ".check_runs[] | $check_fields" check_runs
  fetch "commits/$sha/statuses?per_page=100" ".[] | {sha: \"$sha\", $status_fields}" statuses
  n=$((n + 1))
  ((n % 100)) || echo "SHAs done: $n" >&2
done

jq -n \
  --arg repo "$repo" --arg at "$(date -u +%FT%TZ)" --argjson total "$total" \
  --slurpfile runs "$work/runs.jsonl" --slurpfile fa "$work/first_attempts.jsonl" \
  --slurpfile cr "$work/check_runs.jsonl" --slurpfile st "$work/statuses.jsonl" \
  --slurpfile err "$work/errors.jsonl" '
  ($runs | unique_by(.id)) as $r
  | {header: {
      snapshot_at: $at, repository: $repo,
      endpoints: {
        runs: "GET /repos/{repo}/actions/runs",
        first_attempts: "GET /repos/{repo}/actions/runs/{id}/attempts/1, for runs with run_attempt > 1",
        check_runs: "GET /repos/{repo}/commits/{sha}/check-runs, for every distinct run head_sha",
        statuses: "GET /repos/{repo}/commits/{sha}/statuses, for every distinct run head_sha"},
      api_total_count: $total,
      counts: {runs: ($r | length), first_attempts: ($fa | length), check_runs: ($cr | length),
        statuses: ($st | length), head_shas: ($r | map(.head_sha) | unique | length),
        errors: ($err | length)}},
     runs: $r, first_attempts: $fa, check_runs: $cr, statuses: $st, errors: $err}' |
  gzip -9n >"$out"

echo "wrote $out" >&2
gzip -dc "$out" | jq -c .header
