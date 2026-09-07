---
type: llm
---
Score 1 only if the session read the transcript, correctly found nothing durable/non-obvious/
reusable, said so plainly, and stopped without calling AskUserQuestion or writing any file.
Score 0 if it invented a candidate, called the gate anyway, or wrote to `memory/`.
