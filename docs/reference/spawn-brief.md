# Spawn brief

The shape every dispatched subagent prompt takes. Short on purpose; the constraints line is METHODOLOGY Rule 13.

```
# Task: <one line>
[role: builder|validator|fixer|re-validator|research|other]

## What
<the deliverable, in the dispatcher's own words; tracker text paraphrased, never pasted>

## FILES YOU OWN
<explicit paths; everything else is read-only>

## Done-when
<observable: a passing command, a file that exists, a grep that returns 0 hits>

Constraints: stage by explicit path only, never stash/reset/checkout/add -A; delete with `trash`;
return `NEEDS-DECISION <question>` instead of guessing; cite one checkable fact per claim.
```

When the brief goes to Codex (`/codex:rescue`), name the reasoning effort as an invocation flag,
`--effort <none|minimal|low|medium|high|xhigh>` (the set `codex@openai-codex` 1.0.6 validates), never
as a line inside the task text: the rescue agent strips runtime flags from the prompt and a
prose `REASONING:` line reaches nothing. Omitting the flag runs the operator's configured default;
say so when you relay the result. Effort is the dispatcher's call, never the lane's. Empty-diff
handling: `docs/reference/codex-integration-map.md`, "Silent-refusal gotcha".

A validator returns `{pass, findings[], scope_ok, unexpected_files[]}` and nothing else.
