# Operating model

Three ideas hold the plugin up. Everything else is a consequence.

## 1. Deny the irrecoverable set computationally; advise on the rest

A hook can deny a tool call before it runs. That is the only place a rule is a guarantee
instead of a hope, so the deny list is kept small and literal: the set of actions no later
step can undo. the PreToolUse entries in `hooks/hooks.json` are the whole list:

| gate | denies or asks |
|---|---|
| `gate:bash:irrecoverable` | `rm -rf`, `find -delete`, `--no-verify`, `hooksPath` edits, `push --force`, `reset --hard`, `clean -f`, discarding `restore`/`checkout`, `branch -D`, `stash drop/clear`, `commit --amend`, `dd`, SQL `DROP`, `git add -A` outside a merge, nested `claude` spawns from a subagent |
| `gate:bash:subagent-git-guard` | `git stash`/`reset`/`clean` from a dispatched subagent |
| `gate:task:complete-separation` | a subagent marking its own task complete |
| `gate:write:test-integrity` | asks before a write that weakens a test |
| `gate:write:config-guard` | asks before a write to Claude Code settings `hooks`/`enabledPlugins` |

Everything not in that table is advice: METHODOLOGY.md text, skill prose, agent guardrails.
Advice is honest about being advice; no doc claims a check enforces a rule unless a file in
`hooks/gates/` does.

Each gate owns its error path, and the policy is written in the gate, not assumed: input it
cannot tokenize asks (`could not safely tokenize`), a missing sibling script denies (exit 2),
and only a missing `python3` allows, announced on stderr (#93). `scripts/gate-canary.sh` proves
every staged gate still allows benign payloads. The table is the contract; the hook type is
not. Claude Code's proposed function hooks (anthropics/claude-code#91870, prototype behind
`CLAUDE_CODE_ENABLE_FUNCTION_HOOKS` since 2.1.260; `claude plugin validate` already lists a
module's hooks and `$` calls on 2.1.263) skip a hook that throws, turn every function hook off
for the session when the hooks worker crashes, and evaluate matchers once before the chain. A
gate ported there must catch and deny on its own error and sit above any hook that rewrites
the event.

## 2. The maker never grades its own work

An LLM cannot reliably judge output it produced in the same context (self-preference bias;
task-completion self-grading tops out near chance). So:

- A builder that touched 2+ files or a test gets a fresh-context validator (METHODOLOGY Rule 13).
- Reviewer agents are read-only (`harness-audit` check 32) and return findings, never a verdict
  that ships the work by fiat.
- `harness-audit` checks 04, 05, 20, 22, 28, 29, 70, 71, 72 are proven against known-bad fixtures in
  `tests/skills/harness-audit/`; the rest are smoke-tested only.
- The five review agents (`plan-reviewer`, `blind-spot-hunter`, `silent-failure-hunter`,
  `requirement-analyst`, `nextjs-reviewer`) have a planted-defect case and a clean control each
  under `evals/`, in `claude plugin eval`'s native layout, graded on their own Output Format
  (`evals/README.md`). The runner is early-access gated; `tests/evals/test-eval-cases.sh` keeps
  the cases loadable until it opens.
- `gate:task:complete-separation` makes the rule mechanical for task state.

The same rule at fan-in: when N subagent outputs feed one synthesis, agreement and conflict are
surfaced explicitly and malformed entries are dropped by a stated rule, not by the synthesizing
model's unaided judgment.

## 3. Score, not feel

An important decision carries stated criteria, weights, a numeric result, a pass/fail reason,
and confidence (METHODOLOGY Rule 14). "Important" means the Rule 1 triad flagged it (one-way
door, wide blast radius) or the user asked for a ranking. Routine calls get one line with the
reason. Insufficient data is marked `ข้อมูลไม่เพียงพอ` and blocked on the operator; a guessed
score is worse than none.

## What this plugin deliberately does not do

- No autonomous loop: the model never starts work on its own; every wave begins with a human.
- No orchestration layer of its own: dispatch shape is one page (`spawn-brief.md`); Claude
  Code's native Agent tool does the rest.
- No response style of its own: the `ponytail` plugin is the only style layer.
