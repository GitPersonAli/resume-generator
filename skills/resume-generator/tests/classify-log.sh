#!/usr/bin/env bash
# classify-log.sh - classify the first LaTeX error in a compile log.
#
# The common, mechanical compile failures get a deterministic fix hint so
# generation.md Step 7 can repair them inline; only STATUS=unknown needs a
# diagnosis sub-agent.
#
# Usage: classify-log.sh <file.log>
#
# Stdout (KEY=value):
#   STATUS=classified|unknown|no-error|not-found
#   CLASS=<see table>|unknown|none
#   ERROR=<the first line starting with "! ">
#   LINE=<n>            the "l.<n>" input line TeX printed after the error, when present
#   TOKEN=<text>        the macro / file / font / environment / package the error names
#   HINT=<one-line fix>
#
# CLASS (first match wins):
#   missing-class               ! LaTeX Error: File `x.cls' not found.
#   missing-package             ! LaTeX Error: File `x.sty' not found.
#   missing-file                ! LaTeX Error: File `x' not found.  /  ! I can't find file `x'.
#   font-not-found              fontspec "font-not-found", The font "X" cannot be found, Font \x=X ... not loadable
#   undefined-control-sequence  ! Undefined control sequence.
#   undefined-environment       ! LaTeX Error: Environment x undefined.
#   missing-begin-document      ! LaTeX Error: Missing \begin{document}.
#   missing-dollar              ! Missing $ inserted.
#   extra-brace                 ! Too many }'s.
#   runaway-argument            ! File ended while scanning use of \x. / ! Paragraph ended before \x was complete.
#   unknown-option              ! LaTeX Error: Unknown option `x' for package `y'.
#   package-error               ! Package x Error: ...
#   unknown                     any other "! " line
#
# Exit: 0 classified, 1 unknown, 3 log not found, 4 args, 5 no "! " line in the log

set -u

# shellcheck source-path=SCRIPTDIR
# shellcheck source=lib.sh
. "$(dirname "$0")/lib.sh"

if [ "$#" -ne 1 ]; then
  echo "usage: $0 <file.log>" >&2
  exit 4
fi
log="$1"
if [ ! -f "$log" ]; then
  echo "STATUS=not-found"
  exit 3
fi

clean="$(tr -d '\r' < "$log")"
first="$(printf '%s\n' "$clean" | grep -nE '^! ' | head -n 1)"
if [ -z "$first" ]; then
  echo "STATUS=no-error"
  echo "CLASS=none"
  echo "SUMMARY=no LaTeX error line in $(basename "$log"); the failure is outside LaTeX (timeout, disk, missing binary)"
  exit 5
fi
n="${first%%:*}"
err="${first#*:}"
ctx="$(printf '%s\n' "$clean" | sed -n "$((n + 1)),$((n + 20))p")"

line="$(printf '%s\n' "$ctx" | grep -oE '^l\.[0-9]+' | head -n 1 | cut -c3-)"
lline="$(printf '%s\n' "$ctx" | grep -E '^l\.[0-9]+' | head -n 1)"

# between_ticks <text>: the part between the first ` and the following '
between_ticks() {
  local t="$1"
  t="${t#*\`}"
  t="${t%%\'*}"
  printf '%s\n' "$t"
}
first_macro() {
  printf '%s\n' "$1" | grep -oE '\\[A-Za-z@]+' | head -n 1
}
last_macro() {
  printf '%s\n' "$1" | grep -oE '\\[A-Za-z@]+' | tail -n 1
}

class=unknown
token=""
hint=""
where="${line:+ near line $line}"

case "$err" in
  *"File \`"*".cls' not found"*)
    class=missing-class
    token="$(between_ticks "$err")"
    hint="Class file $token is not in the output dir: re-run generation Step 4 (copy the template's .cls/.sty/fonts next to resume.tex)"
    ;;
  *"File \`"*".sty' not found"*)
    class=missing-package
    token="$(between_ticks "$err")"
    hint="Package ${token%.sty} is not installed: run preflight.sh <N> install (MiKTeX/TeX Live) or copy the .sty next to resume.tex if it is a template asset"
    ;;
  *"File \`"*"' not found"*|*"I can't find file \`"*)
    class=missing-file
    token="$(between_ticks "$err")"
    hint="File $token is referenced$where but absent from the output dir (photo, structure.tex, fonts): copy it or remove the reference"
    ;;
  *"fontspec error"*"font-not-found"*|*"cannot be found"*|*"not loadable"*)
    class=font-not-found
    token="$(printf '%s\n%s\n' "$err" "$ctx" | grep -oE '"[^"]+" cannot be found' | head -n 1 | sed 's/" cannot be found$//; s/^"//')"
    if [ -z "$token" ]; then
      token="$(printf '%s\n' "$err" | sed -nE 's/.*=([^ ]+) at .*not loadable.*/\1/p' | head -n 1)"
    fi
    hint="Font ${token:-?} not found$where: the template's font dir was not copied or its case is wrong (Fonts/ vs fonts/), or the file was compiled with pdflatex instead of xelatex"
    ;;
  *"Undefined control sequence"*)
    class=undefined-control-sequence
    token="$(last_macro "$lline")"
    hint="Macro ${token:-?} is not defined for this template$where: check the macro name and arity in templates/<N>/NOTES.md, or a typo"
    ;;
  *"Environment "*" undefined"*)
    class=undefined-environment
    token="$(printf '%s\n' "$err" | sed -nE 's/.*Environment ([^ ]+) undefined.*/\1/p')"
    hint="Environment ${token:-?} is unknown to this class$where: use the environment named in templates/<N>/NOTES.md"
    ;;
  *"Missing \\begin{document}"*)
    class=missing-begin-document
    hint="Body text or a stray character appears before \\begin{document}$where: move it after, or escape it"
    ;;
  *"Missing \$ inserted"*)
    class=missing-dollar
    hint="An unescaped _ ^ or math character in text mode$where: escape it (\\_ \\textasciicircum{} \\$)"
    ;;
  *"Too many }'s"*)
    class=extra-brace
    hint="A stray }$where: count the brace arguments of that macro call against templates/<N>/NOTES.md"
    ;;
  *"File ended while scanning use of"*|*"Paragraph ended before"*)
    class=runaway-argument
    token="$(first_macro "$err")"
    hint="An argument of ${token:-?} is never closed: a missing } or an unescaped { in the text it wraps (the runaway text is printed above the error)"
    ;;
  *"Unknown option"*)
    class=unknown-option
    token="$(between_ticks "$err")"
    hint="Option $token is not accepted$where: drop it or check the package documentation"
    ;;
  *"Package "*" Error"*)
    class=package-error
    token="$(printf '%s\n' "$err" | sed -nE 's/.*Package ([^ ]+) Error.*/\1/p')"
    hint="Package ${token:-?} rejected the input$where: read the message and fix the named argument"
    ;;
esac

echo "ERROR=$err"
[ -n "$line" ]  && echo "LINE=$line"
[ -n "$token" ] && echo "TOKEN=$token"
if [ "$class" = unknown ]; then
  echo "CLASS=unknown"
  echo "HINT=not a known mechanical failure; dispatch the diagnosis sub-agent with the paths to resume.log and resume.tex"
  echo "STATUS=unknown"
  exit 1
fi
echo "CLASS=$class"
echo "HINT=$hint"
echo "STATUS=classified"
exit 0
