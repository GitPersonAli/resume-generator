#!/usr/bin/env bash
# compile-all.sh - sanity check that every bundled template compiles cleanly.
#
# Run after any template edit. Every templates/<N>/template.tex (discovered
# dynamically, see lib.sh list_templates) is compiled twice in its own
# isolated temp directory with the compiler its %!TEX magic comment asks for
# (default pdflatex), so the source folders stay free of build artefacts.
#
# Exit codes:
#   0 = every template produced a PDF
#   1 = at least one template failed (log tail is printed per failure)
#   2 = no LaTeX compiler needed by the templates is on PATH at all
#   4 = no templates found under templates/
#
# MiKTeX: --enable-installer is passed so missing packages auto-install
# during the compile. It is a MiKTeX-only flag, so it is never passed to
# TeX Live binaries.

set -u

# shellcheck source-path=SCRIPTDIR
# shellcheck source=lib.sh
. "$(dirname "$0")/lib.sh"

root="$(skill_root)"
templates="$(list_templates)"

if [ -z "$templates" ]; then
  echo "No templates found under $root/templates (need templates/<N>/template.tex)." >&2
  exit 4
fi

# Abort early, once, when none of the required compilers exists.
needed=""
for n in $templates; do
  needed="$needed $(compiler_for "$root/templates/$n/template.tex")"
done
needed_unique="$(printf '%s\n' $needed | sort -u | tr '\n' ' ')"
found_any=0
for c in $needed_unique; do
  if have "$c"; then
    found_any=1
  fi
done
if [ "$found_any" -eq 0 ]; then
  echo "No LaTeX compiler found on PATH (templates need: ${needed_unique% })." >&2
  echo "Install MiKTeX (https://miktex.org) or TeX Live (https://tug.org/texlive), then retry." >&2
  exit 2
fi

extra_flags=""
if [ "$(detect_distro)" = "miktex" ]; then
  extra_flags="--enable-installer"
fi

tmp_root="$(mktemp -d)"
trap 'rm -rf "$tmp_root"' EXIT

passed=""
failed=""
npass=0
nfail=0
total=0

for n in $templates; do
  total=$((total + 1))
  src="$root/templates/$n"
  cmd="$(compiler_for "$src/template.tex")"
  echo "=== Template $n ($cmd) ==="

  if ! have "$cmd"; then
    echo "  FAIL: $cmd not on PATH"
    failed="$failed $n($cmd missing)"
    nfail=$((nfail + 1))
    continue
  fi

  tmp="$tmp_root/$n"
  mkdir -p "$tmp"
  cp -R "$src"/. "$tmp"/

  # shellcheck disable=SC2086  # $extra_flags is intentionally word-split (empty or one flag)
  if (cd "$tmp" \
      && run_with_timeout 120 "$cmd" -interaction=nonstopmode -halt-on-error $extra_flags template.tex >/dev/null 2>&1 \
      && run_with_timeout 120 "$cmd" -interaction=nonstopmode -halt-on-error $extra_flags template.tex >/dev/null 2>&1); then
    if [ -f "$tmp/template.pdf" ]; then
      echo "  PASS"
      passed="$passed $n"
      npass=$((npass + 1))
    else
      echo "  FAIL: no PDF produced"
      failed="$failed $n(no pdf)"
      nfail=$((nfail + 1))
    fi
  else
    echo "  FAIL: $cmd error - showing tail of log"
    log_tail "$tmp/template.log" 20
    failed="$failed $n($cmd error)"
    nfail=$((nfail + 1))
  fi

  rm -rf "$tmp"
done

echo ""
echo "=== Summary ==="
passed="${passed# }"
failed="${failed# }"
echo "Passed: $npass/$total (${passed:-none})"
if [ "$nfail" -gt 0 ]; then
  echo "Failed: $failed"
  exit 1
fi
echo "All templates compile cleanly."
exit 0
