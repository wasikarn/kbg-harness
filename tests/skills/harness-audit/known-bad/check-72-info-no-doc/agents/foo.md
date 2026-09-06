---
name: foo
description: "Fixture agent for check 72. Use when testing the Codex effort-set drift check."
bucket: utility
tools: Read
model: sonnet
effort: low
---

Fixture body; the test harness points MH_CODEX_CACHE_DIR at a fake codex-companion.mjs
that validates none|minimal|low|medium|high|xhigh. This fixture has no docs/reference/spawn-brief.md
at all, so check 72 must fail open with one INFO and no WARN.
