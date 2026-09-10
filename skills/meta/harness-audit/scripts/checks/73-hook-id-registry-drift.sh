#!/usr/bin/env bash
# 73. Hook id/description registry drift (hooks.json vs hook-registry.json)
# hooks.json's own schema (code.claude.com/docs/en/hooks) only recognizes "matcher"/"hooks"
# at the hook-group level -- Claude Code warns and drops "id"/"description" if left inline
# (2026-09-10 finding, live-reproduced). The id vocabulary 19+ docs cite by name
# (gate:bash:irrecoverable, session:doctrine-bootstrap, ...) now lives in
# hooks/hook-registry.json instead, keyed by event + array position, with a "command"
# fingerprint per entry so a reorder or same-count replacement can't silently mismatch.
# WARN throughout -- convention/doc drift, not the tamper-sensitive class checks 11/33 own.
_hj="$CLAUDE_DIR/hooks/hooks.json"
_reg="$CLAUDE_DIR/hooks/hook-registry.json"
if [ -f "$_hj" ]; then
  if [ ! -f "$_reg" ]; then
    warn "hooks/hook-registry.json missing -- hooks.json's hook-group entries have no id/description registry"
  else
    while IFS= read -r finding; do
      [ -n "$finding" ] && warn "$finding"
    done < <(python3 - "$_hj" "$_reg" <<'PYEOF'
import json, sys

hj_path, reg_path = sys.argv[1], sys.argv[2]

try:
    hj_doc = json.load(open(hj_path))
except Exception as e:
    print(f"hooks.json unparseable ({e}) -- skip registry cross-check"); sys.exit(0)
try:
    reg_doc = json.load(open(reg_path))
except Exception as e:
    print(f"hook-registry.json unparseable ({e})"); sys.exit(0)

hj = hj_doc.get("hooks") if isinstance(hj_doc, dict) else None
reg = reg_doc.get("hooks") if isinstance(reg_doc, dict) else None
if not isinstance(hj, dict):
    print("hooks.json 'hooks' is not an object -- skip registry cross-check"); sys.exit(0)
if not isinstance(reg, dict):
    print("hook-registry.json 'hooks' is not an object"); sys.exit(0)

events = sorted(set(hj) | set(reg))
seen_ids = {}
for ev in events:
    hj_arr = hj.get(ev)
    reg_arr = reg.get(ev)
    if not isinstance(hj_arr, list):
        print(f"hooks.json event {ev!r} value is not an array"); continue
    if ev not in reg:
        print(f"hooks.json event {ev!r} ({len(hj_arr)} entries) has no hook-registry.json entry"); continue
    if not isinstance(reg_arr, list):
        print(f"hook-registry.json event {ev!r} value is not an array"); continue
    if ev not in hj:
        print(f"hook-registry.json has event {ev!r} not present in hooks.json"); continue
    if len(hj_arr) != len(reg_arr):
        print(f"hooks.json event {ev!r} has {len(hj_arr)} hook-group entries, hook-registry.json has {len(reg_arr)} -- positions can't line up")
        continue

    cmds_this_event = {}
    for i, (hj_item, reg_item) in enumerate(zip(hj_arr, reg_arr)):
        if not isinstance(hj_item, dict):
            print(f"hooks.json {ev}[{i}] is not an object"); continue
        if not isinstance(reg_item, dict):
            print(f"hook-registry.json {ev}[{i}] is not an object"); continue

        for k in hj_item:
            if k not in ("matcher", "hooks"):
                print(f"hooks.json {ev}[{i}] carries key {k!r} -- not part of the hooks.json schema (matcher/hooks only); id/description belong in hook-registry.json")

        handlers = hj_item.get("hooks")
        if not isinstance(handlers, list) or not handlers:
            print(f"hooks.json {ev}[{i}] has no handlers -- can't fingerprint"); continue
        if len(handlers) > 1:
            print(f"hooks.json {ev}[{i}] has {len(handlers)} handlers -- hook-registry.json's command fingerprint only covers the first one; extend the registry schema before relying on it here")
        first = handlers[0] if isinstance(handlers[0], dict) else {}
        hj_cmd = first.get("command")

        _id = reg_item.get("id")
        _desc = reg_item.get("description")
        _cmd = reg_item.get("command")

        if not isinstance(_id, str) or not _id.strip():
            print(f"hook-registry.json {ev}[{i}] missing or empty 'id'")
        else:
            if _id in seen_ids:
                print(f"hook-registry.json id {_id!r} duplicated ({seen_ids[_id]} and {ev}[{i}])")
            else:
                seen_ids[_id] = f"{ev}[{i}]"
        if not isinstance(_desc, str) or not _desc.strip():
            print(f"hook-registry.json {ev}[{i}] (id={_id!r}) missing or empty 'description'")
        if not isinstance(_cmd, str) or not _cmd.strip():
            print(f"hook-registry.json {ev}[{i}] (id={_id!r}) missing or empty 'command' fingerprint")
        elif hj_cmd is not None and _cmd != hj_cmd:
            print(f"hook-registry.json {ev}[{i}] (id={_id!r}) command fingerprint doesn't match hooks.json's actual command at that position -- registry is stale")
        elif isinstance(_cmd, str) and _cmd.strip():
            if _cmd in cmds_this_event:
                print(f"hooks.json event {ev!r} has the same command at positions {cmds_this_event[_cmd]} and {i} -- a swap between them wouldn't be caught by the command fingerprint alone")
            else:
                cmds_this_event[_cmd] = i
PYEOF
)
  fi
fi
unset _hj _reg
