"""fragments_capture_parse.py -- payload parser for
hooks/sensors/fragments-capture.sh.

Invoked BY PATH, never via `python3 -c` + PYTHONPATH -- same reasoning as
fragments_arm_parse.py's own header: cwd-first sys.path under -c let a
same-named hook_payload.py in the hook's own cwd (which fragments-capture.sh
runs in for every Write/Edit in every project, since its readdir gate is
TMPDIR-global, not project-scoped) shadow the real module.

Reads a PostToolUse (Write|Edit) hook payload from stdin. Prints 5 lines:
the validated session_id (or empty), tool_name, cwd, an H1 flag ("1"/"0",
Write only), then file_path as everything remaining.
"""
import json
import re
import sys

from hook_payload import validate_session_id

try:
    data = json.load(sys.stdin)
except Exception:
    data = None

sid = validate_session_id(data.get("session_id") if isinstance(data, dict) else None)

tool_name = data.get("tool_name") if isinstance(data, dict) else None
if not isinstance(tool_name, str):
    tool_name = ""

cwd = data.get("cwd") if isinstance(data, dict) else None
if not isinstance(cwd, str):
    cwd = ""

tool_input = data.get("tool_input") if isinstance(data, dict) else None
file_path = tool_input.get("file_path") if isinstance(tool_input, dict) else None
if not isinstance(file_path, str):
    file_path = ""

h1 = "0"
if tool_name == "Write" and isinstance(tool_input, dict):
    content = tool_input.get("content")
    if isinstance(content, str) and re.match(r"#[ \t]", content):
        h1 = "1"

print(sid)
print(tool_name)
print(cwd)
print(h1)
print(file_path)
