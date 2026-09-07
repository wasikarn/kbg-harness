#!/usr/bin/env python3
import sys, json

def emit_ask(reason):
    print(json.dumps({"hookSpecificOutput": {"hookEventName": "PreToolUse",
                                             "permissionDecision": "ask",
                                             "permissionDecisionReason": reason}}))

try:
    d = json.load(sys.stdin)
    if d.get("tool_name") != "Skill":
        sys.exit(0)
    ti = d.get("tool_input")
    if not isinstance(ti, dict):
        sys.exit(0)
    if ti.get("skill") != "codex:setup":
        sys.exit(0)
    args = ti.get("args")
    if not isinstance(args, str) or "--enable-review-gate" not in args:
        sys.exit(0)

    emit_ask(
        "codex-setup-guard: this call to codex:setup would enable the paired Codex "
        "plugin review gate, an LLM-judgment Stop-time check mh keeps off by design "
        "(see CONTEXT.md, ADR-0001). Confirm this is intentional."
    )
except Exception:
    sys.exit(0)
