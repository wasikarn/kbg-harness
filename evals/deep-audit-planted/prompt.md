---
name: deep-audit-planted
tags: [deep-audit, planted]
runs: 1
max_turns: 40
timeout_seconds: 900
allowed_tools: [Bash, Read, Edit, Write, Glob, Grep, Skill, Agent]
---
Audit and fix. Use the `mh:deep-audit` skill (Skill tool, `skill: "mh:deep-audit"`) on this repo. The session under audit made every commit in `git log` and wrote `NOTES.md`; its claims are the commit messages and that file. The code is `calc.py`, its suite `test_calc.py`; tests run with `python3 -m unittest test_calc.py`. Session start is the first commit, so scope is the whole history.

Start your final message with the Final Verdict line the skill defines, then the six report sections.
