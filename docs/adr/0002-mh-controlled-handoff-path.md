# mh writes its own handoff, at a path it controls

`mattpocock-skills:handoff` compacts a session into a Markdown document, but its own
instructions name no write tool and no output path or filename — only "save to the temporary
directory of the user's OS." The user has to find and retype that path in the next session,
which is the exact friction this decision removes.

mh ships its own gated skill, `mh:handoff` (`skills/workflow/handoff/`), that writes to
`$HOME/.claude/state/mh-handoffs/<slug>-<hash>/`, scoped to the git repo root. A 4th
`SessionStart` hook, `session:handoff-surface`, inlines any unread document automatically —
no path for the user to ever see or type, unless they want the manual fallback the skill
echoes once at write time.

## Rejected: detecting the upstream skill's writes

The original design was a `PostToolUse` hook that would recognise a handoff file as
`mattpocock-skills:handoff` wrote it — by content signature, temp-dir path, or both — snapshot
it, and replay it at the next `SessionStart`. Two rounds of adversarial review (Codex) refined
that design considerably (a content snapshot instead of a pointer, per-project scoping, at-least-
once dedup semantics, budget allocation order) before reading the upstream skill's own source
killed the premise entirely:

- The skill's `SKILL.md` is 17 lines with **no template file**. Its one mandated element is
  prose — `Include a "suggested skills" section` — with no heading level or capitalisation
  specified; the skill's own author documents renders it two different ways.
- It **never names a write tool**. It names "the Skill tool" explicitly one line later, so the
  omission is meaningful — a `Write`-only matcher could silently miss a `Bash` heredoc.
- It prescribes **no path and no filename** at all, and on macOS `$TMPDIR` and `/tmp` are
  entirely separate trees requiring four prefixes to canonicalise.

Detection could therefore only ever be a heuristic with silent-miss modes — no template to match
exactly, no tool guaranteed, no path convention to anchor on. Writing mh's own handoff at a path
mh controls removes the need to detect anything at all, and with it every piece of the snapshot,
digest, TOCTOU-guard, and dedup machinery the detection design had accumulated.

## Consequences

- **Cost accepted**: the user types `/mh:handoff`, not `/handoff` — upstream's
  `disable-model-invocation: true` means no skill can invoke it programmatically, so mh cannot
  delegate to it and must author its own handoff-content guidance instead. Plain `/handoff`
  still works exactly as it does today; it simply isn't auto-surfaced.
- **No new hook-event type.** The surfacer is mh's 4th `SessionStart` hook, an event mh already
  uses — unlike the rejected design, which would have been mh's first-ever `PostToolUse` hook.
- **Publish is atomic, in two steps.** The skill `Write`s into a `staging/` dir (a name `mktemp`
  reserves atomically, with the `X`'s literally trailing — BSD/macOS `mktemp` only randomises a
  *trailing* run of them, confirmed live after a first attempt with trailing characters after
  the `X`'s produced an unrandomised, colliding name), invisible to the hook's `handoff-*.md`
  glob on two independent counts (a leading dot, and no `.md` extension until published). The
  helper then does one `mv -n` into `pending/` — same filesystem, so the hook only ever sees a
  complete file, never a partial write. `mv -n` reports success even when it silently refuses to
  overwrite an existing destination, so every publish and consume step verifies the postcondition
  (source actually gone) rather than trusting the exit code alone.
- **Consumed is a directory, not a state file.** `mv -n` from `pending/` to `consumed/` is the
  entire mechanism — no lock file, no digest index, no JSON state. Consumed files are kept, not
  reaped, doubling as handoff history.
- **Scoped per project, keyed on git repo root** (falling back to physical cwd outside a repo),
  hashed the same way `scripts/_lib/codex-state-path.sh` scopes the paired Codex plugin's state —
  a bare directory-name slug can collide (`.../a-b` and `.../a/b` under a naive `/`→`-` replace).
- **Multiple pending documents: budget allocation and display order are separate axes.**
  Aggregate byte budget is allocated **oldest-first** (`ls -tr`, since `mktemp`'s random suffix
  isn't chronologically sortable by filename), so an old pending handoff can never be starved out
  by a steady stream of newer ones; the documents actually selected are then **displayed
  newest-first**, the more useful reading order. A document cut by the per-file cap
  (~300 lines/~15KB) is truncated *and shown* — truncation still counts as delivery, so it's
  consumed, with the notice pointing at the full archived copy. A document the *aggregate* cap
  never got to at all stays pending, since consumed strictly requires having been shown.
- **Delivery is best-effort, recoverable from archive — stated precisely, not oversold.** Nothing
  moves to `consumed/` until it has printed successfully: a genuine read failure, an empty file,
  or a real output-write failure all leave the document pending for retry. The read path is
  bounded to `MAX_BYTES+1` regardless of actual file size (a single pathological long line can't
  balloon memory), byte-exact under any locale (`LC_ALL=C`, not a character-count bash substring,
  which mis-truncated multibyte content at 3× the intended length in an earlier revision), and
  preserves trailing bytes through capture with a sentinel (plain `$()` silently strips trailing
  newlines, which broke the exact-length truncation check in another earlier revision — a
  50-line/15-byte-cap fixture with a trailing newline at the boundary reproduced it live). The one
  gap none of this closes: if the hook process is killed by Claude Code's own timeout *during* the
  brief, budget-capped move phase after printing has already completed, some files could be
  archived without the caller having received that output. No later signal exists in the hook
  architecture to build an acknowledgment on, and that would be disproportionate machinery for an
  advisory nudge — mitigated by keeping the whole invocation small enough to normally finish in a
  fraction of the 10-second hook timeout, not solved by pretending the mechanism guarantees more
  than it does.
- **Never a symlink.** Both the publish step and the surfacer explicitly reject anything that
  isn't a plain regular file (`-f` alone follows symlinks; `! -L` is required too) — a symlink
  planted in `pending/` pointing at an arbitrary real file must never get its content silently
  inlined into session context.
