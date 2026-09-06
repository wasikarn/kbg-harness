# "Harness Engineering: How to Build AI Agents That Don't Fall Apart" vs mh (2026-09-07)

**Source:** @0xwhrrari, x.com article 2093685107534000560, published 2026-08-29. Read in full
from the operator's llm-wiki clipping.

**Verdict:** a restatement of sources mh already audited (Böckeler 2×2 2026-04, OpenAI
"Harness engineering", Anthropic long-running-apps harness, loop-trend audit 2026-08-02). No
wrong or dangerous claim (contrast the exit-code-2 claim in the @0xCodez roadmap). No new
architecture. Its closing 12-item checklist is a usable mirror; mh covers 10/12, two small
residuals shipped in v1.1.23, one stays open by choice.

## Checklist vs mh

| # | item | mh surface | status |
|---|---|---|---|
| 1 | success defined before execution | `spawn-brief.md` Done-when, requirement-analyst readiness, Rule 3 | advice |
| 2 | map, not manual | CLAUDE.md "Map only", METHODOLOGY ≤4096 B in pre-commit | enforced |
| 3 | tool contract + failure state | every gate owns its error path; `gate-canary.sh` | enforced |
| 4 | isolated from prod | worktrees are Claude Code's own | out of scope |
| 5 | decisions outside the conversation | memory dir, memory-lint, memory-audit-commit, `docs/adr/` | yes |
| 6 | evidence on risky transitions | Rule 14 evidence order, fresh-context validator | yes |
| 7 | irreversible needs approval | `hooks/gates/` irrecoverable set | enforced |
| 8 | retry cap + budget | 3-round cap (Rule 13); no budget ceiling | half |
| 9 | resume after interruption | compaction + doctrine-bootstrap re-inject | native |
| 10 | explain every tool call / change receipt | transcript + `costs.jsonl` | lacked version + commit |
| 11 | failure updates guide/test/tool/policy | Rule 4 + post-mortem failure class | yes |
| 12 | rollback | git, Rule 1 checkpoint | yes |

The article's 7-row failure table folds into mh's 4 classes: LOST DECISION → missing_context,
REPEATED LOOP and UNSAFE ACTION → missing_guardrail, UNKNOWN FAILURE → weak_verification.

## Where the article is weaker than mh

- "The harness decides whether evidence is enough" with no word on LLM-judge circularity; mh
  keeps inferential sensors advisory and enforces with computational checks.
- Its retry loop escalates after 3 attempts but never says the fault is then in the plan
  (mh v1.1.20).

## Shipped (v1.1.23)

- Cost rows carry `mh_version` and `head_commit` (the article's `policy_version` and
  `rollback_point`); null when missing, row written regardless. Test-first.
- Post-mortem template names a memory entry as the fix for a lost decision.

## Left open

- Budget ceiling: `cost-report` is report-only, no halt on overspend. Open since the 2026-06
  gap critique, item 2. No session has yet been hurt by spend; the article's own "smallest
  harness that closes the loop" argues for leaving it until one is.
- Receipt fields `retries` and `tests` would need transcript parsing; not worth it yet.
