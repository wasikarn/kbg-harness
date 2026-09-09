# matt-harness

The Claude Code harness (`mh@wasikarn`) and its doctrine: what gates deny computationally,
what stays advice, and how it composes third-party plugins instead of duplicating them.

## Language

**Codex** (as mh's docs use the word):
The installed Claude Code plugin `codex@openai-codex` (source repo `openai/codex-plugin-cc`),
which exposes the `/codex:*` commands and wraps the Codex CLI (`@openai/codex`). mh treats it
as a second, independent coding agent — a different model family with different blind spots —
never as a subordinate tool mh drives.
_Avoid_: "Codex Companion" (the plugin's own internal/product name, not mh's term for it);
"the Codex CLI" as a stand-in for the whole plugin (the CLI is only the binary the plugin
shells out to; the plugin also owns job state, the review gate, and the `/codex:*` surface).

**Review gate**:
Codex's own optional Stop-time hook (config key `stopReviewGate`, off by default, toggled by
`/codex:setup --enable-review-gate`). When on, it runs a Codex review and can block a Claude
Code session from ending. The Stop hook itself is registered unconditionally whenever the
plugin is enabled — the toggle controls what it *does*, not whether it's *wired in*; off, it
reads local state and returns without spawning anything.
_Avoid_: confusing this with mh's own gates (`gate:*` in `hooks/hooks.json`). Those deny or ask
on a tool call before it runs, by a computational rule. The review gate blocks a Stop after
the fact, by an LLM's judgment call — exactly the shape mh's operating model keeps out of the
deny/ask set. mh's constraint is that this stays off.

**Pairing** (Codex pairing):
Installing and enabling Codex as its own independent plugin alongside mh, routed to by name
for a second opinion from a different model family. Not a wrapper, mirror, or orchestration
layer — mh creates no surface whose only job is to call Codex.
_Avoid_: "integration," which implies code-level coupling mh deliberately avoids; "orchestration,"
which implies mh sequences or supervises Codex's work.

**Handoff**:
A Markdown session-summary document, written by mh's own `/mh:handoff` skill (`skills/workflow/
handoff/`) to a path mh controls, distinct from `mattpocock-skills:handoff` — the upstream skill
mh deliberately does not delegate to or detect (`docs/adr/0002-mh-controlled-handoff-path.md`),
since its own instructions name no write tool and no output path. The term covers both directions:
`session:handoff-surface` reads and inlines an unread one at `SessionStart`; `session:handoff-nudge`
nudges the model, once per session right after a compact, to suggest writing one.
_Avoid_: "the handoff skill" without a prefix, ambiguous between mh's and mattpocock's; "handoff
file" for anything still in `staging/` — it isn't a handoff until published to `pending/`.

**Consumed** (handoff state):
The state a handoff enters once mh's `session:handoff-surface` hook has moved it from
`pending/` to `consumed/` after printing it successfully. No age-based expiry — a document in
`consumed/` is never auto-replayed, regardless of how long it sat unread beforehand.
_Avoid_: "stale" or "expired," which imply a time-based rule mh deliberately does not use.
