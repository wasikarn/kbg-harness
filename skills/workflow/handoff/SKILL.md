---
name: handoff
description: "Writes a session handoff document to a path mh manages, auto-surfacing it at the next session start. Use when the user types /mh:handoff."
argument-hint: "[what will the next session be used for?]"
disable-model-invocation: true
disable-model-invocation-reason: writes a canonical doc the user decides to end a session with — never a step the model chains into on its own
model: inherit
effort: high
---

# Handoff

Write a session-summary document to a path mh controls, so the next session picks it up
automatically — no path to find or retype. This intentionally does not delegate to
`mattpocock-skills:handoff`: that skill's own instructions name no output path or write tool,
which is exactly the friction this skill exists to remove (`docs/adr/0002-mh-controlled-handoff-path.md`).

## 1. Gather the content

From `$ARGUMENTS` (what the next session is for) if given, otherwise from the conversation itself,
determine:

- **Task / focus**: what this session was working on.
- **Done**: what's actually finished, concretely — not "mostly done."
- **Pending / blocked**: what's left, and why it stalled if it stalled.
- **Validation state**: are tests/gates passing right now? Named, not implied.
- **File references**: the paths a fresh agent needs to open first.
- **Suggested skills**: which skill(s) the next agent should reach for to continue.

**Redact before writing.** Strip any live credential, API key, token, or personal data that
appeared in the conversation — a handoff document persists on disk past this session.

Done when: all six items above are either filled in or explicitly marked "None" / "Unknown" —
never invented to make the story cleaner.

## 2. Allocate a staging path

```bash
bash "${CLAUDE_SKILL_DIR}/scripts/handoff-path.sh"
```

Prints a staging file path under this project's own handoff directory. Nothing is visible to any
other session yet — the path is a private draft location until step 4 publishes it.

## 3. Write the document

Use the `Write` tool to write the content from step 1 to the staging path from step 2, as Markdown.

## 4. Publish

```bash
bash "${CLAUDE_SKILL_DIR}/scripts/handoff-path.sh" --publish <staging-path-from-step-2>
```

Atomically moves the document into this project's pending directory and prints the published
path. From here it surfaces automatically, inlined in full, the next time a session starts in
this repo — a fresh `claude`, a `--resume`, or a `/clear` — but deliberately **not** on `/compact`
within this same conversation (that would just re-inject it into the session that just wrote it).

Done when: the command exits 0 and prints a path. A non-zero exit means the write failed
somewhere — report the helper's stderr, don't silently retry with a different path.

## 5. Confirm

Echo the published path to the user once, as a manual fallback if they'd rather open it
themselves than wait for the next session to surface it automatically. Then the session is ready
to end.

## Failure modes

- **Writing "mostly done" instead of naming what's actually done.** The next agent inherits a
  false sense of progress and re-does work, or skips work that was never finished.
- **Skipping redaction because "it's just for me."** The document sits on disk under this
  project's own state directory until explicitly consumed; treat it like any other artifact that
  outlives the conversation.
- **Publishing without writing first.** Step 4 only moves whatever is at the staging path — an
  empty or missing staging file publishes an empty or missing document, silently.
