---
name: cost-report-clean
tags: [cost-report, clean]
runs: 1
max_turns: 8
timeout_seconds: 300
allowed_tools: [Bash, Read, Glob, Grep, Skill]
---
Use the `mh:cost-report` skill (Skill tool, `skill: "mh:cost-report"`) to report Claude Code spend for this workspace. The tracker log for this workspace would be `metrics/costs.jsonl`, not the default location, so run the report with `MH_COSTS_FILE=./metrics/costs.jsonl` in the environment. Bash is needed to run it.

Report what the skill reports.
