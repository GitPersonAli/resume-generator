#!/usr/bin/env bash
# env-probe.sh - one-second, template-agnostic environment probe.
#
# Run at entry (SKILL.md Step 1) so a missing TeX compiler is surfaced before
# any question is asked. preflight.sh <N> still does the per-template smoke
# compile later; this script never compiles anything.
#
# Usage: env-probe.sh            (no arguments)
#
# Stdout (KEY=value):
#   STATUS=ok|no-compiler        ok when pdflatex or xelatex is on PATH
#   PDFLATEX=<path or empty>
#   XELATEX=<path or empty>
#   LUALATEX=<path or empty>
#   LATEXMK=<path or empty>      build.sh uses it when present
#   PDFTOTEXT=<path or empty>    leak / ATS text check available when set
#   PDFINFO=<path or empty>
#   PDFTOPPM=<path or empty>     page-1 PNG render available when set
#   PYTHON3=<path or empty>
#   PYYAML=yes|no                yes: validate-knowledge.sh uses the python parser; no: it exits 6
#   DISTRO=miktex|debian|fedora|texlive|unknown
#   INSTALL_CMD=<hint>           only when STATUS=no-compiler (one or more lines)
#   SUMMARY=<one line>
#
# Exit: 0 ok, 2 no compiler, 4 arguments given
#
# Deliberately uses only bash builtins plus `python3 -c` (when python3 exists)
# so it behaves with an empty PATH; the directory of this file is resolved
# without `dirname` for the same reason.

set -u

case "$0" in
  */*) here="${0%/*}" ;;
  *)   here="." ;;
esac
# shellcheck source=lib.sh
. "$here/lib.sh"

if [ "$#" -ne 0 ]; then
  echo "usage: $0    (no arguments)" >&2
  exit 4
fi

path_of() {
  command -v "$1" 2>/dev/null || true
}

pdflatex_p="$(path_of pdflatex)"
xelatex_p="$(path_of xelatex)"
lualatex_p="$(path_of lualatex)"
latexmk_p="$(path_of latexmk)"
pdftotext_p="$(path_of pdftotext)"
pdfinfo_p="$(path_of pdfinfo)"
pdftoppm_p="$(path_of pdftoppm)"
python3_p="$(path_of python3)"

pyyaml=no
if [ -n "$python3_p" ] && "$python3_p" -c 'import yaml' >/dev/null 2>&1; then
  pyyaml=yes
fi

distro="$(detect_distro)"

printf 'PDFLATEX=%s\n' "$pdflatex_p"
printf 'XELATEX=%s\n' "$xelatex_p"
printf 'LUALATEX=%s\n' "$lualatex_p"
printf 'LATEXMK=%s\n' "$latexmk_p"
printf 'PDFTOTEXT=%s\n' "$pdftotext_p"
printf 'PDFINFO=%s\n' "$pdfinfo_p"
printf 'PDFTOPPM=%s\n' "$pdftoppm_p"
printf 'PYTHON3=%s\n' "$python3_p"
printf 'PYYAML=%s\n' "$pyyaml"
printf 'DISTRO=%s\n' "$distro"

if [ -z "$pdflatex_p" ] && [ -z "$xelatex_p" ]; then
  echo "STATUS=no-compiler"
  echo "INSTALL_CMD=# install MiKTeX (https://miktex.org) or TeX Live (https://tug.org/texlive), then re-invoke"
  echo "INSTALL_CMD=# Debian/Ubuntu: sudo apt install texlive-latex-extra texlive-xetex texlive-fonts-extra latexmk"
  echo "INSTALL_CMD=# Fedora: sudo dnf install texlive-scheme-medium texlive-xetex latexmk"
  echo "INSTALL_CMD=# macOS: brew install --cask mactex-no-gui"
  echo "SUMMARY=no pdflatex or xelatex on PATH; install TeX or continue source-only"
  exit 2
fi

echo "STATUS=ok"
missing=""
[ -n "$pdftotext_p" ] || missing="$missing pdftotext"
[ -n "$pdftoppm_p" ]  || missing="$missing pdftoppm"
[ "$pyyaml" = yes ]   || missing="$missing PyYAML"
if [ -n "$missing" ]; then
  echo "SUMMARY=compiler present; optional tools missing:${missing} (QA text/PNG checks or the scripted gate degrade)"
else
  echo "SUMMARY=compiler, poppler and PyYAML all present"
fi
exit 0
