---
name: compliance-audit-plan-mismatch
tags: [compliance-audit, ambiguous-scope]
runs: 1
max_turns: 15
timeout_seconds: 600
allowed_tools: [Bash, Read, Edit, Write, Glob, Grep, Agent, AskUserQuestion]
---
/mh:compliance-audit

Audit whether the recent work matches the plan for it.
