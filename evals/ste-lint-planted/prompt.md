---
name: ste-lint-planted
tags: [ste-lint, planted]
runs: 1
max_turns: 12
timeout_seconds: 600
allowed_tools: [Bash, Read, Skill]
---
Use the `mh:ste-lint` skill (Skill tool, `skill: "mh:ste-lint"`) to check `notes.md` against ASD-STE100 writing rules. Do not edit the file — it is report-only.

End your final message with the findings only, including advisory findings: one line per finding, each naming its rule number and line number.
