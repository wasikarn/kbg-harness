# `mattpocock-skills:handoff` mechanics, and how mh could remove the path-typing step (2026-09-09)

Question: how does the installed `mattpocock-skills:handoff` skill work today, does anything already
consume its output, and what should matt-harness (mh) build so the user never has to remember or
type the handoff file's path.

Installed plugin checked: `mattpocock-skills` v1.2.3, cache path
`~/.claude/plugins/cache/mattpocock/mattpocock-skills/1.2.3/` [1].

## Summary

- `handoff` is a `disable-model-invocation: true` skill: the user types `/mattpocock-skills:handoff`
  (or the shorter alias if configured); the model never reaches for it on its own [1][2].
- It writes exactly one Markdown file to the OS temp directory, never the workspace. The path and
  filename are not fixed by the skill — the invoking agent picks both at write time, so there is no
  glob or naming convention to rely on [1][3].
- The only structural anchor in the content is a mandated **"suggested skills"** section; everything
  else (redaction, references-not-copies for specs/plans/ADRs/issues/commits/diffs) is instruction
  text, not a template file — this skill ships no template/script beyond a UI-metadata YAML [1][2].
- The installed `docs/productivity/handoff.md` is a byte-for-byte match of `aihero.dev/skills-handoff.md`
  (fetched live 2026-09-09) — no drift between the shipped doc and the author's site [3][4].
- **No sibling skill in this plugin reads a handoff file back in.** There is no "resume" or
  "load-context" skill in the manifest. A different, unshipped skill (`in-progress/claude-handoff`)
  exists in the plugin's source tree but is **not listed in `plugin.json`'s `skills` array**, so it is
  not installed/available to the user right now [1][5][6].
- Two mechanical constraints rule out the most obvious wrapper shapes for mh, detailed below: a
  `disable-model-invocation` skill produces no `Skill` tool call for a hook to key on, and any new mh
  slash-command still requires typing something.

## How the skill works today

**Trigger.** Frontmatter: `disable-model-invocation: true`, `argument-hint: "What will the next
session be used for?"` [1]. This is the same shape mh's own conventions doc uses to describe
"model won't call it itself" skills [7]. The skill body confirms: "You invoke this by typing
`/handoff`" [3][4] (the doc uses the un-namespaced short form; the actual installed invocation
from this plugin is `/mattpocock-skills:handoff`, since mh's own convention for citing such a
slash string is the fully namespaced one [7]). Passed arguments become "what the next session is
for" and steer the doc's content [1].

**What it writes.** One Markdown file, saved to "the temporary directory of the user's OS — not
the current workspace" [1]. The skill body gives no path template, no filename pattern, and no
script that computes one — `agents/openai.yaml` is UI metadata only (`display_name`,
`short_description`, `allow_implicit_invocation: false`), not a path helper [2]. The author's own
doc confirms this is deliberate and is the single most-reported friction point: "the paths are
long, they differ per OS, and on Windows agents sometimes take several attempts to find the right
one. Ask for the path back and keep it before you move on." [3][4] So even the upstream author's
own answer to "how do I find my file" is "ask the agent, by hand, right after it runs" — there is
no built-in path echo instruction in SKILL.md itself; the doc's FAQ is describing user behavior,
not a feature. Nothing in SKILL.md instructs the model to print the path in a fixed format [1].

**Content shape.** Per SKILL.md: a summary of the live thread (what's in flight, why, what's
next), a "suggested skills" section naming which skills the next agent should call, and redaction
of secrets before writing [1]. Per the doc, specs/plans/ADRs/issues/commits/diffs are referenced
by path/URL and never copied in [3][4].

**Durability.** Explicitly not durable: temp directories get swept between sessions on some
harnesses (Codex named as the reported case), and `/private/tmp`-style locations clear on reboot.
The doc's advice if the next session won't start within the hour, or starts under a different
harness, is to copy the file out of temp manually [3][4].

**Doc vs. installed skill: no drift.** The fetched `aihero.dev/skills-handoff.md` and the cached
`docs/productivity/handoff.md` are identical in every section checked (What it does, When to
reach for it, Branching, What travels, Common questions, It's working if, Where it fits) [3][4].
The doc is elaboration and rationale around the terse SKILL.md instructions, not a separate or
newer spec — SKILL.md is still the operative instruction set the agent executes from [1].

## Does anything already consume handoff output?

No. The manifest's `skills` array lists 25 skills; nothing named resume, load-context, continue,
or similar exists in `productivity/` or `engineering/` [6]. The plugin's *source tree* does
contain `skills/in-progress/claude-handoff/SKILL.md` — a same-machine variant that skips the file
entirely and instead launches `claude --bg --name "<name>" "<handoff summary>"` to fork a
background agent seeded with the summary as its prompt [5]. But `in-progress/claude-handoff` is
absent from `plugin.json`'s `skills` array, unlike every other installed skill [6], so it is not
currently reachable by the user through this plugin install — it is unshipped work-in-progress,
not a live sibling. (Not independently confirmed against a newer/different version of the plugin;
flagged as an open question below.)

## Two constraints that shape mh's options

1. **A hook cannot key on `Skill(mattpocock-skills:handoff)`.** `disable-model-invocation: true`
   means the user types the slash command directly; it is not dispatched as a model-invoked `Skill`
   tool call the way, e.g., `codex:setup` is (mh's own `gate:skill:codex-setup-guard` hook proves the
   pattern works for a model-invocable skill by reading `tool_input.skill` / `tool_input.args` on a
   `PreToolUse` `Skill` matcher [8]) — but a prior-session finding already on record notes runner
   expansion of a typed `/cmd` into a `Skill` tool call is unverified for `disable-model-invocation`
   skills, and that such skills are known to bypass `tool_used: Skill` detection entirely in eval
   traces. The safe assumption is: don't build a hook that matches on the `Skill` tool for this case.
   What *is* observable is the underlying **`Write` tool call** the skill's own instructions dispatch
   — that's a normal tool call regardless of how the skill was triggered, and it's on an event mh
   already wires: `PostToolUseFailure` today, `PreToolUse` for gates [9]. A new `PostToolUse` matcher
   on `Write`, filtering `tool_input.file_path` for a temp-dir prefix and (to avoid false positives
   from any other temp-file write) grepping the written content for the mandated "suggested skills"
   heading, is the one reliable observation point [1][9].
2. **A companion mh slash-command reintroduces the exact friction being removed.** The user's own
   standing instruction on `disable-model-invocation` surfaces is to hand back a literal string to
   type [10]. A hypothetical `/mh:resume-handoff` would mean typing a command every time instead of
   remembering a path every time — smaller friction, same shape of friction. A zero-typing surface
   (a `SessionStart` hook) is a strictly better fit for "as convenient as possible," and mh already
   has three `SessionStart` hooks (`command-root-anchor`, `doctrine-bootstrap`,
   `memory-health-nudge`) injecting `additionalContext` on every session boot with no user action
   required [11].

## Options considered

**(a) A companion mh skill/slash-command that finds and prints the most recent handoff file.**
Requires a native mh skill plus a small script. Feasible only as content-search (grep temp dirs for
files containing "suggested skills"), since there is no filename/path convention to glob on [1].
Effort: small (one skill dir, one script, following mh's own "find the transcript, don't guess by
mtime" caution about ambiguous latest-file heuristics on shared machines [12]). Composer-not-creator
fit: acceptable — wraps rather than reimplements the handoff skill's output — but it fails the
"as convenient as possible" bar on its own, since it still requires the user to type something
every session, which is the exact friction being removed. Best used as a fallback command inside
option (c), not as the primary fix.

**(b) A hook that surfaces the path automatically right after handoff runs.** Not viable as
`PostToolUse` on the `Skill` tool (constraint 1, above) — a `disable-model-invocation` skill is not
guaranteed to produce a matchable `Skill` tool call. Viable as `PostToolUse` on `Write`: detect the
handoff file by content marker at the moment it's written, and stamp its path into a small durable
pointer file (e.g. `~/.claude/mh-handoff-pointer.json` with path + timestamp) mh controls, outside
temp. One-way-door-ness: low — it's an additive hook plus a pointer file, fully reversible by
removing the hook entry and deleting the pointer. Requires: one new `PostToolUse` matcher-set entry
in `hooks/hooks.json` plus one script (~20 lines, same shape as existing gates [8][9]).

**(c) Surface at `SessionStart` instead of at write time, reading the pointer from (b).** mh already
runs three `SessionStart` hooks injecting `additionalContext` with zero user action [11]. A fourth
reads the pointer file from (b), checks a freshness window (e.g. under ~24h, since the doc says temp
can be swept within the hour on some harnesses and definitely across a reboot [3][4]), and if fresh,
injects "a handoff from N hours ago is waiting at `<path>` — read it if you're continuing that work"
into context automatically, every session, no typing. If stale or absent, it says nothing (mirrors
the existing `memory-health-nudge` hook's "silent when clean" convention [11]). This is the
zero-typing answer to "as convenient as possible": the write-time hook captures the path at the one
moment it's knowable, the session-start hook surfaces it at the one moment it's needed, and nothing
requires the user to remember or type a path in between.

**Fixed/predictable output location the skill already supports.** Checked and ruled out: SKILL.md
takes no path argument and the frontmatter has no path-configuration key — "argument-hint" is
about task focus, not output location [1]. mh cannot make the handoff skill write somewhere
predictable without forking it, which composer-not-creator doctrine argues against absent a
concrete blocker [7].

## Recommendation

Build (b) + (c): a `PostToolUse` hook on `Write` that detects a handoff file by content marker and
stamps a durable pointer, plus a fourth `SessionStart` hook that reads that pointer and surfaces the
path automatically (time-boxed, silent when stale/absent) — same additive, reversible pattern as
mh's three existing `SessionStart` hooks. This is the only option that needs zero typing from the
user on either end, which is what "not remembering or typing the path" actually requires; skip
option (a) as a standalone fix, since a typed lookup command just relocates the friction rather than
removing it.

## Open questions / unverified

- Whether `in-progress/claude-handoff` is reachable in some other install path or a newer plugin
  version — only this machine's cached v1.2.3 manifest was checked, and it excludes that skill [1][6].
- Whether a typed `/mattpocock-skills:handoff` actually dispatches a matchable `Skill` tool call at
  all on this harness version, versus expanding inline before any tool call — flagged as unverified
  in a prior-session finding surfaced via this session's injected memory index, not independently
  re-tested here.
- Exact macOS temp path the skill's invoking agent tends to pick (`$TMPDIR` vs `/tmp`) was not
  empirically captured by running `/mattpocock-skills:handoff` in this session — the content-marker
  detection in option (b) sidesteps needing this, but confirming it would sharpen the `Write`-matcher
  hook's path-prefix filter.

## Sources

1. `~/.claude/plugins/cache/mattpocock/mattpocock-skills/1.2.3/skills/productivity/handoff/SKILL.md`
2. `~/.claude/plugins/cache/mattpocock/mattpocock-skills/1.2.3/skills/productivity/handoff/agents/openai.yaml`
3. `~/.claude/plugins/cache/mattpocock/mattpocock-skills/1.2.3/docs/productivity/handoff.md`
4. https://www.aihero.dev/skills-handoff.md (fetched 2026-09-09)
5. `~/.claude/plugins/cache/mattpocock/mattpocock-skills/1.2.3/skills/in-progress/claude-handoff/SKILL.md`
6. `~/.claude/plugins/cache/mattpocock/mattpocock-skills/1.2.3/.claude-plugin/plugin.json`
7. `docs/reference/composer-not-creator.md` (this repo)
8. `hooks/gates/codex-setup-guard.py`, `hooks/gates/codex-setup-guard.sh` (this repo)
9. `hooks/hooks.json` (this repo) — `PreToolUse`, `PostToolUseFailure` matcher sets
10. Operator's global `CLAUDE.md` — "Disable-Model-Invocation Surfaces" section
11. `hooks/hooks.json` (this repo) — `SessionStart` matcher set (`command-root-anchor`,
    `doctrine-bootstrap`, `memory-health-nudge`)
12. `skills/meta/learn/scripts/find-transcript.sh` (this repo) — rationale for session-id lookup
    over mtime-latest on a shared tree
