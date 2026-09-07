# cost-report data model

Read when changing `../scripts/cost-report-dedup.js` or `hooks/stop/cost-tracker.sh`.
The report itself needs none of this.

## Rows

The tracker appends one JSON row per (model, stream, agent_type) used in the session so far,
tagged `model_scoped: true`. Each row re-derives cumulative totals from the full transcript,
so the latest row per key is the session's current total, not an increment.

```
{ timestamp, session_id, transcript_path, model, model_scoped, dedup_usage, usage_pick,
  stream, agent_type, turns, input_tokens, output_tokens, cache_write_tokens,
  cache_read_tokens, cache_read_per_turn, rate_verified, mh_version, head_commit,
  estimated_cost_usd }
```

- `stream`: `orchestrator` (the main transcript) or `subagent` (each `subagents/agent-*.jsonl`).
- `agent_type`: the Agent tool's `subagent_type` from the sibling `.meta.json`; `unknown` when
  missing; `null` on orchestrator rows.
- `rate_verified: false`: model matched no rate-table entry, priced at the Sonnet rate.
- A separate row shape `{ timestamp, session_id, codex_invocations: {name: count} }` counts
  `codex:*` Skill and Agent calls; it has no model and is summed on its own.
- Older rows carry fields from retired schemas; unknown keys are ignored.

## Eras

| marker | rows | effect |
|---|---|---|
| no `stream` | before 2026-08-07 | orchestrator-only; no subagent spend recorded |
| no `dedup_usage` | before 2026-09-04 | usage summed once per JSONL content-block line: turns, tokens, and cost about 2.4x high |
| `dedup_usage` without `usage_pick: "last"` | v0.68.639 to v0.68.640 | first line per `message.id` kept, a streaming placeholder: `output_tokens` and cost about 39% low |
| `dedup_usage: true, usage_pick: "last"` | v0.68.641+ | one count per API response, final output count |

No legacy era is rewritten. The report prints a `note:` line for each of the two token-count
eras present; the no-`stream` era shows as a missing section instead.

## Aggregation rule

For each session with any `model_scoped` row: take the latest row per
(`session_id`, `stream`, `model`, `agent_type`) and sum across keys. A row with no `stream`
counts as `stream: "orchestrator"`, not a fourth bucket. A session with no `model_scoped` row
falls back to its single latest row. Days bucket by local calendar day.

Every element of that key exists because dropping it double-counted real spend: a streamless
legacy row plus a same-model orchestrator row overcounted one session by $8.07 on 2026-08-07,
and two agent types on one model would collapse into one bucket. `tests/skills/test-cost-report.sh`
pins each element with fixtures whose wrong answers differ from the right one.

## Why node

Report and CSV logic live in one bundled file so macOS, Linux, and Windows run the same code
with no `jq` or `sqlite3` dependency, and the test runs that file directly.
