---
name: cost-report-planted
tags: [cost-report, planted]
runs: 1
max_turns: 10
timeout_seconds: 300
allowed_tools: [Bash, Read, Glob, Grep, Skill]
---
Use the `mh:cost-report` skill (Skill tool, `skill: "mh:cost-report"`) to report Claude Code spend for this workspace. The tracker log for this workspace is `metrics/costs.jsonl`, not the default location, so run the report with `MH_COSTS_FILE=./metrics/costs.jsonl` in the environment. Bash is needed to run it.

Read the spend back the way the skill says: quote the report's `total:` line verbatim, and say what any `note:` line means for that total.
