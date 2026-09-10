---
name: foo
description: "Fixture agent for check 73. Use when testing the hook id-registry drift check."
bucket: utility
tools: Read
model: sonnet
effort: low
---

Fixture body; the root holds only what check 73 reads, so it stays silent unless the
fixture's own hooks.json / hook-registry.json pair is the thing under test.
