# unlazy adoption audit (2026-09-12) — fresh drill-down

**Date:** 2026-09-12
**Source:** [`Leonxlnx/unlazy`](https://github.com/Leonxlnx/unlazy), read via a shallow local git
clone pinned at commit `16671491f6679ad9378f52604d3bc2415b4120c7` (2026-09-03T17:31:08+08:00) —
the repo carries no release tag as of this read. This is a deliberately fresh pass: the
2026-09-10 audit (`docs/research/unlazy-adoption-audit-2026-09-10.md`) worked from a Thai-language
article summary plus one `WebFetch`, no local clone, no pinned revision. That pass's own
correction note flags a checkable claim it got wrong by sampling once instead of checking
multiple instances — this pass re-derives everything from the pinned clone and this repo's
current state instead of trusting that doc's conclusions, per its own "How to apply" instruction.
**Verdict:** Ship two one-line, fully reversible prose additions to `spawn-brief.md`; decline
everything else, largely for the same reasons the 2026-09-10 pass already gave, now confirmed
against a full local clone and a live `npm test` run instead of an article summary.

Every claim below about unlazy's internals is what the pinned clone shows as of this read, not a
verified fact about the project as it exists today or in the future.

## Method

Two isolated `general-purpose` agents (Phase 1: Agent A on claims, Agent B on fit against this
repo's live state), no shared context between them, then one adversarial `codex exec` pass
(`model_reasoning_effort=high`, `--sandbox read-only`) re-checking both reports against primary
evidence. This increments on the 2026-09-10 pass rather than relitigating item-by-item; it exists
because unlazy's repo grew substantially since that read (`references/dispatch.md`,
`orchestration.md`, `parallel.md`, `token-economy.md`, `scripts/lib/process-tree.mjs`,
`scripts/lib/regex-worker.mjs`, `scripts/stop-hook.mjs`, a `tests/` directory, `SECURITY.md` all
postdate or were unexamined in that pass) and because that pass's own method (single WebFetch, no
pinned commit) was weaker than this skill's normal bar.

Agent A additionally ran the repo's own test suite live (`npm test`, Node v24.11.1): all 7 suites
passed (`run-tests` 34/34, `dispatch-tests` 27/27, `hardening-tests` 51/51, `stress-tests` 24/24,
`lint-tests` 29/29, `contract-tests` 8/8, `self-check` 15/15).

## Claim-by-claim: what the attacker pass changed

Legend: `MATCH` = claim confirmed against primary evidence · `PARTIAL` = partially confirmed ·
`GAP` = claim not found / contradicted by primary evidence · `N-A` = not applicable to this repo.

| # | Claim | Verified? | This repo's posture | Verdict |
|---|---|---|---|---|
| 1 | Evidence hash binds `CHECK`+`EXPECT`+`CWD` to a gate's approval, excludes id/title | Yes — observed directly (Agent A: `scripts/lib/gates.mjs:445-455`; attacker independently recomputed the SHA-256 with `node -e`, confirmed id/title-invariance and check/expect/cwd-sensitivity) | N-A (mh has no equivalent gate-evidence artifact) | MATCH |
| 2 | Stop hook blocks on unmet gates/dispatch and releases after 6 consecutive no-progress blocks, never runs checks itself | Yes — observed directly (`scripts/stop-hook.mjs:12,198-210`) | mh's two Stop hooks (`hooks/hooks.json:179-199`) are both `async: true`, advisory-only — attacker confirmed this via direct read | MATCH (unlazy) / GAP (as an mh adoption target — see Deliberately not shipped) |
| 3 | "Blocking Stop hook directly contradicts mh doctrine" | Author-asserted (Agent B) | `operating-model.md:80` bans the model **starting** work on its own; `:81-85` explicitly permits an operator-initiated `/goal` using a prompt-based Stop hook — the attacker found Agent B's "direct architectural opposite" framing overstated this. The narrower, correct objection: unlazy's release-after-6-blocks fires automatically, not on an operator's explicit continuation | PARTIAL — corrected below |
| 4 | mh already implements unlazy's Tier→model-routing idea via `CLAUDE.md`'s "Models + efforts" / "Task Dispatch" sections | Author-asserted (Agent B), **falsified as cited** | The project's own `CLAUDE.md` has no such sections — the attacker ran a Python assertion (exit 0) confirming their absence. The underlying point still holds, just from different files: `docs/reference/agent-authoring-conventions.md:35` and per-agent frontmatter (`agents/plan-reviewer.md:6`, `agents/test-gap-analyzer.md:5`); the per-wave cap is `docs/METHODOLOGY.md:21`, not `CLAUDE.md` | PARTIAL — citation corrected, conclusion unchanged |
| 5 | Ownership-lease overlap with closed GH #135/#137 write-allowlist proposal | Author-asserted (Agent B) | Attacker read the actual session transcript recording the 2026-09-07 closure ("Close as superseded", both issues closed same reason) — confirmed as a real historical event, not just a memory-file claim | MATCH |
| 6 | Four-pass self-review "would replace, not supplement" the fresh-context validator | Author-asserted (Agent B), **not supported by the citations given** | `unlazy-src/SKILL.md:60-62` is a builder self-check/fix step; `:51`/`:55` still require independent parent/branch re-verification after it. `operating-model.md:40-44` bans self-grading as an *acceptance* decision, not a builder polishing a draft before an independent validator sees it | GAP — reasoning overreach, decision itself not re-opened by this audit (see Open questions) |
| 7 | No prompt-injection content anywhere in the unlazy repo | Author-asserted (Agent A) | Attacker found the literal string "SYSTEM: injected" in `tests/dispatch-tests.mjs:496,580` — these are regression fixtures proving unlazy *resists* privileged-message injection, not actual injected content, so Agent A's practical conclusion holds, but the blanket phrasing didn't distinguish "no injection attempt" from "the string doesn't appear anywhere" | PARTIAL — no real injection risk, phrasing overbroad |
| 8 | The two candidate `spawn-brief.md` additions are reversible, single-file, and correctly sized against the `METHODOLOGY.md` byte cap | Yes — observed directly (attacker independently ran the byte-count: 3493/4096, matching Agent B's number) | Both candidates land in `spawn-brief.md` (uncapped), not `METHODOLOGY.md` | MATCH |

## Shipped

**v1.1.84**, `docs/reference/spawn-brief.md`:

1. **Done-when** gained a negative-control / independent-measurement clause: *"Exercise a negative
   control before trusting an absence claim (a check that fails on a known-bad input); measure a
   stated number independently before writing it into Done-when as its own proof."* Source:
   `unlazy-src/references/gates.md:101-102` ("test negative controls before trusting absence";
   "measure figures independently"). This tightens the EXPECT-literal clause the 2026-09-10 audit
   already shipped (`spawn-brief.md:16-19`), it doesn't replace it — mh had the "state a real
   assertion" half but not the "and don't just trust a supplied number" half.
2. A new dispatcher-facing line: *"Launch a wave's Agent calls together, before reading any of
   their results: dispatching one, waiting on it, then dispatching the next serializes what
   Rule 13's per-wave cap assumes runs concurrently."* Source: `unlazy-src/references/dispatch.md:28,62`
   ("these refusals catch the serial pattern where a driver launches one leaf, waits for it, and
   only then launches the next"; "do not issue foreground Agent calls one after another"). Rule 13
   and `CLAUDE.md`'s Task Dispatch paragraph say how many per wave, never that they must start
   together — this closes that gap without adding a mechanism, a hook, or a state file.

Both are one-sentence, single-file, no-hook additions — reversible with a one-line diff each,
confirmed non-mechanism by the attacker pass (checked item 4 above).

## Deliberately not shipped

- **Ownership-lease / write-allowlist gate** (`unlazy-src/references/parallel.md:49-65`,
  `scripts/lib/gates.mjs:907-953`) — same shape as GH #135/#137, closed 2026-09-07 as superseded
  by `docs/reference/operating-model.md:86-87` ("no orchestration layer of its own"). The attacker
  independently confirmed the closure happened as described by reading the session transcript, not
  just trusting the memory file. **Premise dead** (per the operator's own 2026-09-07 decision, not
  re-litigated here — reopening it needs an explicit exception per that memory's own instruction).
- **Dispatch-wave JSON state machine** (`scripts/lib/dispatch.mjs`, `dispatch-check.mjs`) — the
  persistent bookkeeping unlazy layers on top of native agent calls is exactly the "orchestration
  layer" `operating-model.md:87` says mh deliberately doesn't build. **Declined on evidence**
  (doctrine: no-orchestration-layer).
- **Blocking Stop hook with a 6-block release counter** (`scripts/stop-hook.mjs`) — the attacker's
  finding (claim 3 above) means the original "direct architectural opposite" framing overstated
  its case; the doctrine does tolerate an operator-initiated blocking loop (`/goal`,
  `operating-model.md:81-85`). What still holds without overstatement: unlazy's release fires on
  *unattended* no-progress, not on an operator's explicit continuation, and mh has zero blocking
  Stop hooks today (both existing ones are `async: true`, `hooks/hooks.json:179-199`) — adding one
  is a real mechanism change with no incident behind it. **Deferred**, not declined-on-doctrine —
  the 2026-09-10 audit's YAGNI call stands, just for a narrower reason than originally stated.
- **Four-pass same-context self-review before returning** (`unlazy-src/SKILL.md:57-63`) — the
  attacker found Agent B's specific "replaces the validator" reasoning unsupported (claim 6 above):
  unlazy still requires independent parent/branch re-verification after the builder's own
  self-check. This audit does not re-open the question of whether mh should add a
  self-check-before-handoff step to Rule 13's spawn-brief flow — it only corrects the reasoning
  Agent B gave for rejecting it. Left as an **open question** below rather than shipped or
  declined, since neither this pass's Phase 1/2 agents nor the attacker were asked to evaluate the
  self-check step on its own merits.
- **`--approve` executor** (shells agent-authored commands outside mh's Bash-tool gate surface, no
  sandbox, full privileges) — unchanged from 2026-09-10, still non-negotiable against
  `docs/reference/operating-model.md`'s gate table.
- **Depth/effort-multiplier claim** — still retracted in unlazy's own current docs
  (`references/method.md:3-5`), consistently so across every file that references it; nothing new
  to adopt or reject here.

## Decision score (METHODOLOGY Rule 14)

| Criterion | Weight | Score | Reason |
|---|---|---|---|
| Primary-source fidelity | 40 | 85/100 | Every mechanically checkable claim about unlazy's own code held up under a full local clone, a live test run, and an independent adversarial re-check (10/10 attacker `checked[]` items corroborated). Docked for 3 real findings: one wrong citation (claim 4) and two reasoning-overreach items (claims 3, 6) — none of which touch a fact about unlazy's own mechanism, all about mh-side inference quality. |
| Architectural fit of what's declined | 20 | 75/100 | The four declined items' end calls hold up, but two of their stated reasons were overstated (claims 3, 6) — the doctrine citations exist and are correctly read in isolation, but Agent B's synthesis drew a stronger conclusion than the cited passages support. |
| Blast radius / reversibility of what's shipped | 15 | 95/100 | Two prose sentences, one file, no hook, no state, no `hooks.json` change; attacker independently confirmed both are single-diff reversible and outside `METHODOLOGY.md`'s byte cap. |
| Cost to ship | 10 | 90/100 | No new tests, no new gate, no fixture pair needed — pure doc prose, consistent with `spawn-brief.md`'s own "short on purpose" framing. |
| Incremental value over the 2026-09-10 pass | 15 | 80/100 | Real, narrow: both shipped items come from repo surface (`dispatch.md`, `gates.md`'s negative-control clause) that didn't exist or wasn't read in the prior pass. Not a large new insight — the headline overlap (ownership leases vs. closed #135/#137) was already the strongest candidate and stays declined. |

Weighted sum: 0.40×85 + 0.20×75 + 0.15×95 + 0.10×90 + 0.15×80 = 34 + 15 + 14.25 + 9 + 12 =
**84.25/100**. Pass threshold 60, fatal-weakness floor: any single criterion below 40% of its own
max, or the entire source side graded `insufficient evidence` — neither triggers here (lowest
criterion is 75/100, source was a full pinned clone with a live test run). **PASS.** Confidence:
high — a full local clone (not an article summary), a live upstream test-suite run, and an
independent Codex adversarial pass that found real, actionable findings rather than a vacuous
`pass: true`/`findings: []` (`checked[]` had 10 entries, all citation-backed).

## Open questions

- **Self-check-before-handoff for mh's own Rule 13 builders** — unlazy's four-pass self-review
  (`SKILL.md:57-63`) was rejected by the 2026-09-10 line of reasoning on grounds this audit found
  overstated (claim 6). Revisit only if a real incident shows a builder handing off avoidable
  errors that a cheap self-check before the validator would have caught — not from re-reading
  unlazy again.
- **Blocking Stop hook, operator-initiated variant** — `operating-model.md:81-85`'s tolerance for
  an operator-initiated `/goal` loop means a *consent-gated* version of unlazy's release-counter
  mechanism isn't automatically doctrine-incompatible the way this audit's predecessor implied.
  Revisit only if the operator asks for a persistent-goal mode with its own explicit Stop-hook
  design — not a reason to build one speculatively.
- Same carry-over as 2026-09-10: does the sub-plan-mode Done-when gap (main-session, non-delegated
  work) eventually justify a Rule 3 sentence, or does Rule 1's plan-mode routing already cover
  enough of it in practice? Still left open; nothing in this pass bears on it either way.

## Round 2 (same day, 2026-09-12): 5-analyst + 5-attacker drill-down

A follow-up pass, same session: 5 isolated `general-purpose` analysts, each assigned a distinct
lens (gates/evidence, dispatch/orchestration, Stop-hook/completion-discipline,
token-economy/model-tiering, testing/hardening + the open self-check question from Round 1),
explicitly briefed on everything shipped/declined above to avoid rediscovery. Then 5 independent
`general-purpose` attackers, one per surfaced ship-candidate, each re-checking the claim against
primary evidence rather than trusting the analyst's citations — same fresh-context-validator
pattern as Phase 2 above, run in parallel instead of as one combined pass.

| # | Candidate | Attacker verdict | Disposition |
|---|---|---|---|
| 1 | Size-cap the file reads in `hooks/gates/test-integrity.py` / `config-write-guard.py` (mirroring `irrecoverable.py`'s `_CMD_LEN_CAP`) | **REJECT** — the attacker ran the actual regexes against a synthetic 13MB file (1.3s vs. an 8s timeout) and found `config-write-guard.py` imports no `re` module at all; the candidate's core mechanism claim was false | Not shipped |
| 2 | `Tier: judgment\|mechanical` marker in `spawn-brief.md` for ad hoc dispatches | **REJECT** — the supporting "~3114 ad hoc dispatches" citation pointed to a line that doesn't contain it; the real number lives in a different, pre-correction doc affected by the known 2.4x cost-counter bug (`orchestrate-cost-round2-shipped-2026-09-04`); the mechanism (a self-applied, unenforced label) also directly contradicts `operating-model.md`'s "the maker never grades its own work" | Not shipped |
| 3 | Partial-wave-launch prose (an Agent call errors before a subagent ever starts — don't read the launched subset as a complete wave) | **SHIP** — gap confirmed absent from `spawn-brief.md`/`operating-model.md`; cheap, no incident behind it but free to state | Shipped, v1.1.85 |
| 4 | Ownership-overlap prose for `FILES YOU OWN` (sequential dispatch when two leaves' owned paths aren't disjoint) | **REVISE → SHIP** — confirmed genuinely distinct from the closed GH #135/#137 write-allowlist gate (that was an enforced mechanism; this is dispatcher judgment, no hook). Original wording ("share a parent directory") would have fired on nearly every wave in a monorepo; narrowed to actual ancestor/descendant/same-file overlap before shipping | Shipped (revised), v1.1.85 |
| 5 | Builder self-check-before-handoff line | **REVISE → SHIP** — doctrine citation checked and held (`operating-model.md:38-44` bans self-grading as the *acceptance* decision, stays silent on a private pre-handoff pass); the memory-file "cuts both ways" framing was an unsupported add-on and dropped from the rationale; the drafted placement (after the fence, as dispatcher-only prose) was a real bug — a builder-directed sentence outside the fenced template never reaches the builder. Moved inside the fence, scoped to `Builder/fixer:` | Shipped (revised), v1.1.85 |
| 6 | Wire `scripts/run-gauntlet.sh` into CI (`.github/workflows/validate.yml` currently runs only plugin-validate + harness-audit) | **REVISE** — diagnosis correct (confirmed: 2 jobs only, real 2026-08-26 hooksPath incident), but undercounted the macOS-only `trash` dependency (18 files, not 12) and missed a second landmine: 3 test files still use the BSD-first `stat -f` fallback order already fixed in production code but never propagated to tests. Not a one-line CI addition | Filed as [#159](https://github.com/wasikarn/matt-harness/issues/159), not shipped this pass |

Two Round-1 open questions were explicitly re-examined rather than left untouched: the
consent-gated Stop hook got a full buildable design (trigger, cap placement, three release
conditions, blast-radius warning) but **still not recommended to build** absent an operator ask;
the self-check-before-handoff question was resolved — shipped, per row 5 above, closing that open
question rather than carrying it forward again.

**Why round 2 mattered:** three of six candidates that read as reasonable, doctrine-citing prose
failed under independent adversarial re-verification for reasons a same-model second read would
likely have missed (a citation pointing at the wrong file entirely; a mechanism verified by
actually running it against synthetic input rather than reasoning about it abstractly). This
confirms the pattern already on record in memory `precedence-claims-need-discriminating-probe`
one level down: fluent, doctrine-citing analysis needs a citation-checking adversarial pass, not
just a second opinion.

<!-- Reserved: a later pass appends a dated correction here, never rewrites the sections above. -->
