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

have_yaml=0
if have python3 && python3 -c 'import yaml' >/dev/null 2>&1; then
  have_yaml=1
fi

echo "== env-probe.sh =="
E="$T/env-probe.sh"
mkdir -p "$tmp/emptybin"
run env PATH="$tmp/emptybin" "$(command -v bash)" "$E"
expect "env-probe: empty PATH -> exit 2, no-compiler, PYYAML=no" 2 "STATUS=no-compiler" "PDFLATEX=" "XELATEX=" "PYYAML=no" "DISTRO=unknown" "INSTALL_CMD=#"
if hasre '^PDFLATEX=$' && hasre '^LATEXMK=$'; then ok "env-probe: empty PATH leaves tool paths empty"; else bad "env-probe: empty PATH tool paths" "$(oneline)"; fi
run bash "$E"
if have pdflatex || have xelatex; then
  expect "env-probe: this machine -> STATUS=ok" 0 "STATUS=ok" "DISTRO=" "PYYAML="
else
  expect "env-probe: this machine -> no-compiler" 2 "STATUS=no-compiler"
fi
if [ "$have_yaml" -eq 1 ]; then has "PYYAML=yes" && ok "env-probe: PYYAML=yes matches the validator's parser" || bad "env-probe: PYYAML" "$(oneline)"; fi
run bash "$E" extra
expect "env-probe: any argument -> exit 4" 4

echo "== validate-knowledge.sh =="
V="$T/validate-knowledge.sh"
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

echo "== classify-log.sh =="
C="$T/classify-log.sh"
run bash "$C" "$FX/log-undefined-cs.log"
expect "classify: undefined control sequence" 0 "STATUS=classified" "CLASS=undefined-control-sequence" "LINE=42" "TOKEN=\\sectionn" "HINT="
run bash "$C" "$FX/log-missing-sty.log"
expect "classify: missing .sty -> missing-package" 0 "CLASS=missing-package" "TOKEN=ebgaramond.sty" "LINE=5"
run bash "$C" "$FX/log-missing-cls.log"
expect "classify: missing .cls -> missing-class" 0 "CLASS=missing-class" "TOKEN=resume.cls" "Step 4"
run bash "$C" "$FX/log-font.log"
expect "classify: fontspec font-not-found" 0 "CLASS=font-not-found" "TOKEN=Alegreya" "LINE=30"
run bash "$C" "$FX/log-runaway.log"
expect "classify: runaway argument" 0 "CLASS=runaway-argument" "TOKEN=\\@resumeSubheading"
run bash "$C" "$FX/log-clean.log"
expect "classify: clean log -> exit 5 no-error" 5 "STATUS=no-error" "CLASS=none"
run bash "$C" "$FX/log-unknown.log"
expect "classify: unknown error -> exit 1" 1 "STATUS=unknown" "CLASS=unknown" "ERROR=! Something bizarre" "LINE=7"
printf '(./resume.tex\n! Missing $ inserted.\n<inserted text> \n                $\nl.19 Grew ARR 40%% to $\n                       2M.\n' > "$tmp/dollar.log"
run bash "$C" "$tmp/dollar.log"
expect "classify: missing dollar" 0 "CLASS=missing-dollar" "LINE=19"
printf '(./resume.tex\n! Too many }'"'"'s.\nl.23 \\item{Built it}}\n' > "$tmp/brace.log"
run bash "$C" "$tmp/brace.log"
expect "classify: extra brace" 0 "CLASS=extra-brace" "LINE=23"
printf '(./resume.tex\n! LaTeX Error: Environment rSection undefined.\n\nl.31 \\begin{rSection}\n' > "$tmp/env.log"
run bash "$C" "$tmp/env.log"
expect "classify: undefined environment" 0 "CLASS=undefined-environment" "TOKEN=rSection" "LINE=31"
printf '(./resume.tex\n! Package geometry Error: \\paperwidth (0.0pt) too short.\n\nl.9 \\usepackage[margin=0in]{geometry}\n' > "$tmp/pkg.log"
run bash "$C" "$tmp/pkg.log"
expect "classify: package error" 0 "CLASS=package-error" "TOKEN=geometry" "LINE=9"
run bash "$C" "$tmp/nope.log"
expect "classify: missing log -> exit 3" 3 "STATUS=not-found"
run bash "$C"
expect "classify: no args -> exit 4" 4

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

echo "== qa-gate.sh =="
Q="$T/qa-gate.sh"
qdir="$tmp/qa"
mkdir -p "$qdir"
cp "$FX/good.tex" "$qdir/resume.tex"
mk_out() {  # mk_out <file> <pages> <overfull> <placeholder> <refs> <text> [leak...]
  local f="$1" pages="$2" over="$3" ph="$4" refs="$5" text="$6"
  shift 6
  {
    echo "STATUS=ok"; echo "COMPILER=pdflatex"; echo "PDF=$qdir/resume.pdf"
    echo "PAGES=$pages"; echo "OVERFULL=$over"; echo "UNDERFULL=0"; echo "TEXT_EXTRACT=$text"
    if [ "$text" = ok ]; then echo "PLACEHOLDER_LEAK=$ph"; echo "UNRESOLVED_REFS=$refs"; fi
    for l in ${1+"$@"}; do echo "LEAK=$l"; done
    echo "PNG=$qdir/resume-p1.png"
  } > "$f"
}
mk_out "$tmp/q-pass.out" 1 2 0 0 ok
run bash "$Q" "$qdir" --from "$tmp/q-pass.out" --template 2
expect "qa-gate: clean build passes" 0 "STATUS=pass" "BUDGET=1" "PAGES=1" "PNG=$qdir/resume-p1.png"
mk_out "$tmp/q-2p.out" 2 0 0 0 ok
run bash "$Q" "$qdir" --from "$tmp/q-2p.out" --template 2
expect "qa-gate: 2 pages on template 2 fails" 1 "STATUS=fail" "FAIL=pages:2/1"
run bash "$Q" "$qdir" --from "$tmp/q-2p.out" --template 2 --experience-years 12
expect "qa-gate: template 2 with >8 years gets a 2-page budget" 0 "STATUS=pass" "BUDGET=2"
run bash "$Q" "$qdir" --from "$tmp/q-2p.out" --template 2 --experience-years 8
expect "qa-gate: exactly 8 years keeps 1 page" 1 "BUDGET=1"
run bash "$Q" "$qdir" --from "$tmp/q-2p.out" --template 3
expect "qa-gate: template 3 default budget is 2" 0 "BUDGET=2"
run bash "$Q" "$qdir" --from "$tmp/q-2p.out" --template 3 --page-limit 1
expect "qa-gate: --page-limit overrides the template default" 1 "BUDGET=1" "FAIL=pages:2/1"
run bash "$Q" "$qdir" --from "$tmp/q-2p.out" --template 3 --file cover-letter.tex
expect "qa-gate: a non-resume --file (cover letter) is budgeted at 1 page" 1 "BUDGET=1"
mk_out "$tmp/q-leak.out" 1 0 0 0 ok "John Smith" "MIT"
run bash "$Q" "$qdir" --from "$tmp/q-leak.out" --template 2
expect "qa-gate: LEAK lines fail" 1 "FAIL=leak:John Smith" "FAIL=leak:MIT"
run bash "$Q" "$qdir" --from "$tmp/q-leak.out" --template 2 --allow "MIT" --allow "John Smith"
expect "qa-gate: --allow whitelists genuine strings" 0 "STATUS=pass"
mk_out "$tmp/q-ph.out" 1 0 3 0 ok
run bash "$Q" "$qdir" --from "$tmp/q-ph.out" --template 2
expect "qa-gate: placeholder leak fails" 1 "FAIL=placeholder-leak:3"
mk_out "$tmp/q-refs.out" 1 0 0 2 ok
run bash "$Q" "$qdir" --from "$tmp/q-refs.out" --template 2
expect "qa-gate: unresolved refs fail" 1 "FAIL=unresolved-refs:2"
mk_out "$tmp/q-over.out" 1 9 0 0 ok
run bash "$Q" "$qdir" --from "$tmp/q-over.out" --template 2
expect "qa-gate: overfull > 5 is a warning, not a failure" 0 "STATUS=pass" "WARN=overfull:9"
mk_out "$tmp/q-notext.out" 1 0 0 0 unavailable
run bash "$Q" "$qdir" --from "$tmp/q-notext.out" --template 2
expect "qa-gate: no pdftotext -> warning, leak checks unmeasured" 0 "STATUS=pass" "WARN=text-extract:unavailable"
mk_out "$tmp/q-empty.out" 1 0 0 0 empty
run bash "$Q" "$qdir" --from "$tmp/q-empty.out" --template 2
expect "qa-gate: empty text layer -> warning" 0 "WARN=text-extract:empty"
printf 'STATUS=compile-failed\nCOMPILER=pdflatex\n' > "$tmp/q-cf.out"
run bash "$Q" "$qdir" --from "$tmp/q-cf.out" --template 2
expect "qa-gate: compile-failed passes through as exit 5" 5 "STATUS=compile-failed"
printf 'STATUS=no-compiler\nCOMPILER=xelatex\n' > "$tmp/q-nc.out"
run bash "$Q" "$qdir" --from "$tmp/q-nc.out" --template 3
expect "qa-gate: no-compiler passes through as exit 2" 2 "STATUS=no-compiler"
run bash "$Q" "$qdir" --from "$tmp/q-pass.out"
expect "qa-gate: --template is required" 4
run bash "$Q" "$qdir" --from "$tmp/q-pass.out" --template 99
expect "qa-gate: unknown template -> exit 4" 4
run bash "$Q" "$qdir" --from "$tmp/missing.out" --template 2
expect "qa-gate: missing --from file -> exit 3" 3
run bash "$Q" "$tmp/no-such" --template 2
expect "qa-gate: missing dir -> exit 3" 3
run bash "$Q"
expect "qa-gate: no args -> exit 4" 4
if have pdflatex; then
  skipt "qa-gate: live no-compiler path" "pdflatex is present"
else
  run bash "$Q" "$qdir" --template 2
  expect "qa-gate: live run without TeX -> exit 2" 2 "STATUS=no-compiler"
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
