---
name: post-mortem-missing-input
tags: [post-mortem, planted]
runs: 1
max_turns: 8
timeout_seconds: 300
allowed_tools: [Bash, Read, Glob, Grep]
---
/mh:post-mortem gh-77

Trigger: `python3 -m pytest tests/test_retry.py` fails on `test_backoff_first_retry_waits_base` at the parent of HEAD. Mechanism: `backoff()` in `src/retry.py` used `2 ** attempt` on a 1-based attempt, doubling every wait. Patch: HEAD on the default branch (`GITLOG.txt` lists the SHAs). Nobody has run the tests since the fix and there is no CI. Destination: print-only.
