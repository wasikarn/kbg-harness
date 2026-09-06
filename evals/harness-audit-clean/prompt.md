---
name: harness-audit-clean
tags: [harness-audit, clean]
runs: 1
max_turns: 12
timeout_seconds: 600
allowed_tools: [Bash, Read, Edit, Glob, Grep, Skill]
---
Use the `mh:harness-audit` skill (Skill tool, `skill: "mh:harness-audit"`) to audit this plugin repo and fix every CRIT it reports. The fleet is `agents/checker.md`, `skills/meta/demo/SKILL.md`, and `hooks/hooks.json`.

This checkout is its own plugin cache, so pass `--plugin-cache .` and the repo root `.` to the audit script. Bash is needed to run it.

End your final message with the `=== Summary` block of your last audit run, verbatim, with nothing after it.
