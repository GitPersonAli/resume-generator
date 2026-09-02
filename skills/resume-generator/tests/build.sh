#!/usr/bin/env bash
# build.sh - compile a generated .tex file in an output directory and run
# post-compile QA (page count, box warnings, text extraction, leak checks,
# page-1 PNG render).
#
# Usage:
#   build.sh <output-dir> [--compiler pdflatex|xelatex|lualatex] [--template N]
#                         [--file <name.tex>] [--no-render]
#
#   --file      which .tex in <output-dir> to compile (default resume.tex).
#               The PDF/log/PNG names derive from it: cover-letter.tex ->
#               cover-letter.pdf, cover-letter.log, cover-letter-p1.png.
#   --no-render skip the pdftoppm page-1 render.
#
# Compiler precedence:
#   --compiler flag  >  %!TEX program magic comment in the .tex  >
#   --template N (that template.tex's magic comment)  >  pdflatex
#
# latexmk is used when on PATH (-pdf / -xelatex / -lualatex), otherwise the
# compiler runs twice. Both paths use -interaction=nonstopmode -halt-on-error
# under a 180 s timeout (when GNU timeout/gtimeout is available).
#
# Stdout (KEY=value):
#   STATUS=ok|compile-failed|no-compiler
#   COMPILER=<pdflatex|xelatex|lualatex>
#   PDF=<absolute path>
#   PAGES=<n>                        from the log ("Output written on ... (N pages") or pdfinfo
#   OVERFULL=<n>  UNDERFULL=<n>      count of "Overfull \hbox" / "Underfull \hbox" log lines
#   TEXT_EXTRACT=ok|empty|unavailable   pdftotext present and text non-empty?
#   PLACEHOLDER_LEAK=<n>             sentinel matches in the extracted text   (only when TEXT_EXTRACT=ok)
#   UNRESOLVED_REFS=<n>              count of "??" in the extracted text       (only when TEXT_EXTRACT=ok)
#   LEAK=<string>                    one line per leak-strings.txt hit in the text
#   PNG=<absolute path>              page-1 render at 60 dpi (pdftoppm present and not --no-render)
#
# Exit codes:
#   0 = compiled (QA lines are informational)
#   1 = compile failed (last 40 log lines on stderr)
#   2 = compiler not on PATH
#   4 = bad arguments
#
# On success the aux files (.aux .out .toc .fls .fdb_latexmk .synctex.gz .bbl
# .blg .bcf .run.xml .nav .snm .xdv) are removed; the .log is kept.

set -u

# shellcheck source-path=SCRIPTDIR
# shellcheck source=lib.sh
. "$(dirname "$0")/lib.sh"

usage() {
  echo "usage: $0 <output-dir> [--compiler pdflatex|xelatex|lualatex] [--template N] [--file <name.tex>] [--no-render]" >&2
}

die_args() {
  echo "build: $1" >&2
  usage
  exit 4
}

dir=""
compiler_flag=""
template_flag=""
texfile="resume.tex"
render=1

while [ "$#" -gt 0 ]; do
  case "$1" in
    --compiler)
      [ "$#" -ge 2 ] || die_args "--compiler needs a value"
      compiler_flag="$2"
      shift 2
      ;;
    --compiler=*)
      compiler_flag="${1#*=}"
      shift
      ;;
    --template)
      [ "$#" -ge 2 ] || die_args "--template needs a value"
      template_flag="$2"
      shift 2
      ;;
    --template=*)
      template_flag="${1#*=}"
      shift
      ;;
    --file)
      [ "$#" -ge 2 ] || die_args "--file needs a value"
      texfile="$2"
      shift 2
      ;;
    --file=*)
      texfile="${1#*=}"
      shift
      ;;
    --no-render)
      render=0
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    -*)
      die_args "unknown option: $1"
      ;;
    *)
      [ -z "$dir" ] || die_args "unexpected extra argument: $1"
      dir="$1"
      shift
      ;;
  esac
done

[ -n "$dir" ] || die_args "missing <output-dir>"
[ -d "$dir" ] || die_args "not a directory: $dir"
dir="$(abs_dir "$dir")"

case "$texfile" in
  ''|*/*|*\\*) die_args "--file must be a bare file name inside <output-dir> (got '$texfile')" ;;
  *.tex) ;;
  *) die_args "--file must end with .tex (got '$texfile')" ;;
esac
[ -f "$dir/$texfile" ] || die_args "no $texfile in $dir"
base="${texfile%.tex}"

case "$compiler_flag" in
  ''|pdflatex|xelatex|lualatex) ;;
  *) die_args "unsupported --compiler '$compiler_flag' (pdflatex|xelatex|lualatex)" ;;
esac

if [ -n "$template_flag" ]; then
  known=0
  for t in $(list_templates); do
    [ "$t" = "$template_flag" ] && known=1
  done
  [ "$known" -eq 1 ] || die_args "unknown --template '$template_flag' (have: $(list_templates | tr '\n' ' '))"
fi

# ---- resolve compiler ------------------------------------------------------------
compiler=""
if [ -n "$compiler_flag" ]; then
  compiler="$compiler_flag"
else
  magic="$(magic_program "$dir/$texfile")"
  case "$magic" in
    pdflatex|xelatex|lualatex) compiler="$magic" ;;
  esac
  if [ -z "$compiler" ] && [ -n "$template_flag" ]; then
    compiler="$(compiler_for "$(skill_root)/templates/$template_flag/template.tex")"
  fi
  [ -n "$compiler" ] || compiler="pdflatex"
fi

if ! have "$compiler"; then
  echo "STATUS=no-compiler"
  echo "COMPILER=$compiler"
  echo "build: $compiler not found on PATH - install MiKTeX (https://miktex.org) or TeX Live (https://tug.org/texlive)" >&2
  exit 2
fi

extra_flags=""
if [ "$(detect_distro)" = "miktex" ]; then
  extra_flags="--enable-installer"
fi

pdf="$dir/$base.pdf"
log="$dir/$base.log"
rm -f "$pdf"   # a stale PDF must never masquerade as a fresh build

echo "build: compiling $texfile in $dir with $compiler" >&2

compiled=0
if have latexmk; then
  case "$compiler" in
    xelatex) engine_flag="-xelatex" ;;
    lualatex) engine_flag="-lualatex" ;;
    *) engine_flag="-pdf" ;;
  esac
  latexopt=""
  [ -n "$extra_flags" ] && latexopt="-latexoption=$extra_flags"
  # shellcheck disable=SC2086  # $latexopt is intentionally word-split (empty or one flag)
  if (cd "$dir" && run_with_timeout 180 latexmk "$engine_flag" -interaction=nonstopmode -halt-on-error $latexopt "$texfile" >/dev/null 2>&1); then
    compiled=1
  fi
else
  # shellcheck disable=SC2086  # $extra_flags is intentionally word-split (empty or one flag)
  if (cd "$dir" \
      && run_with_timeout 180 "$compiler" -interaction=nonstopmode -halt-on-error $extra_flags "$texfile" >/dev/null 2>&1 \
      && run_with_timeout 180 "$compiler" -interaction=nonstopmode -halt-on-error $extra_flags "$texfile" >/dev/null 2>&1); then
    compiled=1
  fi
fi

if [ "$compiled" -ne 1 ] || [ ! -f "$pdf" ]; then
  echo "STATUS=compile-failed"
  echo "COMPILER=$compiler"
  echo "build: $compiler failed - last 40 lines of $log:" >&2
  log_tail "$log" 40
  exit 1
fi

# ---- post-compile QA -------------------------------------------------------------
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

pages="$(grep -aE 'Output written on .*\([0-9]+ pages?' "$log" 2>/dev/null | tail -n 1 | sed -E 's/.*\(([0-9]+) pages?.*/\1/')"
if [ -z "$pages" ] && have pdfinfo; then
  pages="$(pdfinfo "$pdf" 2>/dev/null | sed -nE 's/^Pages:[[:space:]]+([0-9]+).*/\1/p' | head -n 1)"
fi
[ -n "$pages" ] || pages=0

overfull="$(grep -ac 'Overfull \\hbox' "$log" 2>/dev/null || true)"
underfull="$(grep -ac 'Underfull \\hbox' "$log" 2>/dev/null || true)"
[ -n "$overfull" ] || overfull=0
[ -n "$underfull" ] || underfull=0

echo "STATUS=ok"
echo "COMPILER=$compiler"
echo "PDF=$pdf"
echo "PAGES=$pages"
echo "OVERFULL=$overfull"
echo "UNDERFULL=$underfull"

text="$tmp/text.txt"
text_status="unavailable"
if have pdftotext; then
  if pdftotext -layout "$pdf" "$text" >/dev/null 2>&1 && [ -s "$text" ] && grep -q '[^[:space:]]' "$text"; then
    text_status="ok"
  else
    text_status="empty"
  fi
fi
echo "TEXT_EXTRACT=$text_status"

if [ "$text_status" = "ok" ]; then
  placeholder_leak="$(grep -aoE "$RG_SENTINEL_RE" "$text" | wc -l | tr -d ' ')"
  unresolved="$(grep -ao '??' "$text" | wc -l | tr -d ' ')"
  echo "PLACEHOLDER_LEAK=${placeholder_leak:-0}"
  echo "UNRESOLVED_REFS=${unresolved:-0}"
  leak_strings > "$tmp/leaks.txt"
  while IFS= read -r s; do
    [ -n "$s" ] || continue
    if grep -aqiF -- "$s" "$text"; then
      echo "LEAK=$s"
    fi
  done < "$tmp/leaks.txt"
fi

if [ "$render" -eq 1 ] && have pdftoppm; then
  png="$dir/$base-p1.png"
  rm -f "$png"
  if pdftoppm -png -r 60 -f 1 -l 1 -singlefile "$pdf" "$dir/$base-p1" >/dev/null 2>&1 && [ -f "$png" ]; then
    echo "PNG=$png"
  else
    echo "build: pdftoppm render failed (no PNG)" >&2
  fi
elif [ "$render" -eq 1 ]; then
  echo "build: pdftoppm not on PATH - skipping page-1 render" >&2
fi

for ext in aux out toc fls fdb_latexmk synctex.gz bbl blg bcf run.xml nav snm xdv; do
  rm -f "$dir/$base.$ext"
done

exit 0
