# Review-agent and skill evals

Twenty-nine cases in Claude Code's native `claude plugin eval` layout. Twelve cover the six review
agents, one planted-defect case and one clean control per agent, the same fires/silent pairing
`tests/skills/harness-audit/known-bad/` uses for audit checks. Each case is
`prompt.md` (the ask: an agent case dispatches by `subagent_type`, a skill case invokes by `skill:`), `case.yaml` (a
`scaffold_script` that writes the fixture into the throwaway workspace), and `graders/`:

| grader | type | what it proves |
|---|---|---|
| `agent-fired.md` | `tool_used: Agent` | the session dispatched the agent instead of reviewing inline |
| `contract.md` | `regex` | the report ends in the agent's documented Output Format |
| `finding.md` / `clean.md` | `regex` | the planted defect was found at its file, or the clean control got the clean verdict |
| `criteria.md` | `llm` | the finding is the right one, sized right, with no manufactured extras |

Five for the `tech-humanize` skill (tag `tech-humanize`): three planted cases (English prose,
Thai standup, Thai UI copy), a clean human-written control that must survive lightly edited, and a file-input
case that proves the prose-only constraint (frontmatter and code block byte-identical, graded on
the file's contents). Their `skill-fired.md` is `tool_used: Skill`; their regex graders assert a
planted tell is absent (`not_contains`) or a source specific is kept (`contains`), and the loader
test proves each pattern against the scaffolded fixture.

Two for `post-mortem` (tag `post-mortem`): a complete case whose repo carries the fix commit and
regression test, graded on all 11 sections in order, no hedging, a Rule 4 failure class, and an
LLM rubric for the checklist and anchoring; and a missing-input case that withholds the
validation input and must get a question, not a draft. The skill is user-invoked
(`disable-model-invocation`), so `prompt.md` opens with `/mh:post-mortem` and `skill-loaded.md`
is a `trace` regex on the skill's own text rather than `tool_used: Skill`. Two runner facts are
undocumented and the first live run settles both: whether a slash command in `prompt.md` is
expanded, and whether `target: trace` is accepted (these are the only two graders using it).

Two for `harness-audit` (tag `harness-audit`): a planted fleet with two CRITs (skill name
mismatch, missing `tools:` grant) that the session must fix and confirm with a second run
(`audit-reran.md` is `tool_used: Bash`, min 2; file graders check the fix landed in the named
file), and a clean control that must get no edits (`no-edits.md` is `tool_used: Edit`, max 0; `max`
is this suite's first use of the key and unverified against the runner, so `fleet-unchanged.md`
proves the same thing on the file's bytes).
The scaffolded repo is its own plugin cache (`--plugin-cache .`). Bash is not granted by
default: run these with `--allow-tools Bash` (the prompt frontmatter also lists it).
Two for `ideate` (tag `ideate`): a full run on an open design problem, bounded on Agent calls
(`fanout.md`, `tool_used: Agent` min 6 max 8: 8 on the host path, 6 when the critic deepens) and
graded on the rendered output shape (score chips, ★ pick, provocation line); the isolation
invariant and wave shape are not observable from these graders; and an abort control, a
"quick"/"canonical" question that must fail the pre-flight gate and get a direct answer with no
Agent call at all (`no-fanout.md`, max 0).

Two for `memory-lint` (tag `memory-lint`): a planted store with one repairable finding per
detector class (typo'd wikilink, stale pointer, unindexed unreachable file) that the session must
fix at the cause and confirm with a second run (`lint-reran.md` is `tool_used: Bash`, min 2; file
graders prove the link was corrected not deleted, the stale pointer removed not satisfied by a new
file, and the unindexed file indexed), and a clean control that must receive no Edit or Write (`store-unchanged.md` proves the index bytes as well).
Bash is not granted by default: run these with `--allow-tools Bash` (the prompt frontmatter lists
it too).

Two for `deep-audit` (tag `deep-audit`): the scaffold is a small git history that is the
"session" under audit. In the planted case the second commit and `NOTES.md` claim a zero-total
guard and a regression test; the commit's diff is a docstring and the suite has no zero-total
case, so the re-run is green with one test and the claim is false on the diff. The case grades
the audit's process (git-derived scope, rubric, checker dispatch, test-first fix, re-score), not
detection difficulty. The clean case makes the same claims truthfully and must come out
byte-identical. Graders check the skill and a checker agent fired, git and the test runner ran
(`tool_used: Bash` anchored on the command), the fix and its test landed in the named files, and
the report opens with the Final Verdict line. Needs `--allow-tools Bash,Edit,Write`.

Two for `cost-report` (tag `cost-report`): a planted log with a session whose two rows must
collapse to the newer one (latest row per key, then sum: $10, where a hand sum gives $15) and one
legacy-era row that makes the script print a `note:` line the read-back must carry; and a
not-set-up control with no log, which must relay the script's "Cost tracker not set up" line,
quote no dollar figure, and create no log (`no-log-created.md` is `tool_used: Bash` max 0 on a
redirect into `costs.jsonl`; Write and Edit are not granted). The prompt points the script at the
workspace log with `MH_COSTS_FILE`, since the sandbox HOME is fresh and case `env` keys must be
`EVAL_*`. Needs `--allow-tools Bash`.

Run (needs `plugin eval` early access on the account; 2.1.263 prints "currently in early access"
otherwise):

```bash
claude plugin eval . --scaffold --runs 1 --no-publish
claude plugin eval . --scaffold --tag silent-failure-hunter --runs 1 --no-publish
claude plugin eval . --scaffold --tag harness-audit --allow-tools Bash --runs 1 --no-publish
claude plugin eval . --scaffold --tag memory-lint --allow-tools Bash --runs 1 --no-publish
claude plugin eval . --scaffold --tag ideate --runs 1 --no-publish     # the run case spawns 6-8 agents
claude plugin eval . --scaffold --tag deep-audit --allow-tools Bash,Edit,Write --runs 1 --no-publish
claude plugin eval . --scaffold --tag cost-report --allow-tools Bash --runs 1 --no-publish
```

`--scaffold` is required: the fixtures live in each case's `scaffold_script`.
`tests/evals/test-eval-cases.sh` checks the cases statically (files present, scaffold scripts run
and produce the fixture files, regex graders compile, and each `contract.md` / `clean.md` regex
matches a verdict sample in the shape the agent actually emits: bare, bold, or after a
`Verdict:` label) so the suite stays loadable while the runner is gated. Results land in `evals/results/`, gitignored.
