## ASD-STE100 rules `ste-lint` checks

Rule numbers and page references are cited for lookup in ASD-STE100 Issue 9
(`asd-ste100.org`); the wording below is this skill's own paraphrase, not a
reproduction of the standard's text — the standard's own copyright notice
covers the whole document. This is a partial, mechanical subset of STE, not
a compliance certification: STE's own approved-word dictionary is not
checked (it is copyright-restricted, and this skill treats project jargon
as a valid STE technical noun, Rule 1.8).

**Load when:** interpreting a `ste-lint.py` finding, or deciding whether an
advisory finding is a real violation.

### Confirmed (mechanical, script-verified)

- **5.1** — a procedural sentence (an instruction) has at most 20 words.
- **6.3** — a descriptive sentence has at most 25 words.
- **8.5** — text in parentheses counts as one word toward its sentence, but
  if that text is more than a bare identifier or abbreviation, it also forms
  its own sentence and gets its own word-count check.
- **6.6** — a paragraph has at most 6 sentences.
- **8.1** — no semicolons.
- **4.2** — no contractions (don't drop letters to shorten a sentence).

Word counting follows the standard's own rules (8.4, 8.6, 8.7): a number, a
number with its unit, an abbreviation, an alphanumeric identifier, quoted
text, and a hyphenated word each count as one word. `ste-lint.py` extends
this same idea, as its own convention rather than an STE rule, to Markdown's
inline-code spans: each one counts as one protected word, so it can't be
silently deleted and under-count a sentence.

### Advisory (heuristic — may misfire; never treated as a hard failure)

- **3.6** — prefer active voice; STE allows passive only in specific
  descriptive-writing cases.
- **3.5** — an `-ing` verb form should be a technical noun or a modifier,
  not a continuous-tense verb.
- **3.4** — avoid stacking auxiliary verbs ("will have been ...").
- **1.14** — use American spelling.
- **2.1** — a multi-word technical noun should be at most 3 words.

Any word-count finding on an auto-classified sentence (see `--mode` in
`SKILL.md`) is also advisory, since a wrong procedural/descriptive guess
changes which limit applies.

### Judgment (not scripted — apply by reading)

- **5.2 / 5.3** — one instruction per sentence, in the imperative (command)
  form.
- **6.5** — one topic per paragraph.
- **9.3** — avoid phrasal verbs.
- **9.4 / 1.11** — use one term per concept, consistently, across a
  document (this project's own biggest source of drift: pick one name for a
  thing and don't rename it mid-document).

### Source

`docs/research/asd-ste100-2026-09-08.md` — primary-source research on the
standard itself. Rule text and worked examples for this skill were
re-verified directly against the Issue 9 PDF during design (`pdftotext`
extraction), since the research file lists section names, not rule text.
