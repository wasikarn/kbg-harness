#!/usr/bin/env python3
import sys, json

try:
    from _journal import journal
except Exception:
    def journal(*a, **k):
        pass

GATE_ID = "gate:skill:codex-setup-guard"

def emit_ask(reason, tool_name, session_id):
    print(json.dumps({"hookSpecificOutput": {"hookEventName": "PreToolUse",
                                             "permissionDecision": "ask",
                                             "permissionDecisionReason": reason}}))
    journal(GATE_ID, tool_name, "ask", session_id)

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
        "(see CONTEXT.md, ADR-0001). Confirm this is intentional.",
        d.get("tool_name"), d.get("session_id"),
    )
except Exception:
    sys.exit(0)
