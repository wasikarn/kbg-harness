---
name: deep-audit
description: "Deep-audit: post-implementation audit — verify every claim, score before/after, fix evidence-backed gaps, re-score. Use after an implementation pass. Don't use for a first-pass review (mattpocock-skills:code-review)."
model: inherit
effort: xhigh
---

Audit everything implemented or changed in this session as if someone else built it. The
session output is a set of claims; each one is true only once evidence outside the model's own
memory says so.

## 1. Reconstruct scope from the tree, not from memory

Scope is what git shows, since a compacted session remembers a retelling, not the work. Find
the session's first commit from the reflog or the session start time, then list:

```bash
git log --oneline --since="<session start>"        # or <first-sha>^..HEAD
git diff <first-sha>^..HEAD --stat; git status --porcelain
```

Uncommitted-only work is the diff alone. Add files edited outside git (memory store, settings,
sibling repos) by name. Then read the diff and trace how the pieces work together end to end,
noting assumptions, implicit behaviour, and anything the session claimed but never ran. Done
when every changed file is listed with the session's claim about it and your own note on it.

## 2. Score the baseline on the fixed rubric

Score each dimension 0–10 from evidence and take the weighted average (weights sum to 10);
pass is 7.0 or more with no dimension under 5. Same rubric every run, so runs compare.

| dimension | weight | evidence that earns the score |
|---|---|---|
| Correctness | 3 | tests, checks, or a reproduced command exit code |
| Completeness | 2 | every item of the request traced to a file or an explicit "left out" |
| Claim accuracy | 2 | each claim in commits, docs, and replies re-run or re-read |
| Regression safety | 2 | gauntlet or equivalent green; sibling callers of changed code checked |
| Simplicity | 1 | no abstraction, file, or line without a caller or a reader |

Evidence is read in the operating-model order: deterministic result, then this run's
trajectory, then rollback history, then model confidence last. A dimension with no evidence is
marked **insufficient evidence**, left out of the total, and named in the report for the operator to
decide; a guessed score is worse than none (Rule 14).

Claim accuracy is scored on whether the claim was true when made; later evidence that makes it
true is separate current-state work.

## 3. Hunt gaps with a fresh-context checker

The maker never grades its own work (`docs/reference/operating-model.md`). Dispatch one
read-only fresh-context agent (`Explore`, or a review agent when the work fits one) in the
`docs/reference/spawn-brief.md` shape, with the scope list and notes from step 1 and this brief:
assume the session is complacent; find what it missed
across correctness, edge cases, failure modes, hidden assumptions, regressions, missing checks,
consistency between files (doc versus code, two docs disagreeing), and drift between intent and
code; every finding cites one checkable fact (a path, a command,
a line). It returns `{pass, findings[], scope_ok, unexpected_files[]}`.

Reconcile its findings with your own. A finding survives only with a concrete trigger; a
speculative "consider X" is dropped. Rank survivors by severity, impact, likelihood, confidence,
and effort. Zero survivors is a valid result: an already-high baseline is a legitimate baseline,
and only evidence separates "nothing worth fixing" from "under-audited".

## 4. Confirm, then fix

Present the ranked findings and confirm with one **AskUserQuestion**:

- `Apply all fixes now` (findings low-risk and inside the session's scope)
- `Apply only some` (a finding is out of scope or needs its own decision); ask which
- `Skip fixes, report findings only` (review-only pass); go to step 6 with the baseline as both scores

Skip the ask only when the same turn already said "audit and fix"; an earlier or implied
authorization is not that.

Each fix names its failure class (Rule 4: missing_context, bad_tool_contract, missing_guardrail,
weak_verification) and lands test-first where a test can express it. Every change carries a
quality rationale; a change that only moves the score is left out.

## 5. Re-verify

- Re-run the tests and checks the fixes touch, plus the repo gate (`scripts/run-gauntlet.sh` or
  the project's equivalent).
- Check each fix's own mechanism for a new regression before scoring its dimension resolved: a
  fix for one problem can reopen another, and a test that only documents the new behaviour
  hides that. Close a self-inflicted regression in the same pass when it is cheap.
- A fix touching 2+ files or a test gets the fresh-context validator again (Rule 13).

## 6. Re-score on the same rubric

Report before, after, absolute delta, and percentage, per dimension and overall. When a baseline
is zero or near it, give the absolute delta and say the percentage is not meaningful.

An improvement counts only when post-change evidence beats the baseline on the predefined
criteria. If the score did not move, say so and say why.

## Final output

Line one is the **Final Verdict**: pass or fail against the threshold in step 2, with the
reason and a confidence level, stated plainly. Then:

1. Baseline score (per dimension, weighted total)
2. Findings, with the checker's and your own marked
3. Changes made, each with its failure class
4. Verification evidence (commands and exit codes)
5. Final score and before → after
6. Remaining risks and **insufficient evidence** dimensions

The report is evidence-backed proof of whether the work improved, written for a reader who
did not watch the session.
