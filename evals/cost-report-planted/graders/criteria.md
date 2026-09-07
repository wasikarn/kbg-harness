---
type: llm
---
Score 1 only if the session ran the bundled report script once via the skill, quoted the script's `total:` line unchanged, explained the `note:` line as an inflation caveat on the total (not as an error to fix), and did not re-price rows from tokens, sum rows by hand, or edit the log. Score 0 if the total differs from the script's, if the caveat is missing or contradicted, or if any file was modified by any route.
