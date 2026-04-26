#!/usr/bin/env bash
# compile-all.sh - sanity check that every bundled template compiles cleanly.
#
# Run after the initial template copy and after any template edit.
# Each template/<N>/template.tex is compiled in an isolated temp directory
# (so the source folder stays free of build artifacts).
#
# Exit code: 0 if all six templates produce a PDF, 1 if any fails.
#
# Requires: pdflatex and xelatex on PATH.

set -u

SKILL_DIR="$(cd "$(dirname "$0")/.." && pwd)"
TEMPLATES_DIR="$SKILL_DIR/templates"

# template number -> compiler
declare -A COMPILER=(
  [1]=pdflatex
  [2]=pdflatex
  [3]=xelatex
  [4]=pdflatex
  [5]=xelatex
  [6]=pdflatex
)

failed=()
passed=()

for n in 1 2 3 4 5 6; do
  src="$TEMPLATES_DIR/$n"
  if [[ ! -d "$src" ]]; then
    echo "MISSING: $src"
    failed+=("$n (missing)")
    continue
  fi

  tmp="$(mktemp -d)"
  trap 'rm -rf "$tmp"' EXIT

  cp -r "$src"/. "$tmp/"

  cmd="${COMPILER[$n]}"
  echo "=== Template $n ($cmd) ==="

  # MiKTeX flags:
  #   --enable-installer: auto-install missing packages without prompting
  # Per-pass timeout prevents indefinite hangs if a package install fails silently.
  flags="-interaction=nonstopmode -halt-on-error --enable-installer"
  if (cd "$tmp" && timeout 120 "$cmd" $flags template.tex >/dev/null 2>&1 \
                && timeout 120 "$cmd" $flags template.tex >/dev/null 2>&1); then
    if [[ -f "$tmp/template.pdf" ]]; then
      echo "  PASS"
      passed+=("$n")
    else
      echo "  FAIL: no PDF produced"
      failed+=("$n (no pdf)")
    fi
  else
    echo "  FAIL: $cmd error - showing tail of log"
    tail -n 20 "$tmp/template.log" 2>/dev/null | sed 's/^/    /'
    failed+=("$n ($cmd error)")
  fi

  rm -rf "$tmp"
  trap - EXIT
done

echo ""
echo "=== Summary ==="
echo "Passed: ${#passed[@]}/6 (${passed[*]:-none})"
if [[ ${#failed[@]} -gt 0 ]]; then
  echo "Failed: ${failed[*]}"
  exit 1
fi
echo "All templates compile cleanly."
exit 0
