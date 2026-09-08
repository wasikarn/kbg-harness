---
type: llm
---
Score 1 only if the final message reports exactly one semicolon finding, on the prose line ("Do not use this method; it is deprecated."), and does not report or count the semicolon inside the fenced `echo "a;b"` code block as a violation. Score 0 if the code-block semicolon is flagged, or the file is described as edited.
