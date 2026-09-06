# Review-agent evals

Twelve cases for the six review agents, in Claude Code's native `claude plugin eval` layout: one
planted-defect case and one clean control per agent, the same fires/silent pairing
`tests/skills/harness-audit/known-bad/` uses for audit checks. Each case is
`prompt.md` (the ask, dispatching the agent by `subagent_type`), `case.yaml` (a
`scaffold_script` that writes the fixture into the throwaway workspace), and `graders/`:

| grader | type | what it proves |
|---|---|---|
| `agent-fired.md` | `tool_used: Agent` | the session dispatched the agent instead of reviewing inline |
| `contract.md` | `regex` | the report ends in the agent's documented Output Format |
| `finding.md` / `clean.md` | `regex` | the planted defect was found at its file, or the clean control got the clean verdict |
| `criteria.md` | `llm` | the finding is the right one, sized right, with no manufactured extras |

Run (needs `plugin eval` early access on the account; 2.1.263 prints "currently in early access"
otherwise):

```bash
claude plugin eval . --scaffold --runs 1 --no-publish
claude plugin eval . --scaffold --tag silent-failure-hunter --runs 1 --no-publish
```

`--scaffold` is required: the fixtures live in each case's `scaffold_script`.
`tests/evals/test-eval-cases.sh` checks the cases statically (files present, scaffold scripts run
and produce the fixture files, regex graders compile, and each `contract.md` / `clean.md` regex
matches a verdict sample in the shape the agent actually emits: bare, bold, or after a
`Verdict:` label) so the suite stays loadable while the runner is gated. Results land in `evals/results/`, gitignored.
