---
name: ste-lint-file-prose-only
tags: [ste-lint, file-prose-only]
runs: 1
max_turns: 12
timeout_seconds: 600
allowed_tools: [Bash, Read, Skill]
---
Use the `mh:ste-lint` skill (Skill tool, `skill: "mh:ste-lint"`) to check `mixed.md`. Do not edit the file.

End your final message with the findings, naming each finding's line number.
