---
name: silent-failure-hunter-planted
tags: [silent-failure-hunter, planted]
runs: 1
max_turns: 12
timeout_seconds: 600
---
Use the `mh:silent-failure-hunter` agent (Agent tool, `subagent_type: "mh:silent-failure-hunter"`) to review the error handling in `app/billing.py` and `app/gateway.py`.
The files are in the current working directory: `app/gateway.py`, `app/billing.py`.

Return the agent's report verbatim as your final message. Add nothing before or after it.
