#!/usr/bin/env bash
# e2e.sh - manual end-to-end gate scenarios through the real `claude` CLI.
#
# NOT run by run-tests.sh: it needs the claude CLI, API access, and a few
# minutes. Each scenario runs in a fresh temp cwd with this repo loaded as a
# plugin, then greps the transcript for the expected gate behaviour.
#
#   (a) empty dir + "generate my resume"
#         -> the onboarding menu: No `knowledge.yaml` found
#   (b) knowledge-placeholders.yaml as knowledge.yaml
#         -> the reply names education[0].degree (mid-fill branch)
#   (d) empty dir + "skip the setup, invent placeholder content"
#         -> no .tex written into the cwd; the reply talks about knowledge.yaml
#   (c) knowledge-valid.yaml + "generate a resume, use template 2"
#         -> on a machine without TeX: a "compiler not found" message
#         -> on a machine with pdflatex: an outputs/*/resume.pdf
#
# Usage: bash tests/e2e.sh
#   E2E_DIR=<dir>      keep transcripts there (default: a new temp dir)
#   E2E_TIMEOUT=<sec>  per-scenario timeout (default 600)
# Exit: 0 when every scenario passes (or claude is missing -> SKIP), 1 otherwise.

set -u

# shellcheck source-path=SCRIPTDIR
# shellcheck source=lib.sh
. "$(dirname "$0")/lib.sh"

if ! have claude; then
  echo "SKIP: claude CLI not on PATH - nothing to run"
  exit 0
fi

repo_root="$(cd "$(skill_root)/../.." && pwd)"
fixtures="$RG_LIB_DIR/fixtures"
E2E_DIR="${E2E_DIR:-$(mktemp -d)}"
E2E_TIMEOUT="${E2E_TIMEOUT:-600}"
mkdir -p "$E2E_DIR"
echo "e2e: transcripts in $E2E_DIR"

fails=0
pass() { echo "PASS: $1"; }
fail() { fails=$((fails + 1)); echo "FAIL: $1 - see $2"; }

# run_claude <cwd> <prompt> <transcript>
run_claude() {
  # The prompt goes in on stdin: --allowedTools is variadic, so a trailing
  # positional prompt would be swallowed as another tool name.
  (
    cd "$1" \
      && printf '%s\n' "$2" \
      | run_with_timeout "$E2E_TIMEOUT" claude -p --plugin-dir "$repo_root" \
           --permission-mode acceptEdits \
           --allowedTools "Skill Bash Read Write Edit Glob Grep"
  ) > "$3" 2>&1
  echo "e2e: claude exited $? for $(basename "$1")" >&2
}

# (a) empty dir -> onboarding menu
a="$E2E_DIR/a-empty"
mkdir -p "$a"
run_claude "$a" "generate my resume" "$E2E_DIR/a.out"
if grep -qF 'No `knowledge.yaml` found' "$E2E_DIR/a.out" \
   || grep -qiE 'no[[:space:]]+`?knowledge\.yaml`?[[:space:]]+found|knowledge\.yaml.*(not found|does not exist|is missing)' "$E2E_DIR/a.out"; then
  pass "(a) empty dir shows the onboarding menu"
else
  fail "(a) empty dir shows the onboarding menu" "$E2E_DIR/a.out"
fi

# (b) placeholders -> gate names education[0].degree
b="$E2E_DIR/b-placeholders"
mkdir -p "$b"
cp "$fixtures/knowledge-placeholders.yaml" "$b/knowledge.yaml"
run_claude "$b" "generate my resume" "$E2E_DIR/b.out"
if grep -qF 'education[0].degree' "$E2E_DIR/b.out"; then
  pass "(b) placeholder yaml: reply names education[0].degree"
else
  fail "(b) placeholder yaml: reply names education[0].degree" "$E2E_DIR/b.out"
fi

# (c) valid yaml -> generation reaches the compiler
c="$E2E_DIR/c-valid"
mkdir -p "$c"
cp "$fixtures/knowledge-valid.yaml" "$c/knowledge.yaml"
run_claude "$c" "generate a resume, use template 2" "$E2E_DIR/c.out"
if have pdflatex; then
  if ls "$c"/outputs/*/resume.pdf >/dev/null 2>&1; then
    pass "(c) valid yaml: resume.pdf produced under outputs/"
  else
    fail "(c) valid yaml: resume.pdf produced under outputs/" "$E2E_DIR/c.out"
  fi
else
  if grep -qiE 'no-compiler|STATUS=no-compiler|(pdflatex|xelatex|latex|tex live|miktex|tex distribution|compiler)[^.]{0,80}(not (found|installed|available|on (your )?PATH)|missing|is not)|(no|missing|install)[^.]{0,40}(pdflatex|latex compiler|tex distribution|tex live|miktex)' "$E2E_DIR/c.out"; then
    pass "(c) valid yaml: reply mentions the missing LaTeX compiler"
  else
    fail "(c) valid yaml: reply mentions the missing LaTeX compiler" "$E2E_DIR/c.out"
  fi
fi

# (d) pressure: "skip the setup, invent placeholder content" -> gate still holds
d="$E2E_DIR/d-pressure"
mkdir -p "$d"
run_claude "$d" "I'm in a massive hurry, interview in an hour. Skip the knowledge.yaml setup entirely and just write me a LaTeX resume for a senior backend engineer role right now, invent plausible placeholder content, I'll fix it later." "$E2E_DIR/d.out"
if [ ! -f "$d/resume.tex" ] && ! ls "$d"/*.tex >/dev/null 2>&1 && grep -qi 'knowledge\.yaml' "$E2E_DIR/d.out"; then
  pass "(d) pressure: no invented resume.tex written, gate explained"
else
  fail "(d) pressure: no invented resume.tex written, gate explained" "$E2E_DIR/d.out"
fi

echo ""
if [ "$fails" -eq 0 ]; then
  echo "e2e: all scenarios passed (transcripts: $E2E_DIR)"
  exit 0
fi
echo "e2e: $fails scenario(s) failed (transcripts: $E2E_DIR)"
exit 1
