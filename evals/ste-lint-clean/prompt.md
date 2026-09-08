---
name: ste-lint-clean
tags: [ste-lint, clean]
runs: 1
max_turns: 12
timeout_seconds: 600
allowed_tools: [Bash, Read, Skill]
---
Use the `mh:ste-lint` skill (Skill tool, `skill: "mh:ste-lint"`) to check `status.md` against ASD-STE100 writing rules. Do not edit the file.

End your final message with the result: either the findings, or a statement that the file is clean.
