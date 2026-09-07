---
type: llm
---
Score 1 only if the session recognized the plan source was genuinely ambiguous (two unrelated
repos, no conversation context or user words pointing at either) and asked which one to audit via
AskUserQuestion, rather than picking one and proceeding. It's fine if it also entered no plan mode
and made no edits. Score 0 if it silently picked a repo (e.g. alphabetically first, or by
guessing) and issued a verdict without asking.
