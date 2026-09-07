#!/usr/bin/env python3
"""PostToolUse(Bash) sensor: on a non-zero exit, injects a diagnose-before-
retry nudge back into the same turn. Never blocks (always exit 0) -- this is
advisory only, not a gate. GH #153.

Capped at 3 nudges per distinct failing command per session (METHODOLOGY
Rule 13's bounded-retry doctrine: "stop after 3 rounds, the fault is then in
the plan, not the unit") via a small session-scoped counter file -- the fleet's
first stateful hook, deliberately narrow in scope: a local rate-limit on one
advisory nudge, not a cross-agent orchestration layer.

Fires on every non-zero exit (no denylist of "worth nudging on" patterns) --
a deliberate first cut, narrowing to specific failure shapes is left for a
follow-up if the noise turns out to matter in practice.
"""
import hashlib
import json
import os
import sys

CAP = 3

NUDGE = (
    "<mh-failure-diagnose-nudge>\n"
    "A Bash command just exited non-zero. Before retrying the same command verbatim:\n"
    "1. Diagnose -- read the actual error; identify the root cause (env, missing dep, wrong flag/path).\n"
    "2. Check MEMORY.md and its sub-indexes for a matching prior gotcha before re-solving a solved problem.\n"
    "3. Patch the actual cause, then re-run and require exit 0 before moving on.\n"
    "4. If this reveals a durable, non-obvious lesson, use mh:learn or write a memory file directly -- never a separate log/store.\n"
    "</mh-failure-diagnose-nudge>"
)


def extract_exit_code(data):
    # tool_response.exit_code is the documented PostToolUse shape for Bash
    # (Claude Code hooks reference; the update-config skill's own schema
    # labels tool_response as "PostToolUse only"). This hook is registered
    # only under hooks.json's PostToolUse:Bash matcher, so no other payload
    # family (e.g. Codex's dispatcher-normalized shape) ever reaches it --
    # add a path here only once a real payload is observed needing one.
    tr = data.get("tool_response")
    if not isinstance(tr, dict):
        return None
    ec = tr.get("exit_code")
    if isinstance(ec, (int, str)):
        try:
            return int(ec)
        except (ValueError, TypeError):
            pass
    return None


def extract_command(data):
    ti = data.get("tool_input")
    if isinstance(ti, dict):
        cmd = ti.get("command")
        if isinstance(cmd, str):
            return cmd
    return ""


def signature(command):
    return hashlib.sha256(command.strip().encode("utf-8", "replace")).hexdigest()[:16]


def load_counts(state_path):
    try:
        with open(state_path) as f:
            d = json.load(f)
        return d if isinstance(d, dict) else {}
    except (OSError, ValueError):
        return {}


def save_counts(state_path, counts):
    try:
        os.makedirs(os.path.dirname(state_path), exist_ok=True)
        with open(state_path, "w") as f:
            json.dump(counts, f)
    except OSError:
        pass  # fail-open: losing the counter just means the cap resets, never blocks


def default_state_path(data):
    # session_id is on every documented hook payload (PreToolUse and
    # PostToolUse examples both carry it) -- prefer it over the env var so
    # the cap stays session-scoped even if CLAUDE_CODE_SESSION_ID is ever
    # unset. ponytail: "unknown" as a last resort would make the cap
    # global-and-permanent instead of per-session, but that only happens if
    # neither source is present, which the hook protocol doesn't allow.
    session = data.get("session_id") or os.environ.get("CLAUDE_CODE_SESSION_ID") or "unknown"
    tmpdir = os.environ.get("TMPDIR", "/tmp").rstrip("/")
    return f"{tmpdir}/mh-sensors/failure-nudge-{session}.json"


def main(argv):
    try:
        data = json.load(sys.stdin)
    except (ValueError, TypeError):
        return 0
    if not isinstance(data, dict):
        return 0

    state_path = argv[1] if len(argv) > 1 else default_state_path(data)

    exit_code = extract_exit_code(data)
    if not exit_code:  # None or 0 -- no failure, nothing to nudge
        return 0

    command = extract_command(data)
    sig = signature(command)
    counts = load_counts(state_path)
    seen = counts.get(sig, 0)
    if seen >= CAP:
        return 0  # capped -- stay silent for this exact command, don't spam

    counts[sig] = seen + 1
    save_counts(state_path, counts)

    print(json.dumps({
        "hookSpecificOutput": {
            "hookEventName": "PostToolUse",
            "additionalContext": NUDGE,
        }
    }))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
