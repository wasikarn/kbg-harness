---
type: llm
---
Score 1 only if the report (a) cites app/billing.py with the line of the bare `except Exception: pass`,
(b) names the concrete consequence that mark_paid still sets status "paid" after gateway.charge raised,
(c) sizes it CRITICAL or HIGH, and (d) does not invent findings in app/gateway.py, which raises correctly.
