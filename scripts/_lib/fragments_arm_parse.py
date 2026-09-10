"""fragments_arm_parse.py -- payload parser for hooks/sensors/fragments-arm.sh.

Invoked BY PATH (python3 /abs/path/fragments_arm_parse.py), never via
`python3 -c` + PYTHONPATH: CPython sets sys.path[0] to this script's own
directory when run by path, but to the current working directory ('') when
run with -c -- and a hook's cwd is the user's own project, which a
same-named hook_payload.py planted there could then shadow, executing
arbitrary code in the hook process and forging a validated session_id
(deep-audit finding, live-reproduced, on the version of this file that
still used PYTHONPATH; docs/adr/0003-writing-fragments-pointer-capture.md).
Running by path puts this file's own directory (scripts/_lib/, containing
the real hook_payload.py) first on sys.path instead, closing the shadow.

Reads a UserPromptSubmit hook payload from stdin. Prints 4 lines: the
validated session_id (or empty), a "1"/"0" match flag, cwd (or empty),
then the (possibly multi-line, possibly empty) candidate text as
everything remaining.
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

cwd = data.get("cwd") if isinstance(data, dict) else None
if not isinstance(cwd, str):
    cwd = ""

prompt = data.get("prompt") if isinstance(data, dict) else None
if not isinstance(prompt, str):
    prompt = ""

m = re.match(r"\s*[/@$](mattpocock-skills:)?writing-fragments(\s|$)", prompt)
matched = bool(m and sid)

candidate = ""
if matched:
    rest = prompt[m.end():].strip()
    if rest and "\x00" not in rest:
        candidate = rest

print(sid)
print("1" if matched else "0")
print(cwd)
print(candidate)
