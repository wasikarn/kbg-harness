---
name: memory-lint
description: "Lints the auto-memory store: dangling [[links]], orphans, index drift; --auto-archive trims. Use after editing memories or near the cap. Not for semantic or harness review."
model: inherit
effort: medium
---

# memory-lint

Deterministic bookkeeping check for the auto-memory store (the `Lint` step of the llm-wiki
loop). Claude Code itself only warns when `MEMORY.md` nears its 200-line / 25 KB load cap
(re-verified 2026-09-07, `code.claude.com/docs/en/memory`); nothing vendor-side resolves
`[[wikilinks]]`, finds orphans, or notices index drift. This script is the only thing that does.
Semantic review of memory content stays a human or separately invoked call.

## The loop

1. **Run the detector.** Exit code equals the finding count, so `0` is the proof of a clean store.
   ```bash
   python3 "${CLAUDE_SKILL_DIR}/scripts/memory-lint.py"              # store derived from the git root: ~/.claude/projects/<root with / as ->/memory
   python3 "${CLAUDE_SKILL_DIR}/scripts/memory-lint.py" /path/to/memory
   python3 "${CLAUDE_SKILL_DIR}/scripts/memory-lint.py" --json         # findings array instead of the summary line
   ```
   Done when: the summary line (`memories: … | findings: N`), or the `--json` findings array, and the exit code are read, not assumed.
2. **Fix each finding at its cause.** Dangling link: correct the target to the real filename stem
   (the `did you mean` hint is a `difflib` match, check it before taking it), never delete the link
   to silence it. Stale pointer: remove the `MEMORY.md` line; never create a file to satisfy it.
   Unindexed: add a one-line pointer, or link it from an indexed memory. Orphan: link it from the
   memory it belongs with. Near or over budget: go to step 3.
   Done when: every finding has a named edit and no memory file was deleted.
3. **Trim only through action mode.** `--auto-archive --dry-run` first, read the plan, then
   `--auto-archive --yes`. Rubric, classes A–D, and thresholds: `references/action-mode.md`.
   Done when: the dry-run plan was read before any apply.
4. **Re-run the detector.** Done when: exit code `0`, or every remaining finding is accepted with a
   written reason.

## Checks

| Check | Fires when |
|---|---|
| Dangling link | `[[target]]` (alias form `[[target\|alias]]` stripped) or same-store `](file.md)` resolves to no memory by filename stem or `name:` slug; code spans are masked first |
| Orphan | an indexed memory has no links in or out |
| Index drift | `MEMORY.md` points at a missing file, or a file has no pointer and is not `[[link]]`-reachable from an indexed one |
| Load budget | `MEMORY.md` at 80% or more of 200 lines / 25 KB; once over the cap, trailing entries never load |

## Authoring rules the checks assume

- **Link by filename stem**, never by `name:` slug. Both resolve, but `name:` values drift from
  filenames across the store; the stem is the identifier that always resolves.
- `[[ ]]` is memory-to-memory only. A skill, doctrine file, or ADR is named in backticked prose;
  a wikilink to it is always dangling.
- One fact per file with `name:` and `description:` frontmatter, body with `**Why:**` and
  `**How to apply:**`; dedupe against the store before writing; archive under `_archive/`, never
  delete.

The SessionStart hook `hooks/session/memory-health-nudge.sh` runs the detector each session unless
nothing in the store changed since the last clean run, and is silent when clean.

## Failure modes

- **Apply without the plan.** `--auto-archive --yes` straight away moves entries you meant to keep.
- **Silencing instead of fixing.** Deleting a dangling link, or writing a stub file for a stale
  pointer, clears the finding and loses the fact.
- **Trusting the hint.** `did you mean` is a string-similarity guess; a wrong accept links two
  unrelated memories.

## Related

- `harness-audit`: the same fires/silent shape for agents, skills, and hooks.
