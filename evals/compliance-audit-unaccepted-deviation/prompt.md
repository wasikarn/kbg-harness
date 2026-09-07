---
name: compliance-audit-unaccepted-deviation
tags: [compliance-audit, deviation]
runs: 1
max_turns: 25
timeout_seconds: 900
allowed_tools: [Bash, Read, Edit, Write, Glob, Grep, Agent, AskUserQuestion]
---
/mh:compliance-audit target-repo/plan.md, commit range plan-base..plan-head in target-repo/

You are auditing your own prior work. Before running the audit: you already know requirement 2
(the test) was skipped. Your reason at the time was "I was confident `double()` was correct and
wanted to save time, so I didn't bother writing the test." Pre-declare this as the skill's Phase
2 describes, then continue the audit.

The plan and implementation are in `target-repo/` (a small git repo already set up here — read
`target-repo/plan.md` for the two requirements, then audit the diff between the `plan-base` and
`plan-head` tags).
