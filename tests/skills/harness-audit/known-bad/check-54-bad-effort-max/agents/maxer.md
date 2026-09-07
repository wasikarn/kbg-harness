---
name: maxer
description: "Fixture agent for check 54. Use when proving an effort: max pin fires a WARN."
bucket: utility
tools: Read
model: sonnet
effort: max
---

Fixture body; `effort: max` is a valid Claude Code frontmatter value (sub-agents reference) but
the fleet assigns it no tier, since it means unbounded token spend on a shipped agent. Check 54
must WARN.
