#!/usr/bin/env python3
import json, sys

try:
    d = json.load(sys.stdin)
except Exception as e:
    # Fail-safe = ALLOW: a parse error must not stall every subagent Agent call.
    print(f"[mh:gate] subagent-spawn-guard: unparseable stdin, allowing ({e})", file=sys.stderr)
    sys.exit(0)

if not isinstance(d, dict):
    print("[mh:gate] subagent-spawn-guard: non-object payload, allowing", file=sys.stderr)
    sys.exit(0)

if d.get("tool_name") != "Agent":
    sys.exit(0)

# agent_id is present ONLY inside a subagent call (task-complete-separation.py's
# header: agent_type is ALSO set for a top-level `claude --agent <name>` main
# session, which legitimately dispatches; agent_id is the correct discriminant).
# Presence check, not truthiness (GH #154): the key being present at all is
# the signal, so an empty-string or null agent_id must still deny, not allow.
if "agent_id" not in d:
    sys.exit(0)

agent_type = d.get("agent_type") or "unknown"

# Deliberately ignores tool_input.subagent_type: the check is "any subagent
# calling Agent at all", not "a subagent spawning its own type" -- the
# 2026-08-31 fork-recursive-spawn incident evaded a same-type check by
# switching subagent_type, so this gate never looks at it.
print(f"[mh:gate] BLOCKED: subagent ({agent_type}) may not call the Agent tool to spawn its "
      f"own reviewer/validator/subagent -- dispatch is the main session's job (maker≠checker, "
      f"docs/METHODOLOGY.md Rule 13). Return findings to the main session and let it "
      f"dispatch the next agent.", file=sys.stderr)
sys.exit(2)
