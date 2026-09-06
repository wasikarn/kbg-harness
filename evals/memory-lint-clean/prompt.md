---
name: memory-lint-clean
tags: [memory-lint, clean]
runs: 1
max_turns: 12
timeout_seconds: 600
allowed_tools: [Bash, Read, Edit, Write, Glob, Grep, Skill]
---
Use the `mh:memory-lint` skill (Skill tool, `skill: "mh:memory-lint"`) to lint the memory store and fix every finding it reports. The index is `memory/MEMORY.md`; the memories are `memory/gate-hooks-break-machine-wide.md`, `memory/push-needs-remote-check.md`, and `memory/trash-empty-arg-deletes-cwd.md`.

The store is the `memory/` directory here: pass it as the script's positional path. Bash is needed to run the script.

End your final message with the script's last detector-mode summary line (the one starting `memories:`) verbatim, with nothing after it.
