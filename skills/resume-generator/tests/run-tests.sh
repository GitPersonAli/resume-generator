#!/usr/bin/env bash
# run-tests.sh - self-contained test runner for the scripts in this directory.
#
# No bats, no python needed (python-dependent cases are skipped when python3
# or PyYAML is missing, and the grep fallback is tested instead). Every test
# prints PASS/FAIL/SKIP; the exit code is non-zero when anything fails.
#
# Usage: bash tests/run-tests.sh

set -u

# shellcheck source-path=SCRIPTDIR
# shellcheck source=lib.sh
. "$(dirname "$0")/lib.sh"

T="$RG_LIB_DIR"
FX="$T/fixtures"
ROOT="$(skill_root)"

npass=0
nfail=0
nskip=0
out=""
rc=0

ok()    { npass=$((npass + 1)); echo "PASS: $1"; }
bad()   { nfail=$((nfail + 1)); echo "FAIL: $1${2:+ - $2}"; }
skipt() { nskip=$((nskip + 1)); echo "SKIP: $1${2:+ - $2}"; }

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

# run <cmd...>: capture stdout in $out and the exit status in $rc (stderr to a file).
run() {
  out="$("$@" 2>"$tmp/stderr.txt")"
  rc=$?
}
has()     { printf '%s\n' "$out" | grep -qF -- "$1"; }
hasre()   { printf '%s\n' "$out" | grep -qE -- "$1"; }
oneline() { printf '%s' "$out" | tr '\n' '|' | cut -c1-400; }

# expect <name> <expected-rc> [substring ...]: assert $rc and that every
# substring occurs in $out.
expect() {
  local name="$1" want="$2" missing="" s
  shift 2
  if [ "$rc" -ne "$want" ]; then
    bad "$name" "expected rc=$want, got rc=$rc; out: $(oneline)"
    return
  fi
  for s in ${1+"$@"}; do
    has "$s" || missing="$missing [$s]"
  done
  if [ -n "$missing" ]; then
    bad "$name" "missing in output:$missing; out: $(oneline)"
  else
    ok "$name"
  fi
}

echo "== syntax =="
for s in "$T"/*.sh; do
  if bash -n "$s" 2>"$tmp/stderr.txt"; then
    ok "bash -n $(basename "$s")"
  else
    bad "bash -n $(basename "$s")" "$(tr '\n' ' ' < "$tmp/stderr.txt")"
  fi
done

echo "== portability guard =="
# Bash-4-only constructs (associative arrays, the two array readers, the
# pipe-both-streams operator, case-conversion expansions, namerefs) must not
# appear in any script. The pattern is assembled from pieces so this file
# does not contain the forbidden spellings itself.
pipe_amp="$(printf '|%s' '&')"
guard="$(printf 'decl%s -A|map%s|read%s|\\%s|\\$\\{[A-Za-z_][A-Za-z0-9_]*(,,|\\^\\^)|loc%s -n' are file array "$pipe_amp" al)"
for s in "$T"/*.sh; do
  hits="$(grep -nE -- "$guard" "$s" || true)"
  if [ -z "$hits" ]; then
    ok "portable bash: $(basename "$s")"
  else
    bad "portable bash: $(basename "$s")" "$(printf '%s' "$hits" | tr '\n' '|' | cut -c1-200)"
  fi
done

echo "== lib.sh =="
tpls="$(list_templates)"
if [ -n "$tpls" ]; then
  sorted_ok=1
  prev=0
  for n in $tpls; do
    [ "$n" -gt "$prev" ] || sorted_ok=0
    prev="$n"
    [ -f "$ROOT/templates/$n/template.tex" ] || sorted_ok=0
  done
  if [ "$sorted_ok" -eq 1 ]; then
    ok "list_templates: $(printf '%s' "$tpls" | tr '\n' ' ')(numeric, each has template.tex)"
  else
    bad "list_templates" "not sorted numerically or a dir lacks template.tex: $(printf '%s' "$tpls" | tr '\n' ' ')"
  fi
else
  bad "list_templates" "returned nothing"
fi

c="$(compiler_for "$FX/magic-xelatex.tex")"
[ "$c" = "xelatex" ] && ok "compiler_for magic-xelatex.tex -> xelatex" || bad "compiler_for magic-xelatex.tex" "got '$c'"
c="$(compiler_for "$FX/no-magic.tex")"
[ "$c" = "pdflatex" ] && ok "compiler_for no-magic.tex -> pdflatex (default)" || bad "compiler_for no-magic.tex" "got '$c'"
c="$(compiler_for "$FX/magic-lualatex-spaced.tex")"
[ "$c" = "lualatex" ] && ok "compiler_for spaced/cased TS-program marker -> lualatex" || bad "compiler_for magic-lualatex-spaced.tex" "got '$c'"
c="$(compiler_for "$FX/good.tex")"
[ "$c" = "pdflatex" ] && ok "compiler_for good.tex -> pdflatex" || bad "compiler_for good.tex" "got '$c'"
for n in $tpls; do
  c="$(compiler_for "$ROOT/templates/$n/template.tex")"
  case "$n" in
    3|5) want=xelatex ;;
    *)   want=pdflatex ;;
  esac
  [ "$c" = "$want" ] && ok "compiler_for templates/$n -> $want" || bad "compiler_for templates/$n" "expected $want, got '$c'"
done

d="$(detect_distro)"
case "$d" in
  miktex|debian|fedora|texlive|unknown) ok "detect_distro -> $d" ;;
  *) bad "detect_distro" "unexpected value '$d'" ;;
esac
s="$(tex_needs_sudo)"
case "$s" in
  yes|no) ok "tex_needs_sudo -> $s" ;;
  *) bad "tex_needs_sudo" "unexpected value '$s'" ;;
esac
if run_with_timeout 5 true; then ok "run_with_timeout runs the command"; else bad "run_with_timeout true" "rc=$?"; fi
if [ -n "$RG_TIMEOUT_BIN" ]; then
  run_with_timeout 1 sh -c 'sleep 3' >/dev/null 2>&1
  r=$?
  [ "$r" -eq 124 ] && ok "run_with_timeout kills after the limit (rc=124)" || bad "run_with_timeout kill" "rc=$r"
else
  skipt "run_with_timeout kill" "no GNU timeout/gtimeout here"
fi
if [ -s "$T/leak-strings.txt" ] && leak_strings | grep -qF 'John Smith' && leak_strings | grep -qF 'Lorem ipsum'; then
  ok "leak-strings.txt present with sample names and lorem markers ($(leak_strings | grep -c '') entries)"
else
  bad "leak-strings.txt" "missing or lacks 'John Smith' / 'Lorem ipsum'"
fi

echo "== validate-knowledge.sh =="
V="$T/validate-knowledge.sh"
have_yaml=0
if have python3 && python3 -c 'import yaml' >/dev/null 2>&1; then
  have_yaml=1
fi
if [ "$have_yaml" -eq 1 ]; then
  run bash "$V" "$FX/knowledge-valid.yaml"
  expect "validate: valid fixture passes the gate" 0 "STATUS=ok" "PARSER=python"
  run bash "$V" "$FX/knowledge-projects-only.yaml"
  expect "validate: projects-only fixture passes (no experience needed)" 0 "STATUS=ok"
  run bash "$V" "$FX/knowledge-placeholders.yaml"
  expect "validate: placeholder fixture fails on education[0].degree" 1 "STATUS=missing" \
    "PLACEHOLDER=education[0].degree=<DEGREE_NAME_E_G_MSc_in_X>" \
    "OPTIONAL_PLACEHOLDER=experience[0].achievements[0]=<QUANTIFIED_ACHIEVEMENT_1>"
  if [ "$rc" -eq 1 ] && ! hasre '^PLACEHOLDER=experience\[0\]\.achievements\[0\]='; then
    ok "validate: optional sentinel is not reported as a required PLACEHOLDER"
  else
    bad "validate: optional sentinel is not reported as a required PLACEHOLDER" "$(oneline)"
  fi
  run bash "$V" "$FX/knowledge-invalid.yaml"
  expect "validate: broken yaml -> exit 2 with PARSE_ERROR" 2 "STATUS=invalid-yaml" "PARSE_ERROR="
  if hasre '^PARSE_ERROR=[0-9]+:[0-9]+: '; then
    ok "validate: PARSE_ERROR carries line:col"
  else
    bad "validate: PARSE_ERROR carries line:col" "$(oneline)"
  fi
  run bash "$V" "$FX/knowledge-missing-email.yaml"
  expect "validate: missing email -> exit 1 with MISSING=email" 1 "STATUS=missing" "MISSING=email"
  run bash "$V" "$ROOT/assets/knowledge.template.yaml"
  expect "validate: blank template fails with required placeholders" 1 "PLACEHOLDER=name=<YOUR_NAME>" "PLACEHOLDER=email=<YOUR_EMAIL>"
  : > "$tmp/empty.yaml"
  run bash "$V" "$tmp/empty.yaml"
  expect "validate: empty file -> gate failure listing name/email/education" 1 "MISSING=name" "MISSING=email" "MISSING=education"
  printf -- '- just\n- a list\n' > "$tmp/list.yaml"
  run bash "$V" "$tmp/list.yaml"
  expect "validate: non-mapping document -> invalid-yaml" 2 "STATUS=invalid-yaml"
else
  skipt "validate: python-parser cases" "python3 with PyYAML not available"
fi
run bash "$V" "$tmp/does-not-exist.yaml"
expect "validate: missing file -> exit 3" 3 "STATUS=not-found"
run bash "$V"
expect "validate: no args -> exit 4" 4
run env RESUME_VALIDATE_FORCE_GREP=1 bash "$V" "$FX/knowledge-placeholders.yaml"
expect "validate: grep fallback -> exit 6 with PLACEHOLDER_LINE" 6 "STATUS=no-parser" "PARSER=grep" "PLACEHOLDER_LINE=10:" "<DEGREE_NAME_E_G_MSc_in_X>"

echo "== lint-tex.sh =="
L="$T/lint-tex.sh"
run bash "$L" "$FX/good.tex"
expect "lint: good.tex is clean" 0 "STATUS=ok" "ERRORS=0"
run bash "$L" "$FX/bad.tex"
expect "lint: bad.tex fails" 1 "STATUS=errors"
for want in \
  "template placeholder left in the document: <PLACEHOLDER_X>" \
  'template sample data leaked (verify against knowledge.yaml): "John Smith"' \
  "unescaped & outside a table environment" \
  "unescaped _ in text mode" \
  "unescaped # in text mode" \
  "unbalanced braces: 6 opening { vs 5 closing }" \
  "hyperref is not loaded" \
  "does not match the innermost open environment" \
  "odd number of unescaped \$" \
  "usepackage{lipsum}" \
  "no \"%!TEX program" ; do
  if has "$want"; then ok "lint: bad.tex reports '$want'"; else bad "lint: bad.tex reports '$want'" "$(oneline)"; fi
done
hasre '^LINT_ERROR=12: unescaped &' && ok "lint: & error carries the right line number" || bad "lint: & line number" "$(oneline)"
run bash "$L"
expect "lint: no args -> exit 4" 4
run bash "$L" "$tmp/nope.tex"
expect "lint: missing file -> exit 4" 4

for n in $tpls; do
  run bash "$L" "$ROOT/templates/$n/template.tex"
  nonleak="$(printf '%s\n' "$out" | grep '^LINT_ERROR=' | grep -v 'template sample data leaked' || true)"
  badwarn="$(printf '%s\n' "$out" | grep '^LINT_WARN=' | grep -vE 'magic comment|lipsum' || true)"
  if [ -z "$nonleak" ] && [ -z "$badwarn" ]; then
    ok "lint: templates/$n has no false positives (only sample-data leaks)"
  else
    bad "lint: templates/$n has no false positives" "$(printf '%s\n%s' "$nonleak" "$badwarn" | tr '\n' '|' | cut -c1-300)"
  fi
done
for n in $tpls; do
  st="$ROOT/templates/$n/structure.tex"
  [ -f "$st" ] || continue
  run bash "$L" "$st"
  if has "ERRORS=0"; then
    ok "lint: templates/$n/structure.tex (macro definitions with #1) is clean"
  else
    bad "lint: templates/$n/structure.tex is clean" "$(oneline)"
  fi
done

cat > "$tmp/edge.tex" <<'EOF'
%!TEX program = pdflatex
\documentclass{article}
\usepackage{graphicx,hyperref}
\newenvironment{myenv}
{\begin{itemize}}
{\end{itemize}}
\def\mymacro#1#2{#1 and #2}
\begin{document}
\begin{tabular}{ll} a & b \\ c & d \end{tabular}
\begin{verbatim}
raw & stuff _ # { unbalanced
\end{verbatim}
\includegraphics[width=2cm]{my_photo.png} \input{some_file} \verb|a_b & c|
Display math $$x_1 + y_2$$ and \[ z_3 \] and \( w_4 \) done.
\begin{align} a &= b \\ c &= d \end{align}
\href{https://example.org/a_b?x=1&y=2}{Example \& Co} \url{https://x.org/a_b}
\end{document}
EOF
run bash "$L" "$tmp/edge.tex"
expect "lint: edge cases (verbatim, display math, tabular/align &, path args, \\def) are clean" 0 "ERRORS=0" "WARNINGS=0"

printf '%%!TEX program = pdflatex\n\\documentclass{article}\n\\begin{document}\nA \\begin{center} b \\end{enumerate} c\n\\end{document}\n' > "$tmp/envmis.tex"
run bash "$L" "$tmp/envmis.tex"
expect "lint: environment mismatch is an error" 1 "does not match"
printf '%%!TEX program = pdflatex\n\\documentclass{article}\n\\begin{document}\nA }\n\\end{document}\n' > "$tmp/neg.tex"
run bash "$L" "$tmp/neg.tex"
expect "lint: stray closing brace is an error" 1 "unbalanced braces: 1 opening { vs 2 closing }"

echo "== check-version-sync.sh =="
run bash "$T/check-version-sync.sh"
expect "check-version-sync: manifests agree" 0 "versions in sync"

echo "== preflight.sh =="
P="$T/preflight.sh"
run bash "$P" 99
expect "preflight: bogus template number -> exit 4" 4 "STATUS=invalid"
run bash "$P" abc
expect "preflight: non-numeric template -> exit 4" 4 "STATUS=invalid"
run bash "$P"
expect "preflight: no args -> exit 4" 4 "STATUS=invalid"
run bash "$P" 2 bogus-mode
expect "preflight: bad mode -> exit 4" 4 "STATUS=invalid"
if have pdflatex; then
  run bash "$P" 2
  case "$rc" in
    0) expect "preflight: template 2 on this TeX (ok)" 0 "STATUS=ok" "COMPILER=pdflatex" ;;
    1) expect "preflight: template 2 on this TeX (missing items, auto-install possible)" 1 "STATUS=missing" "NEEDS_UPDATE=" "SUDO=" ;;
    3) expect "preflight: template 2 on this TeX (missing items, manual install)" 3 "STATUS=no-distro" "NEEDS_UPDATE=" "SUDO=" ;;
    *) bad "preflight: template 2 on this TeX" "unexpected rc=$rc: $(oneline)" ;;
  esac
  skipt "preflight: no-compiler path" "pdflatex is present on this machine"
else
  run bash "$P" 2
  expect "preflight: no pdflatex -> exit 2" 2 "STATUS=no-compiler" "COMPILER=pdflatex" "INSTALL_CMD=#"
fi
if have xelatex; then
  skipt "preflight: template 5 no-compiler path" "xelatex is present on this machine"
else
  run bash "$P" 5 install
  expect "preflight: no xelatex (install mode) -> exit 2" 2 "STATUS=no-compiler" "COMPILER=xelatex"
fi

echo "== build.sh =="
B="$T/build.sh"
bdir="$tmp/build"
mkdir -p "$bdir"
cp "$FX/good.tex" "$bdir/resume.tex"
run bash "$B"
expect "build: no args -> exit 4" 4
run bash "$B" "$tmp/no-such-dir"
expect "build: missing dir -> exit 4" 4
run bash "$B" "$tmp"
expect "build: dir without resume.tex -> exit 4" 4
run bash "$B" "$bdir" --compiler tex
expect "build: unsupported --compiler -> exit 4" 4
run bash "$B" "$bdir" --template 999
expect "build: unknown --template -> exit 4" 4
run bash "$B" "$bdir" --file ../evil.tex
expect "build: --file with a path -> exit 4" 4
run bash "$B" "$bdir" --file notes.txt
expect "build: --file without .tex -> exit 4" 4
run bash "$B" "$bdir" --file cover-letter.tex
expect "build: --file naming a missing file -> exit 4" 4
if have pdflatex; then
  skipt "build: no-compiler path" "pdflatex is present on this machine"
else
  run bash "$B" "$bdir"
  expect "build: no pdflatex -> exit 2" 2 "STATUS=no-compiler" "COMPILER=pdflatex"
fi
if have lualatex; then
  skipt "build: --compiler precedence" "lualatex is present on this machine"
else
  run bash "$B" "$bdir" --compiler lualatex --template 2
  expect "build: --compiler flag wins over magic comment and --template" 2 "COMPILER=lualatex"
fi
if have xelatex; then
  skipt "build: magic-comment / --template precedence" "xelatex is present on this machine"
else
  cp "$FX/magic-xelatex.tex" "$bdir/cover-letter.tex"
  run bash "$B" "$bdir" --file cover-letter.tex --template 2
  expect "build: --file picks the named .tex and its magic comment wins over --template" 2 "COMPILER=xelatex"
  cp "$FX/no-magic.tex" "$bdir/resume.tex"
  run bash "$B" "$bdir" --template 3
  expect "build: --template N supplies the compiler when the .tex has no marker" 2 "COMPILER=xelatex"
fi

echo "== compile-all.sh =="
if have pdflatex || have xelatex || have lualatex; then
  skipt "compile-all: no-compiler path" "a LaTeX compiler is present (run compile-all.sh directly to exercise it)"
else
  run bash "$T/compile-all.sh"
  expect "compile-all: no compiler -> exit 2" 2
fi

echo ""
echo "Tests: $npass passed, $nfail failed, $nskip skipped"
[ "$nfail" -eq 0 ]
