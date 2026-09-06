---
name: reviewer-ok
description: "Fixture reviewer. Use when proving checks 03, 07, 09, 10, 21, 23, 24, 32, 41, 54 stay silent on a clean agent."
bucket: utility
tools: Read, Grep, Bash(git:*), mcp__demo__lookup
model: sonnet
effort: low
---

Read-only fixture agent; every tool token is real, no duplicates, no Agent, no Write/Edit.
