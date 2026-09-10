"""hook_payload.py -- shared session_id validation for hook payloads.

Imported (PYTHONPATH) by hooks/sensors/fragments-arm.sh and
hooks/sensors/fragments-capture.sh; run as a script by
hooks/session/handoff-nudge.sh, which needs only the session id and nothing
else from the payload. One definition so the character-class regex and the
"." / ".." rejection can't drift apart between the three call sites
(docs/adr/0003-writing-fragments-pointer-capture.md).

validate_session_id must run on the untruncated JSON value, before it ever
crosses into bash: bash command substitution unconditionally strips
trailing newlines and silently drops embedded NUL bytes, so a value like
"foo\\n" or "foo\\x00bar" would otherwise pass a bash-side regex as a
mangled "foo"/"foobar".
"""
import re

_SESSION_ID_RE = re.compile(r"[A-Za-z0-9._-]+")


def validate_session_id(value):
    """Return value if it is a valid session id, else "".

    A wrong-typed value (None, a number, a list/dict) is deliberately not
    stringified -- Python's own str() would turn None into "None", which
    would then pass the character-class check as if it were a real id.
    """
    if not isinstance(value, str):
        return ""
    if value in (".", ".."):
        return ""
    if not _SESSION_ID_RE.fullmatch(value):
        return ""
    return value


if __name__ == "__main__":
    import json
    import sys

    try:
        data = json.load(sys.stdin)
    except Exception:
        data = None
    sid = data.get("session_id") if isinstance(data, dict) else None
    print(validate_session_id(sid))
