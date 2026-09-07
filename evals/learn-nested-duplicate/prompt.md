---
name: learn-nested-duplicate
tags: [learn, dedupe]
runs: 1
max_turns: 15
timeout_seconds: 600
allowed_tools: [Bash, Read, Edit, Write, Glob, Grep, Skill, AskUserQuestion]
---
Use the `mh:learn` skill (Skill tool, `skill: "mh:learn"`) to mine `./transcript.jsonl` (a Claude
Code session transcript already saved here — skip the locator script, this file is the
transcript) for durable, non-obvious, cross-turn learnings worth saving to the memory store at
`./memory/`. The store already has some content indexed — check it before proposing anything.
