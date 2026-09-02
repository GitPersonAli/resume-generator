#!/usr/bin/env bash
# validate-knowledge.sh - deterministic gate validator for the user's knowledge.yaml.
#
# Usage:
#   validate-knowledge.sh <path-to-knowledge.yaml>
#
# Schema reference: <SKILL_ROOT>/assets/knowledge.template.yaml
# Placeholder sentinel regex: <[A-Z][A-Za-z0-9_]*>   (e.g. <YOUR_NAME>, <TECH_1>,
# <DEGREE_NAME_E_G_MSc_in_X>)
#
# Gate rules (required):
#   - `name` and `email`: non-empty strings without a sentinel
#   - `education`: a list with >= 1 entry whose `degree` AND `university` are filled
#   - at least one of:
#       an `experience` entry with `title` AND `company` filled, or
#       a `projects` entry with `name` filled
#   Any other sentinel anywhere in the file is a warning, not a gate failure
#   (the generator must treat such values as absent so they never reach the PDF).
#
# Stdout contract (KEY=value, one per line):
#   STATUS=ok|missing|invalid-yaml|not-found|no-parser
#   PARSER=python|grep
#   MISSING=<dotted.path>                         required field absent/empty
#   PLACEHOLDER=<dotted.path>=<value>             required field still holds a sentinel
#   OPTIONAL_PLACEHOLDER=<dotted.path>=<value>    sentinel in an optional field (warning)
#   PARSE_ERROR=<line>:<col>: <message>           invalid yaml (PyYAML problem_mark, 1-based)
#   PLACEHOLDER_LINE=<n>:<text>                   grep fallback only (PARSER=grep)
#   SUMMARY=<one line human summary>
#
# Exit codes:
#   0 = ok (gate passes)
#   1 = gate failure (MISSING/PLACEHOLDER in a required field)
#   2 = invalid yaml
#   3 = file not found
#   4 = bad arguments
#   6 = no parser (python3 or PyYAML missing): grep-only scan was emitted and the
#       caller must do the structural check by hand
#
# Set RESUME_VALIDATE_FORCE_GREP=1 to exercise the grep fallback deliberately.

set -u

# shellcheck source-path=SCRIPTDIR
# shellcheck source=lib.sh
. "$(dirname "$0")/lib.sh"

if [ "$#" -ne 1 ] || [ -z "${1:-}" ]; then
  echo "usage: $0 <path-to-knowledge.yaml>" >&2
  echo "SUMMARY=bad arguments: expected exactly one path to a knowledge.yaml"
  exit 4
fi

file="$1"
if [ ! -f "$file" ]; then
  echo "STATUS=not-found"
  echo "SUMMARY=no such file: $file"
  exit 3
fi

have_python=0
if [ -z "${RESUME_VALIDATE_FORCE_GREP:-}" ] && have python3 \
   && python3 -c 'import yaml' >/dev/null 2>&1; then
  have_python=1
fi

if [ "$have_python" -eq 1 ]; then
  python3 - "$file" <<'PY'
import re
import sys

import yaml

SENTINEL = re.compile(r"<[A-Z][A-Za-z0-9_]*>")
path = sys.argv[1]

try:
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")
except Exception:
    pass


def clean(value):
    text = re.sub(r"\s+", " ", str(value)).strip()
    if len(text) > 120:
        text = text[:117] + "..."
    return text


def die_invalid(line, col, message):
    message = clean(message)
    print("STATUS=invalid-yaml")
    print("PARSER=python")
    print("PARSE_ERROR=%d:%d: %s" % (line, col, message))
    print("SUMMARY=knowledge.yaml is not valid YAML (line %d, column %d): %s" % (line, col, message))
    sys.exit(2)


try:
    with open(path, "r", encoding="utf-8-sig") as fh:
        data = yaml.safe_load(fh)
except yaml.YAMLError as exc:
    mark = getattr(exc, "problem_mark", None) or getattr(exc, "context_mark", None)
    line = mark.line + 1 if mark is not None else 0
    col = mark.column + 1 if mark is not None else 0
    problem = getattr(exc, "problem", None) or str(exc)
    context = getattr(exc, "context", None)
    die_invalid(line, col, "%s (%s)" % (problem, context) if context else problem)
except UnicodeDecodeError as exc:
    die_invalid(0, 0, "file is not UTF-8 text: %s" % exc)
except OSError as exc:
    print("STATUS=not-found")
    print("SUMMARY=cannot read %s: %s" % (path, exc))
    sys.exit(3)

if data is None:
    data = {}
if not isinstance(data, dict):
    die_invalid(1, 1, "top-level document must be a mapping of key: value pairs")

missing = []          # dotted paths of required fields that are absent/empty
placeholder = []      # (path, value) of required fields holding a sentinel
optional = []         # (path, value) of sentinels in optional fields
notes = []
required_paths = set()


def has_sentinel(value):
    return isinstance(value, str) and SENTINEL.search(value) is not None


def filled(value):
    if isinstance(value, bool):
        return True
    if isinstance(value, (int, float)):
        return True
    if isinstance(value, str):
        return value.strip() != "" and SENTINEL.search(value) is None
    return False


def check_required(dotted, value):
    required_paths.add(dotted)
    if has_sentinel(value):
        placeholder.append((dotted, value))
        return False
    if not filled(value):
        missing.append(dotted)
        return False
    return True


# --- name / email -----------------------------------------------------------
check_required("name", data.get("name"))
check_required("email", data.get("email"))

# --- education --------------------------------------------------------------
education = data.get("education")
edu_count = 0
if not isinstance(education, list) or len(education) == 0:
    missing.append("education")
    required_paths.add("education")
else:
    edu_count = len(education)
    complete = []
    for entry in education:
        if isinstance(entry, dict):
            complete.append(filled(entry.get("degree")) and filled(entry.get("university")))
        else:
            complete.append(False)
    if any(complete):
        for i, entry in enumerate(education):
            if complete[i]:
                continue
            if isinstance(entry, dict):
                for key in ("degree", "university"):
                    v = entry.get(key)
                    if not has_sentinel(v) and not filled(v):
                        notes.append("education[%d].%s is empty" % (i, key))
            else:
                notes.append("education[%d] is not a mapping" % i)
    else:
        for i, entry in enumerate(education):
            if isinstance(entry, dict):
                check_required("education[%d].degree" % i, entry.get("degree"))
                check_required("education[%d].university" % i, entry.get("university"))
            else:
                missing.append("education[%d]" % i)
                required_paths.add("education[%d]" % i)

# --- experience / projects --------------------------------------------------
experience = data.get("experience")
projects = data.get("projects")
if experience is not None and not isinstance(experience, list):
    notes.append("experience is not a list")
if projects is not None and not isinstance(projects, list):
    notes.append("projects is not a list")
exp_list = experience if isinstance(experience, list) else []
prj_list = projects if isinstance(projects, list) else []

exp_complete = [isinstance(e, dict) and filled(e.get("title")) and filled(e.get("company")) for e in exp_list]
prj_complete = [isinstance(p, dict) and filled(p.get("name")) for p in prj_list]

if any(exp_complete) or any(prj_complete):
    for i, e in enumerate(exp_list):
        if exp_complete[i]:
            continue
        if isinstance(e, dict):
            for key in ("title", "company"):
                v = e.get(key)
                if not has_sentinel(v) and not filled(v):
                    notes.append("experience[%d].%s is empty" % (i, key))
        else:
            notes.append("experience[%d] is not a mapping" % i)
    for i, p in enumerate(prj_list):
        if prj_complete[i]:
            continue
        if isinstance(p, dict):
            v = p.get("name")
            if not has_sentinel(v) and not filled(v):
                notes.append("projects[%d].name is empty" % i)
        else:
            notes.append("projects[%d] is not a mapping" % i)
else:
    if not exp_list and not prj_list:
        missing.append("experience")
        missing.append("projects")
        required_paths.add("experience")
        required_paths.add("projects")
    for i, e in enumerate(exp_list):
        if isinstance(e, dict):
            check_required("experience[%d].title" % i, e.get("title"))
            check_required("experience[%d].company" % i, e.get("company"))
        else:
            missing.append("experience[%d]" % i)
            required_paths.add("experience[%d]" % i)
    for i, p in enumerate(prj_list):
        if isinstance(p, dict):
            check_required("projects[%d].name" % i, p.get("name"))
        else:
            missing.append("projects[%d]" % i)
            required_paths.add("projects[%d]" % i)


# --- every other sentinel is a warning -------------------------------------
def walk(node, dotted):
    if isinstance(node, dict):
        for key, value in node.items():
            walk(value, "%s.%s" % (dotted, key) if dotted else str(key))
    elif isinstance(node, list):
        for i, value in enumerate(node):
            walk(value, "%s[%d]" % (dotted, i))
    elif isinstance(node, str):
        if SENTINEL.search(node) and dotted not in required_paths:
            optional.append((dotted, node))


walk(data, "")

# --- emit -------------------------------------------------------------------
gate_ok = not missing and not placeholder
print("STATUS=%s" % ("ok" if gate_ok else "missing"))
print("PARSER=python")
for dotted in missing:
    print("MISSING=%s" % dotted)
for dotted, value in placeholder:
    print("PLACEHOLDER=%s=%s" % (dotted, clean(value)))
for dotted, value in optional:
    print("OPTIONAL_PLACEHOLDER=%s=%s" % (dotted, clean(value)))

note_text = ("; note: " + "; ".join(notes)) if notes else ""
if gate_ok:
    print(
        "SUMMARY=ok: name, email, education=%d, experience=%d, projects=%d; optional placeholders=%d%s"
        % (edu_count, sum(1 for c in exp_complete if c), sum(1 for c in prj_complete if c), len(optional), note_text)
    )
    sys.exit(0)

parts = []
if missing:
    parts.append("missing=%d (%s)" % (len(missing), ", ".join(missing)))
if placeholder:
    parts.append("placeholders=%d (%s)" % (len(placeholder), ", ".join(p for p, _ in placeholder)))
print("SUMMARY=gate failed: %s; optional placeholders=%d%s" % ("; ".join(parts), len(optional), note_text))
sys.exit(1)
PY
  exit $?
fi

# ---- grep-only fallback (no python3 / no PyYAML) -----------------------------
echo "STATUS=no-parser"
echo "PARSER=grep"
count=0
hits="$(tr -d '\r' < "$file" | grep -nE "$RG_SENTINEL_RE" 2>/dev/null || true)"
if [ -n "$hits" ]; then
  while IFS= read -r line; do
    [ -n "$line" ] || continue
    n="${line%%:*}"
    text="${line#*:}"
    echo "PLACEHOLDER_LINE=$n:$text"
    count=$((count + 1))
  done <<EOF
$hits
EOF
fi
echo "SUMMARY=no YAML parser available (python3 with PyYAML needed); grep found $count line(s) with placeholder sentinels - check required fields manually"
exit 6
