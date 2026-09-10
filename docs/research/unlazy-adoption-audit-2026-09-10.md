# unlazy adoption audit (2026-09-10)

**Correction (2026-09-10, `mh:deep-audit`):** "The finding that overturned P1" section below
claimed Claude Code does not overwrite a plan-mode file reused within a session, verified on CC
2.1.267. That claim is **false** — a `mh:deep-audit` fresh-context Codex checker plus direct
transcript re-verification found four separate sessions (2026-07-07, 08-23, 09-08, 09-10,
CC 2.1.263-267) where a later plan-mode entry in the same session overwrote the existing plan
file in place, including the session behind the original 2026-08-23 incident itself — contrary to
this doc's claim, that session's log does exist and directly reproduces the overwrite. The
session cited below as evidence (`ccf0f177`) was also misread: its "second distinct file" was a
retry after the *first* attempt was rejected (not two approved plans), and that second file was
itself overwritten 4.5 minutes after approval. Net effect: the plan-seal sensor's premise is
**not dead** — it's re-opened, not revived (a build decision, out of audit scope). Everything
else in this doc (item 1, the spawn-brief Done-when change) is unaffected and still stands.

---

Source: a Thai-language article summarizing [`Leonxlnx/unlazy`](https://github.com/Leonxlnx/unlazy),
an open-source Claude Code/Codex skill, plus one `WebFetch` of the live repo. No local clone, no
pinned revision — the repo carries no release tag as of this read. Every claim below about
unlazy's internals is what the article/repo describes as of this read, not a verified fact about
the project as it exists today or in the future.

## What unlazy does (as described)

An agent writes `GATES.md` before starting work: each gate has `CHECK:` (a real shell command)
and `EXPECT:` (a literal string required in that command's output) plus optional `CWD:`. An
evidence hash binds `CHECK`+`EXPECT`+`CWD` together with the exit code and captured output, so
loosening the criteria after the fact invalidates prior "passed" evidence even if the checkbox
stays ticked. `gate-check.mjs` has `--status` (read-only), default (dry-run preview), `--approve`
(executes for real, no sandbox, full user privileges), `--reverify` (reruns every gate). An
optional Stop-hook blocks a premature "done" turn, releasing after 6 consecutive no-progress
blocks. The developer's own current docs (`references/method.md`) retract an earlier claim (still
in the README) that decomposition depth mathematically multiplies effort — current docs call it a
"signal," not a guarantee, and say the original benchmark numbers were never preserved.

## Process

Two agents ran in sequence. `mh:code-architect` (fresh context, read-only) analyzed mh's actual
hooks/gates/doctrine against unlazy's mechanism and proposed 4 adoption candidates, scored by
Rule 14. `mh:plan-reviewer` (fresh context) then adversarially attacked that analysis against the
live repo and found 13 issues — several load-bearing, including one that changed the ranking
(retiring an "unverified precondition" the memory store had already answered). During plan-mode
drafting, a further primary-evidence check (below) overturned the critic's own top pick.

## Scoring table (as corrected by the critic's pass)

| # | Proposal | Gap | Fit | Blast⁻¹ | Cost | Ev | Score |
|---|---|---|---|---|---|---|---|
| P3 | EXPECT-literal clause in Done-when | 4 | 5 | 4 | 4 | 4 | ~4.40 |
| P2 | Promote Done-when to METHODOLOGY | 3 | 5 | 4 | 5 | 3 | 4.00 |
| P1 | Plan-text seal for compliance-audit | — | — | — | — | — | dead (see below) |
| P4 | Stop-tier "done claimed, unverified" sensor | 2 | 3 | 2 | 2 | 2 | 2.25 — below bar |

P1's premise (below) died after this table was built, so it has no meaningful re-score.

## The finding that overturned P1: the plan-file-reuse claim is stale

`skills/review/compliance-audit/SKILL.md` (pre-edit) said: "Claude Code reuses one plan file per
session, so a later unrelated plan-mode entry silently overwrites the one you meant to audit."
The critic's recommended build (a `PostToolUse:ExitPlanMode` sensor sealing plan text, to detect
an agent quietly loosening its own approved criteria) rested on this race being real and current.

Checked against `~/.claude/plans/` and session transcripts under `~/.claude/projects/` (installed
CC: 2.1.267): session `ccf0f177` (2026-09-08) entered plan mode twice, roughly 18 minutes apart,
and CC wrote two distinct, uniquely-named files — both still on disk, neither overwritten.
Seventy-six uniquely-named plan files coexist under `~/.claude/plans/` across many sessions.

What this shows and doesn't: it disproves "always overwrites" as *current* behavior. It does
**not** confirm or deny that the 2026-08-23 incident behind the doc's claim happened as described
— there's no log reaching back to that date to check. The doc's stated mechanism (single-file
reuse) does not hold under 2026-09-08 observation. That's enough to drop the sensor's premise from
confirmed to unconfirmed-at-best — not worth building a `hooks.json` entry, a hook-registry
entry, tests, and canary coverage on. YAGNI.

## Shipped

1. **`docs/reference/spawn-brief.md`** — `Done-when` gains the EXPECT half: exit status plus a
   task-relevant assertion (literal string, count, or structured field), with an explicit warning
   that exit 0 alone isn't evidence and a file existing isn't evidence. Kept intentionally short,
   consistent with the file's own "short on purpose" framing — this is the one genuinely new idea
   from unlazy that mh didn't already have (mh's existing `Done-when` field was already
   `CHECK`-shaped; it lacked the `EXPECT` half).
2. **`skills/review/compliance-audit/SKILL.md`** — corrected the stale plan-file-reuse rationale
   in three spots (Phase 1 step 1, step 5, Anti-Patterns). Both rules survive with corrected
   reasoning: "don't trust mtime" still holds (multiple plan files can exist per session, so
   newest isn't necessarily the approved one); "never enter plan mode to gate audit scope" still
   holds (plan mode is read-only, blocking the worktree pin and gauntlet run), just not for the
   overwrite reason originally given.

This increments on a prior recorded judgment, not a relitigation of it:
`docs/research/harness-engineering-checklist-article-audit-2026-09-07.md:16` already scored
"success defined before execution" as covered (`spawn-brief.md` Done-when, requirement-analyst
readiness, Rule 3) at "advice" tier — the EXPECT-literal clause is the increment that audit never
tested, not a rediscovery of row 1.

## Deliberately not shipped

- **Plan-seal sensor (`PostToolUse:ExitPlanMode`)** — premise unconfirmed/contradicted, see above.
  No incident behind the residual threat (an agent editing its own approved plan to loosen
  criteria). YAGNI.
- **Promoting Done-when into `docs/METHODOLOGY.md`** — real but narrow gap: main-session,
  non-delegated, sub-plan-mode multi-step work has no pre-declared criteria requirement today.
  Rule 13 (delegation) is the wrong home; Rule 3 (interrogate the incoming claim) is closer, but
  placement was already flagged as "needs a real decision, not a default" in
  `docs/research/loop-graph-engineering-trend-audit-2026-08-02.md:451` (pre-rebuild, cite as prior
  judgment only). `METHODOLOGY.md` is 3,493 of a hard 4,096 bytes
  (`git-hooks/pre-commit:47-50`), injected into every session — 603 bytes of headroom, and this
  isn't the decision that should spend it. Deferred, not rejected.
- **Blocking Stop-hook with a 6-block release counter** — the first-pass analysis rejected this on
  the wrong grounds ("no autonomous loop" per `operating-model.md:80-85`), which actually objects
  to a *prompt-based, transcript-only evaluator* — mh already tolerates an operator-typed `/goal`
  blocking a turn's end that way. What actually holds: a premature "done" claim is fully
  recoverable (the operator types another message) → advice tier, not the deny set. Mechanically:
  both existing Stop hooks (`hooks/stop/cost-tracker.sh`, `hooks/stop/memory-audit-commit.sh`) are
  `async: true` and cannot return a blocking decision; `Stop` has no confirmed `additionalContext`
  support anywhere in this repo or its docs; a synchronous blocking Stop hook would need a
  `stop_hook_active` loop guard with zero precedent here.
- **A standalone `GATES.md` artifact** — `harness-audit`'s 30 checks under
  `skills/meta/harness-audit/scripts/checks/` already are acceptance criteria as executable
  predicates (exit code = CRIT count). Ranked lowest of four candidates in the 2026-08-02 audit;
  nothing here changes that call.
- **unlazy's `--approve` executor** — as described, a sidecar shells out agent-authored commands
  *outside* the Bash tool, so `gate:bash:irrecoverable` never sees them and every deny in
  `docs/reference/operating-model.md`'s table is bypassed by construction, at full user privileges
  with no sandbox. If mh ever executes a criterion command, it routes through the Bash tool.
  Non-negotiable.
- **Depth Tree / effort-multiplier claim** — the developer's own current docs retract it and say
  the supporting numbers were never preserved. A retracted borrowed claim, per Rule 3.
- **`agents/performance-optimizer.md:159` sweep** — its own `## Done-when` section is agent-level
  completion prose ("targeted metric moved, measured before and after"), already stronger than the
  exit-code-shaped baseline this pass hardens. No fleet-cohesion sweep needed.

## Open questions

- Does the sub-plan-mode Done-when gap (main-session, non-delegated work) eventually justify a
  Rule 3 sentence, or does Rule 1's existing plan-mode routing already cover enough of it in
  practice? Left open.
- The `compliance-audit-overwrites-plan-file-2026-08-23` memory needs a drift annotation — noted
  as a follow-up, tracked outside this repo in the operator's memory store.
