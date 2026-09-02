#!/usr/bin/env bash
# lib.sh - shared helpers for the resume-generator test/build scripts.
#
# Source it, never execute it:
#   . "$(dirname "$0")/lib.sh"
#
# Portability contract: bash 3.2 (stock macOS), Git Bash on Windows, and any
# GNU/Linux bash. Only coreutils/grep/sed/awk are required. No helper calls
# `set -e`, and every helper is safe under `set -u`.
#
# Helpers:
#   skill_root                 absolute path of skills/resume-generator
#   list_templates             numeric template dirs that contain template.tex
#   magic_program <tex>        program named by a %!TEX program = ... comment
#   compiler_for <tex>         xelatex | lualatex | pdflatex (default)
#   run_with_timeout <s> <cmd> timeout/gtimeout wrapper with a no-timeout fallback
#   detect_distro              miktex | debian | fedora | texlive | unknown
#   tex_needs_sudo             yes | no  (is TEXMFDIST writable?)
#   log_tail <file> <n>        last n lines of a file, indented, to stderr
#   have <cmd>                 true when <cmd> is on PATH
#   abs_dir <dir>              absolute path of an existing directory
#   leak_strings               the non-comment lines of leak-strings.txt
#   count_lines <file>         portable line count (no leading spaces)

# shellcheck disable=SC2034  # variables below are consumed by the sourcing scripts

if [ -n "${RG_LIB_LOADED:-}" ]; then
  return 0 2>/dev/null || true
fi
RG_LIB_LOADED=1

RG_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Placeholder sentinel regex shared by the gate validator, the lint and build.sh.
RG_SENTINEL_RE='<[A-Z][A-Za-z0-9_]*>'

# Template sample-data strings (one per line, `#` comments allowed).
RG_LEAK_FILE="$RG_LIB_DIR/leak-strings.txt"

have() {
  command -v "$1" >/dev/null 2>&1
}

skill_root() {
  (cd "$RG_LIB_DIR/.." && pwd)
}

abs_dir() {
  (cd "$1" 2>/dev/null && pwd)
}

count_lines() {
  if [ -f "$1" ]; then
    awk 'END { print NR + 0 }' "$1"
  else
    printf '0\n'
  fi
}

# list_templates - numeric dirs under templates/ that contain template.tex,
# one per line, sorted numerically. Nothing is hardcoded: adding templates/7/
# with a template.tex makes it show up everywhere.
list_templates() {
  local root d n
  root="$(skill_root)"
  for d in "$root"/templates/*/; do
    [ -d "$d" ] || continue
    n="$(basename "$d")"
    case "$n" in
      ''|*[!0-9]*) continue ;;
    esac
    [ -f "$d/template.tex" ] || continue
    printf '%s\n' "$n"
  done | sort -n
}

# magic_program <file.tex> - lower-cased program named by a magic comment such as
#   %!TEX program = xelatex
#   % !TeX TS-program = lualatex
# within the first 30 lines. Prints nothing when there is no marker.
magic_program() {
  local f="$1"
  [ -f "$f" ] || return 0
  head -n 30 "$f" 2>/dev/null \
    | tr -d '\r' \
    | LC_ALL=C tr '[:upper:]' '[:lower:]' \
    | sed -nE 's/^[[:space:]]*%[[:space:]]*!tex[[:space:]]+(ts-)?program[[:space:]]*=[[:space:]]*([a-z]+).*/\2/p' \
    | head -n 1
}

# compiler_for <file.tex> - the compiler a .tex file asks for; pdflatex when
# the file carries no marker or names something we do not support.
compiler_for() {
  local p
  p="$(magic_program "$1")"
  case "$p" in
    xelatex|lualatex|pdflatex) printf '%s\n' "$p" ;;
    *) printf 'pdflatex\n' ;;
  esac
}

# run_with_timeout <seconds> <cmd...> - run under GNU timeout (or gtimeout on
# macOS/Homebrew). When neither exists the command runs without a limit.
# The Windows timeout.exe (a "wait" command) is deliberately not accepted.
RG_TIMEOUT_BIN=""
RG_TIMEOUT_PROBED=""
run_with_timeout() {
  local secs="$1"
  shift
  if [ -z "$RG_TIMEOUT_PROBED" ]; then
    RG_TIMEOUT_PROBED=1
    if have timeout && timeout --version 2>/dev/null | grep -qi 'coreutils'; then
      RG_TIMEOUT_BIN=timeout
    elif have gtimeout && gtimeout --version 2>/dev/null | grep -qi 'coreutils'; then
      RG_TIMEOUT_BIN=gtimeout
    fi
  fi
  if [ -n "$RG_TIMEOUT_BIN" ]; then
    "$RG_TIMEOUT_BIN" "$secs" "$@"
  else
    "$@"
  fi
}

# detect_distro - which package manager can install TeX packages here.
#   miktex   `miktex` on PATH (Windows/macOS/Linux MiKTeX)
#   debian   the pdflatex/xelatex binary is owned by a dpkg package
#   fedora   the binary is owned by an rpm package
#   texlive  vanilla TeX Live: `tlmgr` on PATH and not OS-packaged
#   unknown  none of the above (Nix, conda, docker images without tlmgr, ...)
# Order matters: Debian/Fedora ship tlmgr in user-mode only, so tlmgr install
# is broken there and apt/dnf hints are what the user needs.
detect_distro() {
  local bin=""
  if have miktex; then
    printf 'miktex\n'
    return 0
  fi
  bin="$(command -v pdflatex 2>/dev/null || command -v xelatex 2>/dev/null || true)"
  if [ -n "$bin" ]; then
    if have dpkg && dpkg -S "$bin" >/dev/null 2>&1; then
      printf 'debian\n'
      return 0
    fi
    if have rpm && rpm -qf "$bin" >/dev/null 2>&1; then
      printf 'fedora\n'
      return 0
    fi
  fi
  if have tlmgr; then
    printf 'texlive\n'
    return 0
  fi
  printf 'unknown\n'
}

# tex_needs_sudo - yes when TEXMFDIST (where tlmgr installs packages) exists
# and the current user cannot write to it.
tex_needs_sudo() {
  local d=""
  if have kpsewhich; then
    d="$(kpsewhich -var-value TEXMFDIST 2>/dev/null | tr -d '\r' | head -n 1)"
  fi
  if [ -n "$d" ] && [ -d "$d" ] && [ ! -w "$d" ]; then
    printf 'yes\n'
  else
    printf 'no\n'
  fi
}

# log_tail <file> <n> - last <n> lines of <file> (default 20), indented, on stderr.
log_tail() {
  local f="$1" n="${2:-20}"
  if [ -f "$f" ]; then
    tail -n "$n" "$f" 2>/dev/null | sed 's/^/    /' >&2
  else
    printf '    (no log file at %s)\n' "$f" >&2
  fi
}

# leak_strings - print the active lines of leak-strings.txt (no comments/blanks).
leak_strings() {
  [ -f "$RG_LEAK_FILE" ] || return 0
  tr -d '\r' < "$RG_LEAK_FILE" | grep -vE '^[[:space:]]*(#|$)'
}
