---
name: test-gap-analyzer-clean
tags: [test-gap-analyzer, clean]
runs: 1
max_turns: 12
timeout_seconds: 600
---
Use the `mh:test-gap-analyzer` agent (Agent tool, `subagent_type: "mh:test-gap-analyzer"`) to review test coverage for the change in `src/discount.py` against `tests/test_discount.py`.
The files are in the current working directory: `src/discount.py`, `tests/test_discount.py`.

Return the agent's report verbatim as your final message. Add nothing before or after it.
