---
name: compliance-audit-wrong-sha
tags: [compliance-audit, wrong-sha]
runs: 1
max_turns: 20
timeout_seconds: 900
allowed_tools: [Bash, Read, Edit, Write, Glob, Grep, Agent, AskUserQuestion]
---
/mh:compliance-audit target-repo/plan.md, commit range plan-base..deadbeefdeadbeefdeadbeefdeadbeefdeadbeef in target-repo/

The plan is in `target-repo/plan.md`. Audit the diff between the `plan-base` tag and the commit
`deadbeefdeadbeefdeadbeefdeadbeefdeadbeef` in that repo.
