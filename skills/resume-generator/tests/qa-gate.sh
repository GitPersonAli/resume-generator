#!/usr/bin/env bash
# qa-gate.sh - scripted post-compile QA gate (generation.md Step 7).
#
# Runs build.sh in <output-dir> (or reads a saved build.sh output with --from,
# for tests and re-checks), echoes every build key, then applies the page
# budget and leak rules deterministically so the docs never do the arithmetic.
#
# Usage:
#   qa-gate.sh <output-dir> --template N [--page-limit L] [--experience-years Y]
#              [--file name.tex] [--compiler X] [--no-render] [--allow <string>]...
#   qa-gate.sh <output-dir> --from <build.out> --template N [...]
#
# BUDGET (pages allowed), first rule that applies:
#   --page-limit L                     the yaml's page_limit
#   --file other than resume.tex       1 (a cover letter)
#   template default                   1:1  2:1  3:2  4:2  5:2  6:1, and template 2
#                                      becomes 2 when --experience-years is above 8
# FAIL= lines (any FAIL -> STATUS=fail, exit 1):
#   pages:<n>/<budget>                 PAGES above BUDGET
#   placeholder-leak:<n>               PLACEHOLDER_LEAK above 0
#   leak:<string>                      each LEAK= line not covered by --allow
#   unresolved-refs:<n>                UNRESOLVED_REFS above 0
# WARN= lines (never fail):
#   overfull:<n>                       OVERFULL above 5
#   text-extract:empty                 the PDF has no text layer (ATS sees nothing)
#   text-extract:unavailable           no pdftotext: leak and refs checks unmeasured
#   png:none                           no page-1 render to look at
#   pages:unknown                      build.sh could not count pages
#
# Stdout: the build.sh lines first (its STATUS is re-emitted as BUILD_STATUS),
#   then BUDGET=, ALLOWED=/FAIL=/WARN= lines, PNG= (when present),
#   STATUS=pass|fail|no-compiler|compile-failed, SUMMARY=
# Exit: 0 pass, 1 fail, 2 no compiler, 3 <output-dir> or --from file missing,
#       4 arguments, 5 compile failed (run classify-log.sh on the .log)

set -u

# shellcheck source-path=SCRIPTDIR
# shellcheck source=lib.sh
. "$(dirname "$0")/lib.sh"

usage() {
  echo "usage: $0 <output-dir> --template N [--page-limit L] [--experience-years Y] [--file name.tex] [--compiler X] [--no-render] [--allow <string>]... [--from <build.out>]" >&2
}
die_args() {
  echo "qa-gate: $1" >&2
  usage
  exit 4
}
is_int() {
  case "$1" in
    ''|*[!0-9]*) return 1 ;;
    *) return 0 ;;
  esac
}

dir=""
template=""
page_limit=""
years=""
texfile="resume.tex"
from=""
allow="
"
pass_args=""

while [ "$#" -gt 0 ]; do
  case "$1" in
    --template)         [ "$#" -ge 2 ] || die_args "--template needs a value"; template="$2"; shift 2 ;;
    --template=*)       template="${1#*=}"; shift ;;
    --page-limit)       [ "$#" -ge 2 ] || die_args "--page-limit needs a value"; page_limit="$2"; shift 2 ;;
    --page-limit=*)     page_limit="${1#*=}"; shift ;;
    --experience-years) [ "$#" -ge 2 ] || die_args "--experience-years needs a value"; years="$2"; shift 2 ;;
    --experience-years=*) years="${1#*=}"; shift ;;
    --file)             [ "$#" -ge 2 ] || die_args "--file needs a value"; texfile="$2"; pass_args="$pass_args --file $2"; shift 2 ;;
    --file=*)           texfile="${1#*=}"; pass_args="$pass_args --file ${1#*=}"; shift ;;
    --compiler)         [ "$#" -ge 2 ] || die_args "--compiler needs a value"; pass_args="$pass_args --compiler $2"; shift 2 ;;
    --compiler=*)       pass_args="$pass_args --compiler ${1#*=}"; shift ;;
    --no-render)        pass_args="$pass_args --no-render"; shift ;;
    --allow)            [ "$#" -ge 2 ] || die_args "--allow needs a value"; allow="$allow$2
"; shift 2 ;;
    --allow=*)          allow="$allow${1#*=}
"; shift ;;
    --from)             [ "$#" -ge 2 ] || die_args "--from needs a value"; from="$2"; shift 2 ;;
    --from=*)           from="${1#*=}"; shift ;;
    -h|--help)          usage; exit 0 ;;
    -*)                 die_args "unknown option: $1" ;;
    *)                  [ -z "$dir" ] || die_args "unexpected extra argument: $1"; dir="$1"; shift ;;
  esac
done

[ -n "$dir" ] || die_args "missing <output-dir>"
[ -n "$template" ] || die_args "--template N is required"
is_int "$template" || die_args "--template must be a number"
if ! list_templates | grep -qx "$template"; then
  die_args "unknown template $template (no templates/$template/template.tex)"
fi
[ -z "$page_limit" ] || is_int "$page_limit" || die_args "--page-limit must be a number"
[ -z "$years" ] || is_int "$years" || die_args "--experience-years must be a number"
case "$texfile" in
  ''|*/*|*\\*) die_args "--file must be a bare file name" ;;
esac

if [ ! -d "$dir" ]; then
  echo "qa-gate: not a directory: $dir" >&2
  echo "STATUS=not-found"
  exit 3
fi
dir="$(abs_dir "$dir")"

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
bout="$tmp/build.out"

if [ -n "$from" ]; then
  if [ ! -f "$from" ]; then
    echo "qa-gate: --from file not found: $from" >&2
    echo "STATUS=not-found"
    exit 3
  fi
  tr -d '\r' < "$from" > "$bout"
else
  # shellcheck disable=SC2086  # pass_args is a deliberately word-split option list
  bash "$RG_LIB_DIR/build.sh" "$dir" --template "$template" $pass_args > "$bout"
fi

get() {
  sed -n "s/^$1=//p" "$bout" | head -n 1
}

# Echo the build lines, renaming STATUS so the gate's own STATUS is the last word.
sed 's/^STATUS=/BUILD_STATUS=/' "$bout"

bstatus="$(get STATUS)"
case "$bstatus" in
  ok) ;;
  no-compiler)
    echo "STATUS=no-compiler"
    echo "SUMMARY=no compiler for this template; source-only or install TeX (preflight.sh)"
    exit 2
    ;;
  compile-failed)
    echo "STATUS=compile-failed"
    echo "SUMMARY=compile failed; run classify-log.sh $dir/${texfile%.tex}.log"
    exit 5
    ;;
  *)
    echo "STATUS=compile-failed"
    echo "SUMMARY=build.sh returned no usable STATUS (got '$bstatus')"
    exit 5
    ;;
esac

# Budget
if [ -n "$page_limit" ]; then
  budget="$page_limit"
elif [ "$texfile" != "resume.tex" ]; then
  budget=1
else
  case "$template" in
    3|4|5) budget=2 ;;
    *)     budget=1 ;;
  esac
  if [ "$template" = 2 ] && [ -n "$years" ] && [ "$years" -gt 8 ]; then
    budget=2
  fi
fi
echo "BUDGET=$budget"

fails=0
warns=0
fail() { fails=$((fails + 1)); echo "FAIL=$1"; }
warn() { warns=$((warns + 1)); echo "WARN=$1"; }

pages="$(get PAGES)"
if is_int "$pages"; then
  [ "$pages" -le "$budget" ] || fail "pages:$pages/$budget"
else
  warn "pages:unknown"
fi

text="$(get TEXT_EXTRACT)"
case "$text" in
  ok)
    ph="$(get PLACEHOLDER_LEAK)"
    if is_int "$ph" && [ "$ph" -gt 0 ]; then fail "placeholder-leak:$ph"; fi
    refs="$(get UNRESOLVED_REFS)"
    if is_int "$refs" && [ "$refs" -gt 0 ]; then fail "unresolved-refs:$refs"; fi
    sed -n 's/^LEAK=//p' "$bout" | while IFS= read -r leak; do
      [ -n "$leak" ] || continue
      if printf '%s' "$allow" | grep -qxF -- "$leak"; then
        echo "ALLOWED=$leak"
      else
        echo "FAIL=leak:$leak"
      fi
    done > "$tmp/leaks.out"
    cat "$tmp/leaks.out"
    nleak="$(grep -c '^FAIL=' "$tmp/leaks.out" || true)"
    fails=$((fails + nleak))
    ;;
  empty)       warn "text-extract:empty" ;;
  *)           warn "text-extract:unavailable" ;;
esac

over="$(get OVERFULL)"
if is_int "$over" && [ "$over" -gt 5 ]; then warn "overfull:$over"; fi

png="$(get PNG)"
if [ -n "$png" ]; then
  echo "PNG=$png"
else
  warn "png:none"
fi

if [ "$fails" -gt 0 ]; then
  echo "STATUS=fail"
  echo "SUMMARY=$fails check(s) failed, $warns warning(s); budget $budget page(s)"
  exit 1
fi
echo "STATUS=pass"
echo "SUMMARY=all checks passed, $warns warning(s); budget $budget page(s), rendered $pages"
exit 0
