#!/usr/bin/env python3
"""Check Markdown prose against a partial, mechanical subset of ASD-STE100
(Simplified Technical English) writing rules. Not a compliance certification —
see rules.md. Report-only: never edits a scanned file.

Confirmed findings: sentence word-count limits (5.1/6.3, incl. the Rule 8.5
nested-parenthetical case), paragraph length (6.6), semicolons (8.1),
contractions (4.2).

Advisory findings (heuristic, may misfire): passive voice (3.6), -ing verb
form (3.5), stacked auxiliaries (3.4), non-American spelling (1.14), long
noun runs (2.1). Every finding from an auto-classified sentence is advisory,
since misclassifying procedural vs. descriptive changes which limit applies.

Run with --selftest to check the word counter against the standard's own
worked examples.
"""
import argparse
import json
import os
import re
import subprocess
import sys

MAX_PROCEDURAL_WORDS = 20  # Rule 5.1
MAX_DESCRIPTIVE_WORDS = 25  # Rule 6.3
MAX_PARAGRAPH_SENTENCES = 6  # Rule 6.6

FROZEN_DIRS = ("docs/research/", "docs/post-mortems/", "docs/plans/")
FROZEN_FILES = ("CHANGELOG.md", "docs/METHODOLOGY.md")

CODE_PLACEHOLDER = ""
PAREN_PLACEHOLDER = ""
INLINE_CODE_RE = re.compile(r"`[^`\n]*`")
URL_RE = re.compile(r"https?://\S+")
PAREN_RE = re.compile(r"\(([^()]*)\)")
NUMBER_RE = re.compile(r"^\d+(\.\d+)?$")
SENT_SPLIT_RE = re.compile(r'(?<=[.!?])\s+(?=[A-Z0-9"`(])')
MD_LINK_RE = re.compile(r"\[([^\]]*)\]\([^)]*\)")
# 's is ambiguous with a possessive ("the dog's bone"), so it's only treated
# as a contraction after a closed list of words that actually contract to 's
# ("it's", "that's", ...) -- never a bare \w+'s.
CONTRACTION_RE = re.compile(
    r"\b\w+n['’]t\b"
    r"|\b\w+['’](?:re|ve|ll|d|m)\b"
    r"|\b(?:it|he|she|that|there|here|what|who|let|where|how|when|why)['’]s\b",
    re.IGNORECASE)
PASSIVE_RE = re.compile(r"\b(?:is|are|was|were|be|been|being)\s+\w+ed\b", re.IGNORECASE)
ING_RE = re.compile(r"\b(?:is|are|was|were|be|been|being)\s+\w+ing\b", re.IGNORECASE)
AUX_STACK_RE = re.compile(
    r"\b(?:will|would|shall|should|can|could|may|might|must)\s+(?:not\s+)?"
    r"(?:have|has|had)\s+been\b", re.IGNORECASE)
NOUN_RUN_RE = re.compile(r"(?:\b[A-Z][a-zA-Z]*\b\s+){3,}\b[A-Z][a-zA-Z]*\b")

# ponytail: closed lists, not general NLP — extend here if a real doc needs
# a unit/abbreviation this misses. STE's own dictionary is not bundled (v1
# scope decision), so this is an author-defined ceiling, not from the standard.
UNIT_TOKENS = {"°c", "°f", "kg", "mg", "mm", "cm", "km", "psi", "ma", "kw",
               "hz", "ohms", "ohm", "rpm", "a.m", "p.m", "kb", "mb", "gb", "ms"}
DEGREE_UNIT_WORDS = {"celsius", "fahrenheit", "kelvin"}
ABBREV_PREFIX_TOKENS = {"no", "fig", "rev", "item"}
SPELLING_MAP = {
    "colour": "color", "organise": "organize", "organised": "organized",
    "analyse": "analyze", "analysed": "analyzed", "behaviour": "behavior",
    "favour": "favor", "favourite": "favorite", "centre": "center",
    "licence": "license", "defence": "defense", "programme": "program",
    "optimise": "optimize", "optimised": "optimized", "recognise": "recognize",
    "utilise": "utilize", "customise": "customize", "cancelled": "canceled",
}
IMPERATIVE_STARTS = {
    "run", "use", "check", "add", "remove", "delete", "create", "write",
    "read", "verify", "confirm", "never", "always", "do", "don't", "ensure",
    "set", "stage", "commit", "avoid", "keep", "call", "invoke", "pass",
    "return", "install", "enable", "disable", "open", "close", "start",
    "stop", "update", "edit", "move", "copy", "build", "test",
}

# The closing "---" needs a following newline OR end-of-string, so frontmatter
# that ends exactly at EOF (no trailing blank line) still parses instead of
# silently falling through to be scanned as body text.
FRONTMATTER_RE = re.compile(r"\A---\n(.*?\n)---(?:\n|\Z)", re.DOTALL)


def normalize_tok(tok):
    return tok.strip(".,;:!?\"'()").lower()


def analyze_sentence(text):
    """STE word count for one sentence. Returns (count, nested_sentences)."""
    nested = []

    def paren_sub(m):
        inner = m.group(1)
        if re.search(r"\s", inner.strip()):
            nested.append(inner)  # Rule 8.5: non-bare parenthetical is its own sentence
        return PAREN_PLACEHOLDER

    working = INLINE_CODE_RE.sub(CODE_PLACEHOLDER, text)  # protected 1-word token, not an STE rule
    working = URL_RE.sub(CODE_PLACEHOLDER, working)
    working = MD_LINK_RE.sub(r"\1", working)
    working = PAREN_RE.sub(paren_sub, working)

    tokens = working.split()
    merged = []
    i = 0
    while i < len(tokens):
        t = tokens[i]
        nt = normalize_tok(t)
        if i + 1 < len(tokens):
            nt1 = normalize_tok(tokens[i + 1])
            if NUMBER_RE.match(nt) and nt1 in UNIT_TOKENS:  # Rule 8.6: number+unit = 1 word
                merged.append(t + " " + tokens[i + 1]); i += 2; continue
            if nt in ABBREV_PREFIX_TOKENS and NUMBER_RE.match(nt1):  # Rule 8.6: alphanumeric identifier
                merged.append(t + " " + tokens[i + 1]); i += 2; continue
            if NUMBER_RE.match(nt) and nt1 == "degrees" and i + 2 < len(tokens):
                nt2 = normalize_tok(tokens[i + 2])
                if nt2 in DEGREE_UNIT_WORDS:
                    merged.append(" ".join(tokens[i:i + 3])); i += 3; continue
        merged.append(t)
        i += 1
    return len(merged), nested


def split_sentences(text):
    sentences, start = [], 0
    for m in SENT_SPLIT_RE.finditer(text):
        sentences.append((text[start:m.start()], start))
        start = m.end()
    tail = text[start:]
    if tail.strip():
        sentences.append((tail, start))
    return sentences


def classify_sentence(sentence, is_list_item):
    if is_list_item:
        return "procedural"
    m = re.match(r"[\"'`(]*([A-Za-z']+)", sentence.strip())
    if m and m.group(1).lower() in IMPERATIVE_STARTS:
        return "procedural"
    return "descriptive"


def check_text_block(text, base_line, mode, source, is_list_item=False, paragraph_check=True):
    confirmed, advisory = [], []
    sentences = split_sentences(text)

    for sentence, offset in sentences:
        eff_mode = mode if mode != "auto" else classify_sentence(sentence, is_list_item)
        limit = MAX_PROCEDURAL_WORDS if eff_mode == "procedural" else MAX_DESCRIPTIVE_WORDS
        line = base_line + text.count("\n", 0, offset)
        base = {"source": source, "line": line, "sentence": sentence.strip()[:120]}
        bucket = advisory if mode == "auto" else confirmed

        count, nested = analyze_sentence(sentence)
        if count > limit:
            f = dict(base, rule=("5.1" if eff_mode == "procedural" else "6.3"),
                     words=count, limit=limit, mode=eff_mode)
            if mode == "auto":
                f["guessed_mode"] = True
            bucket.append(f)
        for inner in nested:
            inner_count, _ = analyze_sentence(inner)
            if inner_count > limit:
                bucket.append(dict(base, rule="8.5", words=inner_count, limit=limit,
                                    mode=eff_mode, nested=True, sentence=inner.strip()[:120]))

        if ";" in sentence:
            confirmed.append(dict(base, rule="8.1", message="semicolon"))
        cm = CONTRACTION_RE.search(sentence)
        if cm:
            confirmed.append(dict(base, rule="4.2", message="contraction: " + cm.group(0)))
        if PASSIVE_RE.search(sentence):
            advisory.append(dict(base, rule="3.6", message="possible passive voice"))
        if ING_RE.search(sentence):
            advisory.append(dict(base, rule="3.5", message="-ing verb form"))
        if AUX_STACK_RE.search(sentence):
            advisory.append(dict(base, rule="3.4", message="stacked auxiliary verbs"))
        if NOUN_RUN_RE.search(sentence):
            advisory.append(dict(base, rule="2.1", message="long noun run"))
        for wrong, right in SPELLING_MAP.items():
            if re.search(r"\b" + wrong + r"\b", sentence, re.IGNORECASE):
                advisory.append(dict(base, rule="1.14", message=f"non-American spelling: {wrong} -> {right}"))

    if paragraph_check and not is_list_item and len(sentences) > MAX_PARAGRAPH_SENTENCES:
        confirmed.append({"source": source, "line": base_line, "rule": "6.6",
                           "sentences": len(sentences)})
    return confirmed, advisory


def extract_frontmatter(text):
    m = FRONTMATTER_RE.match(text)
    if not m:
        return None, 0, text, 1
    fm_text = m.group(1)
    fm_start_line = 2  # file line 1 is the opening "---"
    body = text[m.end():]
    body_start_line = text.count("\n", 0, m.end()) + 1
    return fm_text, fm_start_line, body, body_start_line


def check_frontmatter(fm_text, fm_start_line):
    confirmed, advisory, errors = [], [], []
    try:
        import yaml
    except ImportError:
        errors.append({"rule": "tooling", "message": "PyYAML unavailable; frontmatter description not checked"})
        return confirmed, advisory, errors

    try:
        data = yaml.safe_load(fm_text)
    except (yaml.YAMLError, ValueError) as e:
        # ValueError: PyYAML's SafeLoader resolves some scalars (e.g. an
        # implicit timestamp like "2026-99-99") by calling datetime.date(...),
        # which raises ValueError rather than YAMLError on an invalid value.
        errors.append({"rule": "tooling", "message": f"malformed frontmatter YAML: {e}"})
        return confirmed, advisory, errors

    if not isinstance(data, dict) or "description" not in data:
        return confirmed, advisory, errors
    desc = data["description"]
    if not isinstance(desc, str):
        errors.append({"rule": "tooling", "message": "frontmatter 'description' is not a string"})
        return confirmed, advisory, errors

    line = fm_start_line
    try:
        node = yaml.compose(fm_text, Loader=yaml.SafeLoader)
        if node is not None and hasattr(node, "value"):
            for k, _ in node.value:
                if getattr(k, "value", None) == "description":
                    line = fm_start_line + k.start_mark.line
                    break
    except yaml.YAMLError:
        pass  # keep the fm_start_line fallback

    c, a = check_text_block(desc, line, "descriptive", "frontmatter.description", paragraph_check=False)
    confirmed.extend(c)
    advisory.extend(a)
    return confirmed, advisory, errors


def strip_fenced_code(text):
    out, last = [], 0
    for m in re.finditer(r"^```.*?^```", text, re.DOTALL | re.MULTILINE):
        out.append(text[last:m.start()])
        out.append("\n" * text.count("\n", m.start(), m.end()))
        last = m.end()
    out.append(text[last:])
    return "".join(out)


def strip_tables(text):
    lines = text.split("\n")
    for i, line in enumerate(lines):
        if re.match(r"^\s*\|.*\|\s*$", line) or re.match(r"^\s*[-:| ]+$", line.strip()) and "|" in line:
            lines[i] = ""
    return "\n".join(lines)


def check_body(body, body_start_line, mode):
    confirmed, advisory = [], []
    lines = body.split("\n")
    para_lines, para_start = [], None
    list_item_re = re.compile(r"^\s*(?:[-*+]|\d+\.)\s+")

    def flush():
        if not para_lines:
            return
        text = "\n".join(para_lines)
        line_no = body_start_line + para_start
        if list_item_re.match(para_lines[0]):
            for offset, item_line in enumerate(para_lines):
                c, a = check_text_block(item_line, line_no + offset, mode,
                                         "body", is_list_item=True)
                confirmed.extend(c); advisory.extend(a)
        else:
            c, a = check_text_block(text, line_no, mode, "body")
            confirmed.extend(c); advisory.extend(a)

    for idx, line in enumerate(lines):
        if not line.strip() or line.lstrip().startswith("#"):
            flush()
            para_lines, para_start = [], None
            continue
        if para_start is None:
            para_start = idx
        para_lines.append(line)
    flush()
    return confirmed, advisory


def scan_markdown_file(path, mode):
    confirmed, advisory, errors = [], [], []
    try:
        with open(path, "r", encoding="utf-8") as f:
            text = f.read()
    except (OSError, UnicodeDecodeError) as e:
        errors.append({"rule": "tooling", "message": f"could not read file: {e}"})
        return confirmed, advisory, errors

    fm_text, fm_start_line, body, body_start_line = extract_frontmatter(text)
    if fm_text is not None:
        c, a, e = check_frontmatter(fm_text, fm_start_line)
        confirmed.extend(c); advisory.extend(a); errors.extend(e)

    body = strip_fenced_code(body)
    body = strip_tables(body)
    c, a = check_body(body, body_start_line, mode)
    confirmed.extend(c); advisory.extend(a)
    return confirmed, advisory, errors


def repo_root():
    out = subprocess.run(["git", "rev-parse", "--show-toplevel"],
                          capture_output=True, text=True, check=True)
    return out.stdout.strip()


def is_frozen(rel_path):
    return rel_path.startswith(FROZEN_DIRS) or rel_path in FROZEN_FILES


def _in_repo(root, full_path):
    real = os.path.realpath(full_path)
    return real == root or real.startswith(root + os.sep)


def default_targets(root):
    changed = set()
    scan_errors = []
    head_ok = subprocess.run(["git", "rev-parse", "--verify", "-q", "HEAD"],
                              cwd=root, capture_output=True).returncode == 0
    # A repo with no commits yet has no HEAD to diff against; fall back to
    # --cached so staged files in a brand-new repo are still found instead
    # of the diff command failing and being silently swallowed as "clean".
    diff_cmd = (["git", "diff", "--name-only", "-z", "HEAD"] if head_ok
                else ["git", "diff", "--name-only", "-z", "--cached"])
    for cmd in (diff_cmd, ["git", "ls-files", "--others", "--exclude-standard", "-z"]):
        try:
            out = subprocess.run(cmd, cwd=root, capture_output=True, check=True)
        except subprocess.CalledProcessError as e:
            scan_errors.append({"rule": "tooling",
                                 "message": f"git command failed ({' '.join(cmd)}): {e}"})
            continue
        for part in out.stdout.split(b"\x00"):
            if part:
                changed.add(part.decode("utf-8", "surrogateescape"))

    result = []
    for rel in sorted(changed):
        if not rel.endswith(".md") or is_frozen(rel):
            continue
        full = os.path.join(root, rel)
        if not os.path.isfile(full):
            continue
        # realpath() resolves every ancestor path segment, not just a
        # symlinked leaf -- a plain file reached through a symlinked
        # ancestor directory must be caught too, so this check always runs,
        # not only when the leaf itself is a symlink.
        if not _in_repo(root, full):
            continue
        result.append(full)
    return result, scan_errors


def explicit_targets(root, arg_path):
    full = os.path.abspath(arg_path)
    scan_errors = []
    if not _in_repo(root, full):
        return [], scan_errors
    if os.path.isfile(full):
        return [full], scan_errors
    if not os.path.isdir(full):
        scan_errors.append({"rule": "tooling", "message": f"path does not exist: {arg_path}"})
        return [], scan_errors

    def on_walk_error(exc):
        scan_errors.append({"rule": "tooling", "message": f"could not list directory: {exc}"})

    result = []
    for dirpath, dirnames, filenames in os.walk(full, onerror=on_walk_error):
        dirnames[:] = [d for d in dirnames if _in_repo(root, os.path.join(dirpath, d))]
        for fn in filenames:
            if not fn.endswith(".md"):
                continue
            fp = os.path.join(dirpath, fn)
            if not _in_repo(root, fp):
                continue
            result.append(fp)
    return sorted(result), scan_errors


def format_finding(f):
    if "message" in f:
        return f["message"]
    if "words" in f:
        tag = " [guessed mode]" if f.get("guessed_mode") else ""
        tag += " [nested 8.5]" if f.get("nested") else ""
        return f"{f['words']} words (limit {f['limit']}, mode={f.get('mode', '?')}){tag}: {f['sentence']!r}"
    if "sentences" in f:
        return f"{f['sentences']} sentences (limit {MAX_PARAGRAPH_SENTENCES})"
    return str(f)


def print_human(result):
    for e in result.get("errors", []):
        print(f"[error] {e['message']}")
    for f in result["files"]:
        print(f["path"])
        for c in f["confirmed"]:
            print(f"  [confirmed] rule {c['rule']} line {c['line']}: {format_finding(c)}")
        for a in f["advisory"]:
            print(f"  [advisory]  rule {a['rule']} line {a['line']}: {format_finding(a)}")
        for e in f["errors"]:
            print(f"  [error]     {e['message']}")
    print(f"exit_code={result['exit_code']} (0=clean, 1=confirmed findings, 2=incomplete check)")
    print("Checks a partial, mechanical subset of ASD-STE100 — not a compliance certification.")


def main():
    p = argparse.ArgumentParser(description=(__doc__ or "").splitlines()[0])
    p.add_argument("path", nargs="?", help="file or directory; default: changed .md files in the working tree")
    p.add_argument("--mode", choices=["procedural", "descriptive", "auto"], default="auto")
    p.add_argument("--json", action="store_true")
    p.add_argument("--selftest", action="store_true")
    args = p.parse_args()

    if args.selftest:
        _selftest()
        return

    root = repo_root()
    targets, scan_errors = (explicit_targets(root, args.path) if args.path
                             else default_targets(root))

    files_out, any_confirmed, any_error = [], False, bool(scan_errors)
    for fp in targets:
        confirmed, advisory, errors = scan_markdown_file(fp, args.mode)
        any_confirmed = any_confirmed or bool(confirmed)
        any_error = any_error or bool(errors)
        files_out.append({"path": os.path.relpath(fp, root), "confirmed": confirmed,
                           "advisory": advisory, "errors": errors})

    exit_code = 2 if any_error else (1 if any_confirmed else 0)
    result = {"files": files_out, "errors": scan_errors, "exit_code": exit_code}
    print(json.dumps(result, indent=2)) if args.json else print_human(result)
    sys.exit(exit_code)


def _selftest():
    # Verified fixtures, extracted directly from the ASD-STE100 Issue 9 PDF (see rules.md).
    fixtures = [
        ("Make sure that the EMER pushbutton switch is released (the EMER legend is off).", 10),
        ("Remove the safety pin (10).", 5),
        ("Installation of a Business Class (B/C) Seat", 7),
        ("Make sure that the temperature in the room is 10 °C.", 10),
        ("Make sure that the temperature in the room is 10 degrees Celsius.", 10),
        ("The maintenance team does a test of this system each day at 10 a.m.", 13),
        ("Examine the No. 1 bearing installation.", 5),
        ("The unit weighs 20 kg.", 4),
        ("The spar box has twenty-one ribs.", 6),
        ("Do steps 13 thru 16 a minimum of three times.", 10),
    ]
    for text, expected in fixtures:
        count, _ = analyze_sentence(text)
        assert count == expected, f"{text!r}: got {count}, expected {expected}"

    # Rule 8.5: the nested parenthetical is its own sentence.
    _, nested = analyze_sentence(
        "Make sure that the EMER pushbutton switch is released (the EMER legend is off).")
    assert nested == ["the EMER legend is off"], nested
    inner_count, _ = analyze_sentence(nested[0])
    assert inner_count == 5, inner_count

    # Boundary: 20 words passes the procedural limit, 21 fails.
    words20 = " ".join(f"w{i}" for i in range(1, 21)) + "."
    words21 = " ".join(f"w{i}" for i in range(1, 22)) + "."
    c20, _ = analyze_sentence(words20)
    c21, _ = analyze_sentence(words21)
    assert c20 == 20 and c21 == 21, (c20, c21)

    # Boundary: 25 words passes the descriptive limit, 26 fails.
    words25 = " ".join(f"w{i}" for i in range(1, 26)) + "."
    words26 = " ".join(f"w{i}" for i in range(1, 27)) + "."
    c25, _ = analyze_sentence(words25)
    c26, _ = analyze_sentence(words26)
    assert c25 == 25 and c26 == 26, (c25, c26)

    # Inline code is a protected ONE-word token, never silently excluded to
    # zero (that under-counted a 21-word sentence as 20 and let it pass).
    words20_plus_code = " ".join(f"w{i}" for i in range(1, 21)) + " `code`."
    c_code, _ = analyze_sentence(words20_plus_code)
    assert c_code == 21, c_code

    confirmed, _ = check_text_block(words21 + " " + words21, 1, "procedural", "test")
    assert any(f["rule"] == "5.1" for f in confirmed)

    confirmed, _ = check_text_block("Do not use this; do not use that.", 1, "descriptive", "test")
    assert any(f["rule"] == "8.1" for f in confirmed)

    confirmed, _ = check_text_block("It's fine. We won't do that.", 1, "descriptive", "test")
    assert any(f["rule"] == "4.2" for f in confirmed)

    # Curly apostrophe contractions are caught too, not just the straight one.
    confirmed, _ = check_text_block("We don’t stop.", 1, "descriptive", "test")
    assert any(f["rule"] == "4.2" for f in confirmed), confirmed

    # A genuine possessive is not mistaken for a contraction.
    confirmed, _ = check_text_block("Check the dog's bone before you leave.", 1, "descriptive", "test")
    assert not any(f["rule"] == "4.2" for f in confirmed), confirmed

    # Frontmatter: top-level description is found, not a nested metadata.description.
    fm = ('name: x\nmetadata:\n  description: "nested, not this one"\n'
          'description: "' + words26.rstrip(".") + '"\n')
    confirmed, _, errors = check_frontmatter(fm, 2)
    assert not errors, errors
    assert any(f["rule"] == "6.3" for f in confirmed), confirmed
    assert confirmed[0]["line"] == 5, confirmed[0]["line"]

    # A non-string description is a tool error, not a silent clean pass.
    _, _, errors = check_frontmatter("description: [1, 2]\n", 2)
    assert errors and "not a string" in errors[0]["message"]

    # Malformed YAML in the frontmatter block is a tool error, not a crash
    # or a silent clean pass.
    _, _, errors = check_frontmatter("description: [1, 2\n", 2)
    assert errors and "malformed" in errors[0]["message"], errors

    # A missing PyYAML dependency fails loud with a tool error, never a
    # silent "clean" pass. sys.modules[name] = None forces ImportError on
    # the next `import yaml`, the standard way to simulate this in-process.
    import sys as _sys
    _saved_yaml = _sys.modules.pop("yaml", None)
    _sys.modules["yaml"] = None  # type: ignore[assignment]
    try:
        _, _, errors = check_frontmatter('description: "hi"\n', 2)
    finally:
        del _sys.modules["yaml"]
        if _saved_yaml is not None:
            _sys.modules["yaml"] = _saved_yaml
    assert errors and "PyYAML unavailable" in errors[0]["message"], errors

    # A block-scalar description (`description: |`) is parsed and checked
    # like any other string value.
    fm_block = "description: |\n  " + words26.rstrip(".") + "\n"
    confirmed, _, errors = check_frontmatter(fm_block, 2)
    assert not errors, errors
    assert any(f["rule"] == "6.3" for f in confirmed), confirmed

    # A YAML scalar that resolves via a ValueError (an invalid implicit
    # date/timestamp), not a YAMLError, is still a tool error, not a crash.
    _, _, errors = check_frontmatter("description: 2026-99-99\n", 2)
    assert errors and "malformed" in errors[0]["message"], errors

    # Frontmatter closing exactly at EOF (no trailing blank line) still
    # parses, instead of falling through and being scanned as body text.
    fm_start, _, body, _ = extract_frontmatter('---\ndescription: "hi"\n---')
    assert fm_start is not None and body == "", (fm_start, body)

    # An unreadable file (chmod 000) is a tool error (exit 2), never a
    # crash or a silent "clean" pass.
    import tempfile
    with tempfile.NamedTemporaryFile(suffix=".md", delete=False) as tf:
        tf.write(b"Some text.\n")
        unreadable_path = tf.name
    os.chmod(unreadable_path, 0)
    try:
        _, _, errors = scan_markdown_file(unreadable_path, "auto")
    finally:
        os.chmod(unreadable_path, 0o644)
        os.unlink(unreadable_path)
    assert errors and "could not read" in errors[0]["message"], errors

    print("ste-lint.py selftest ok")


if __name__ == "__main__":
    main()
