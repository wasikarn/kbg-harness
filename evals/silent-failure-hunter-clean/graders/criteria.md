---
type: llm
---
Score 1 only if the verdict is CLEAN with zero findings. Logging then re-raising in charge_order is
correct propagation, not a swallow; flagging it, or flagging gateway.charge's raise, is a false positive.
