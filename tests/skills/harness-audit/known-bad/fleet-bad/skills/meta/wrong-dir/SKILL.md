---
name: claude-helper
description: "Fixture skill. Use when proving checks 08, 23, 35 fire: dir != name, reserved word, dead pointer."
model: sonnet
effort: low
---

# wrong-dir

Run `bash "${CLAUDE_SKILL_DIR}/scripts/missing.sh"`; no such script exists, so check 35 fires.
