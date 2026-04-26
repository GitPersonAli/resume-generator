#!/usr/bin/env bash
# preflight.sh - LaTeX environment check for resume-generator skill.
#
# Detects TeX distribution, verifies the required compiler is present,
# smoke-compiles the bundled template to surface missing packages/fonts,
# and reports machine-parseable findings on stdout.
#
# Usage:
#   preflight.sh <template_number>           # check only
#   preflight.sh <template_number> install   # check and (after caller consent) install missing items
#
# Exit codes:
#   0 = environment is ready (chosen template smoke-compiles cleanly)
#   1 = missing items detected (see stdout for list)
#   2 = required compiler not on PATH
#   3 = unknown TeX distribution (neither MiKTeX nor TeX Live found)
#   4 = invalid arguments / template not found
#   5 = install attempted but smoke-compile still fails afterwards
#
# Stdout format (machine-parseable):
#   STATUS=<ok|missing|no-compiler|no-distro|invalid|install-failed>
#   DISTRO=<miktex|texlive|unknown>
#   COMPILER=<pdflatex|xelatex>
#   COMPILER_PATH=<path or empty>
#   MISSING_PKG=<package-name>            (zero or more lines)
#   MISSING_FONT=<font-spec>              (zero or more lines)
#   OTHER_ERROR=<message>                 (zero or more lines)
#   INSTALL_CMD=<shell command>           (zero or more lines, in suggested run order)
#
# Stderr is reserved for human-readable progress lines.

set -u

# ---------- args ----------
template="${1:-}"
mode="${2:-check}"

if [[ -z "$template" || ! "$template" =~ ^[1-6]$ ]]; then
  echo "STATUS=invalid"
  echo "OTHER_ERROR=template number must be 1..6 (got '${template}')"
  exit 4
fi

skill_dir="$(cd "$(dirname "$0")/.." && pwd)"
template_dir="$skill_dir/templates/$template"

if [[ ! -d "$template_dir" || ! -f "$template_dir/template.tex" ]]; then
  echo "STATUS=invalid"
  echo "OTHER_ERROR=template directory not found: $template_dir"
  exit 4
fi

# Compiler choice mirrors compile-all.sh
case "$template" in
  3|5) compiler="xelatex" ;;
  *)   compiler="pdflatex" ;;
esac

echo "preflight: template=$template compiler=$compiler" >&2

# ---------- compiler presence ----------
compiler_path="$(command -v "$compiler" 2>/dev/null || true)"
if [[ -z "$compiler_path" ]]; then
  echo "STATUS=no-compiler"
  echo "DISTRO=unknown"
  echo "COMPILER=$compiler"
  echo "COMPILER_PATH="
  echo "OTHER_ERROR=$compiler not found on PATH"
  echo "INSTALL_CMD=# Install a TeX distribution: MiKTeX (https://miktex.org) or TeX Live (https://tug.org/texlive)"
  exit 2
fi

# ---------- distribution detection ----------
distro="unknown"
if command -v miktex >/dev/null 2>&1; then
  distro="miktex"
elif command -v tlmgr >/dev/null 2>&1; then
  distro="texlive"
fi

echo "preflight: distro=$distro" >&2

if [[ "$distro" == "unknown" ]]; then
  echo "STATUS=no-distro"
  echo "DISTRO=unknown"
  echo "COMPILER=$compiler"
  echo "COMPILER_PATH=$compiler_path"
  echo "OTHER_ERROR=$compiler is on PATH but neither 'miktex' nor 'tlmgr' is — cannot auto-install missing packages"
  exit 3
fi

# ---------- smoke compile in temp dir ----------
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
cp -r "$template_dir"/. "$tmp/"

# Run compiler. For MiKTeX we use --enable-installer so missing packages
# get auto-installed during this very pass — covers the common case where
# the user just needs a few packages; the mode==install branch below adds
# explicit install commands for anything still missing afterwards.
extra_flags=""
if [[ "$distro" == "miktex" ]]; then
  extra_flags="--enable-installer"
fi

run_compile() {
  (cd "$tmp" && timeout 180 "$compiler" -interaction=nonstopmode -halt-on-error $extra_flags template.tex >/dev/null 2>&1)
  return $?
}

run_compile
exit1=$?

# Second pass for cross-references (only if first succeeded)
if [[ $exit1 -eq 0 ]]; then
  run_compile
  exit2=$?
else
  exit2=$exit1
fi

if [[ -f "$tmp/template.pdf" && $exit2 -eq 0 ]]; then
  echo "STATUS=ok"
  echo "DISTRO=$distro"
  echo "COMPILER=$compiler"
  echo "COMPILER_PATH=$compiler_path"
  exit 0
fi

# ---------- parse log for missing items ----------
log="$tmp/template.log"
missing_pkgs=()
missing_fonts=()
other_errors=()

if [[ -f "$log" ]]; then
  # missing .sty / .cls / .def files
  while IFS= read -r line; do
    pkg="$(echo "$line" | sed -nE "s/.*File [\`']([^']+)\.(sty|cls|def|tex)' not found.*/\1/p")"
    [[ -n "$pkg" ]] && missing_pkgs+=("$pkg")
  done < <(grep -E "File [\`'][^']+\.(sty|cls|def|tex)' not found" "$log" 2>/dev/null)

  # missing fonts (pdftex / fontspec / luaotfload variants)
  while IFS= read -r line; do
    f="$(echo "$line" | sed -nE 's/.*Font ([A-Za-z0-9_-]+) at [0-9]+ not found.*/\1/p')"
    [[ -n "$f" ]] && missing_fonts+=("$f")
  done < <(grep -E "Font [A-Za-z0-9_-]+ at [0-9]+ not found" "$log" 2>/dev/null)

  while IFS= read -r line; do
    f="$(echo "$line" | sed -nE 's/.*The font "([^"]+)" cannot be found.*/\1/p')"
    [[ -n "$f" ]] && missing_fonts+=("$f")
  done < <(grep -E 'The font "[^"]+" cannot be found' "$log" 2>/dev/null)

  # font expansion / scalable font error (T6 case)
  if grep -qE "auto expansion is only possible with scalable fonts" "$log" 2>/dev/null; then
    other_errors+=("microtype font expansion requires scalable fonts (try adding \\usepackage{lmodern} before microtype)")
  fi

  # LaTeX format mismatch (T2 case)
  if grep -qE "You have requested release '[0-9-]+' of LaTeX, but only release" "$log" 2>/dev/null; then
    msg="$(grep -E "You have requested release" "$log" | head -1 | sed -E 's/^[[:space:]]+//')"
    other_errors+=("$msg — update your TeX distribution (e.g. 'miktex update' or 'tlmgr update --self --all')")
  fi

  # generic fatal-error fallback if no specific patterns matched
  if [[ ${#missing_pkgs[@]} -eq 0 && ${#missing_fonts[@]} -eq 0 && ${#other_errors[@]} -eq 0 ]]; then
    fatal="$(grep -E "^! " "$log" | head -3 | tr '\n' '|')"
    [[ -n "$fatal" ]] && other_errors+=("$fatal")
  fi
fi

# Deduplicate
mapfile -t missing_pkgs < <(printf '%s\n' "${missing_pkgs[@]}" | awk 'NF && !seen[$0]++')
mapfile -t missing_fonts < <(printf '%s\n' "${missing_fonts[@]}" | awk 'NF && !seen[$0]++')

# ---------- emit findings ----------
echo "STATUS=missing"
echo "DISTRO=$distro"
echo "COMPILER=$compiler"
echo "COMPILER_PATH=$compiler_path"

for p in "${missing_pkgs[@]}"; do echo "MISSING_PKG=$p"; done
for f in "${missing_fonts[@]}"; do echo "MISSING_FONT=$f"; done
for e in "${other_errors[@]}"; do echo "OTHER_ERROR=$e"; done

# ---------- install commands ----------
# Distro-specific install hints. We emit one INSTALL_CMD per missing package
# and a generic font-pkg hint per missing font (font name often differs from
# package name, so we ask the user to consult their distro's repo).
case "$distro" in
  miktex)
    update_cmd="miktex packages update --quiet && miktex update"
    pkg_cmd_prefix="miktex packages install"
    ;;
  texlive)
    update_cmd="tlmgr update --self --all"
    pkg_cmd_prefix="tlmgr install"
    ;;
esac

# Always offer the update command first when there are issues
echo "INSTALL_CMD=$update_cmd"
for p in "${missing_pkgs[@]}"; do
  echo "INSTALL_CMD=$pkg_cmd_prefix $p"
done
for f in "${missing_fonts[@]}"; do
  # Font name -> package name is non-trivial; emit a search hint
  echo "INSTALL_CMD=# missing font '$f' — search your distro's repo for the providing package, then: $pkg_cmd_prefix <package>"
done

# ---------- install mode ----------
if [[ "$mode" == "install" ]]; then
  echo "preflight: install mode active — running install commands" >&2

  # Run update first
  echo "preflight: $update_cmd" >&2
  eval "$update_cmd" >&2 || echo "preflight: update command exited non-zero (continuing)" >&2

  # Run each package install
  for p in "${missing_pkgs[@]}"; do
    echo "preflight: $pkg_cmd_prefix $p" >&2
    eval "$pkg_cmd_prefix $p" >&2 || echo "preflight: failed to install $p (continuing)" >&2
  done

  # Re-smoke-compile
  rm -rf "$tmp"
  trap - EXIT
  tmp="$(mktemp -d)"
  trap 'rm -rf "$tmp"' EXIT
  cp -r "$template_dir"/. "$tmp/"

  run_compile && run_compile
  if [[ -f "$tmp/template.pdf" ]]; then
    echo "POST_INSTALL_STATUS=ok" >&2
    # Override prior stdout — emit clean OK summary
    echo "STATUS=ok"
    echo "DISTRO=$distro"
    echo "COMPILER=$compiler"
    echo "COMPILER_PATH=$compiler_path"
    exit 0
  else
    echo "POST_INSTALL_STATUS=still-missing" >&2
    echo "STATUS=install-failed"
    exit 5
  fi
fi

exit 1
