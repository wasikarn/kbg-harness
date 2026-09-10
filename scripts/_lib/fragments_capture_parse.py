"""fragments_capture_parse.py -- payload parser for
hooks/sensors/fragments-capture.sh.

Invoked BY PATH, never via `python3 -c` + PYTHONPATH -- same reasoning as
fragments_arm_parse.py's own header: cwd-first sys.path under -c let a
same-named hook_payload.py in the hook's own cwd (which fragments-capture.sh
runs in for every Write/Edit in every project, since its readdir gate is
TMPDIR-global, not project-scoped) shadow the real module.

Reads a PostToolUse (Write|Edit) hook payload from stdin. Prints 5 NUL-
separated fields (deep-audit finding, live-reproduced: newline-separated
fields let an embedded newline in `cwd` desync every field after it --
`sed -n 'Np'` reads by line number, so a 2-line cwd shifted HAS_H1 into
FILE_PATH and truncated the real file_path): the validated session_id (or
empty), tool_name, cwd, an H1 flag ("1"/"0", Write only), then file_path.
Every field has embedded NUL bytes stripped before the join (deep-audit
finding, live-reproduced on this NUL-delimited framing itself: an
unstripped NUL inside e.g. `cwd` forges a fake field boundary, letting a
crafted payload spoof HAS_H1/FILE_PATH to values it never actually
computed -- a real field-injection primitive, not just the pre-existing,
irreducible "bash can't represent a NUL" limitation this framing accepted).
No real cwd/file_path/tool_name legitimately contains a NUL, so stripping
it is a no-op for any real payload.
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

fields = [f.replace("\0", "") for f in (sid, tool_name, cwd, h1, file_path)]
sys.stdout.write("\0".join(fields))
