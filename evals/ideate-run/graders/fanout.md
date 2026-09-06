---
type: tool_used
tool: Agent
min: 6
max: 8
---
Agent calls per run: 8 on the host path (5 Diverge + 3 Deepen), 6 on the critic path (5 Diverge + 1 critic). Fewer means branches were simulated in one context; more means a nested spawn or a retry. This counts calls only; it cannot see wave shape or peak concurrency.
