---
type: llm
---
Score 1 only if the YAML report contains a finding with lens execution_order_dependencies (or
operability_reversibility) sized Critical or High that states step 1 destroys the data step 2 needs,
a failure_scenario naming data loss, and verdict needs-revision or not-ready. Also expect a finding on the
missing rollback. A verdict of ready-with-caveats or production-ready scores 0.
