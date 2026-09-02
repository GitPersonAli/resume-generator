#!/usr/bin/env bash
# preflight.sh - LaTeX environment check for the resume-generator skill.
#
# Verifies the compiler the chosen template needs is present, smoke-compiles
# the bundled template.tex twice in a temp dir, and - only if that fails -
# parses the log for missing packages/fonts, detects which package manager
# can fix it, and prints install commands. Optionally runs them.
#
# Usage:
#   preflight.sh <template_number>           # check only
#   preflight.sh <template_number> install   # check, then run the INSTALL_CMD lines
#                                            # (only on MiKTeX / vanilla TeX Live)
#
# Flow:
#   1. args              -> exit 4 / STATUS=invalid   (template must exist under templates/)
#   2. compiler on PATH? -> exit 2 / STATUS=no-compiler (INSTALL_CMD hints to get MiKTeX or TeX Live)
#   3. smoke compile     -> exit 0 / STATUS=ok when a PDF is produced. No package
#                           manager is needed on this path (Nix, conda, docker
#                           and Debian TeX all work without tlmgr/miktex).
#   4. on failure        -> parse the log, detect_distro, emit findings + hints
#   5. install mode      -> run the hints (miktex/texlive only), re-smoke-compile
#
# Exit codes:
#   0 = ok: the template smoke-compiles
#   1 = missing items detected and auto-install is possible (DISTRO=miktex|texlive)
#   2 = required compiler not on PATH
#   3 = missing items but no auto-install: DISTRO=debian|fedora|unknown needs a
#       manual / sudo OS-package install (all MISSING_* and INSTALL_CMD hints are
#       still printed). Also used in install mode when sudo is needed but stdin
#       is not a TTY (OTHER_ERROR explains; STATUS stays `missing`).
#   4 = invalid arguments / template not found
#   5 = install ran but the smoke compile still fails
#
# Stdout (KEY=value, machine-parseable; stderr carries human progress):
#   STATUS=<ok|missing|no-compiler|no-distro|invalid|install-failed>
#   DISTRO=<miktex|debian|fedora|texlive|unknown>
#   COMPILER=<pdflatex|xelatex|lualatex>
#   COMPILER_PATH=<path or empty>
#   MISSING_PKG=<package-name>            (zero or more)
#   MISSING_FONT=<font-spec>              (zero or more)
#   OTHER_ERROR=<message>                 (zero or more)
#   NEEDS_UPDATE=yes|no                   yes only when the log shows a LaTeX release mismatch
#   SUDO=yes|no                           texlive only: TEXMFDIST not writable by this user
#   INSTALL_CMD=<shell command or # hint> (zero or more, in suggested run order)
#
# INSTALL_CMD by distro:
#   miktex   miktex packages install <pkg>            (+ `miktex packages update --quiet && miktex update`
#                                                        first, only when NEEDS_UPDATE=yes)
#   texlive  [sudo ]tlmgr install <pkg>                (+ `[sudo ]tlmgr update --self --all` first,
#                                                        only when NEEDS_UPDATE=yes)
#   debian   sudo apt-get install texlive-latex-extra texlive-fonts-extra
#            texlive-fonts-recommended texlive-xetex  (+ an apt-file hint per missing file)
#   fedora   sudo dnf install 'tex(<pkg>.sty)'         per missing file
#   unknown  comment hints only
#   fonts    a search hint per missing font, on every distro

set -u

# shellcheck source-path=SCRIPTDIR
# shellcheck source=lib.sh
. "$(dirname "$0")/lib.sh"

# ---------- args ----------
template="${1:-}"
mode="${2:-check}"

templates="$(list_templates)"
valid=0
if [ -n "$template" ]; then
  for t in $templates; do
    [ "$t" = "$template" ] && valid=1
  done
fi
if [ "$valid" -ne 1 ]; then
  echo "STATUS=invalid"
  echo "OTHER_ERROR=template number must be one of: $(printf '%s' "$templates" | tr '\n' ' ') (got '${template}')"
  exit 4
fi
case "$mode" in
  check|install) ;;
  *)
    echo "STATUS=invalid"
    echo "OTHER_ERROR=second argument must be 'install' or omitted (got '${mode}')"
    exit 4
    ;;
esac

template_dir="$(skill_root)/templates/$template"
compiler="$(compiler_for "$template_dir/template.tex")"
echo "preflight: template=$template compiler=$compiler mode=$mode" >&2

# ---------- compiler presence ----------
compiler_path="$(command -v "$compiler" 2>/dev/null || true)"
if [ -z "$compiler_path" ]; then
  echo "STATUS=no-compiler"
  echo "DISTRO=$(detect_distro)"
  echo "COMPILER=$compiler"
  echo "COMPILER_PATH="
  echo "OTHER_ERROR=$compiler not found on PATH"
  echo "INSTALL_CMD=# Install a TeX distribution: MiKTeX (https://miktex.org) or TeX Live (https://tug.org/texlive), then make sure $compiler is on PATH"
  exit 2
fi

# ---------- smoke compile ----------
extra_flags=""
if have miktex; then
  # MiKTeX-only flag: auto-install missing packages during this very pass.
  extra_flags="--enable-installer"
fi

work=""
cleanup() {
  [ -n "$work" ] && rm -rf "$work"
}
trap cleanup EXIT

# smoke_compile: fresh copy of the template, two passes, PDF must exist.
smoke_compile() {
  [ -n "$work" ] && rm -rf "$work"
  work="$(mktemp -d)"
  cp -R "$template_dir"/. "$work"/
  # shellcheck disable=SC2086  # $extra_flags is intentionally word-split (empty or one flag)
  (cd "$work" && run_with_timeout 180 "$compiler" -interaction=nonstopmode -halt-on-error $extra_flags template.tex >/dev/null 2>&1) || return 1
  # shellcheck disable=SC2086
  (cd "$work" && run_with_timeout 180 "$compiler" -interaction=nonstopmode -halt-on-error $extra_flags template.tex >/dev/null 2>&1) || return 1
  [ -f "$work/template.pdf" ]
}

emit_ok() {
  echo "STATUS=ok"
  echo "DISTRO=$(detect_distro)"
  echo "COMPILER=$compiler"
  echo "COMPILER_PATH=$compiler_path"
}

echo "preflight: smoke-compiling template $template" >&2
if smoke_compile; then
  emit_ok
  exit 0
fi

# ---------- parse log for missing items ----------
log="$work/template.log"
missing_files=""     # name.ext per line
missing_fonts=""
other_errors=""
needs_update="no"

if [ -f "$log" ]; then
  # missing .sty / .cls / .def / .tex files
  missing_files="$(grep -aE "File [\`'][^']+\.(sty|cls|def|tex)' not found" "$log" 2>/dev/null \
    | sed -nE "s/.*File [\`']([^']+)\.(sty|cls|def|tex)' not found.*/\1.\2/p")"

  # missing fonts (pdftex / fontspec / TFM variants)
  missing_fonts="$(
    grep -aE "Font [A-Za-z0-9_-]+ at [0-9]+ not found" "$log" 2>/dev/null \
      | sed -nE 's/.*Font ([A-Za-z0-9_-]+) at [0-9]+ not found.*/\1/p'
    grep -aE 'The font "[^"]+" cannot be found' "$log" 2>/dev/null \
      | sed -nE 's/.*The font "([^"]+)" cannot be found.*/\1/p'
    grep -aE '^! Font .* not loadable: Metric \(TFM\) file' "$log" 2>/dev/null \
      | sed -nE 's/^! Font [^=]*=([^ ]+) at [0-9.]+pt not loadable.*/\1/p' \
      | tr -d '"'
  )"

  # font expansion / scalable font error (microtype + bitmap fonts)
  if grep -aqE "auto expansion is only possible with scalable fonts" "$log" 2>/dev/null; then
    other_errors="microtype font expansion requires scalable fonts (try adding \\usepackage{lmodern} before microtype)"
  fi

  # LaTeX format/release mismatch (package newer than the installed format)
  if grep -aqE "You have requested release '[0-9-]+' of LaTeX, but only release" "$log" 2>/dev/null; then
    needs_update="yes"
    msg="$(grep -aE "You have requested release" "$log" | head -n 1 | sed -E 's/^[[:space:]]+//')"
    other_errors="${other_errors}${other_errors:+
}${msg} - update your TeX distribution"
  fi

  # generic fatal-error fallback when nothing specific matched
  if [ -z "$missing_files" ] && [ -z "$missing_fonts" ] && [ -z "$other_errors" ]; then
    fatal="$(grep -aE "^! " "$log" | head -n 3 | tr '\n' '|')"
    [ -n "$fatal" ] && other_errors="$fatal"
  fi
else
  other_errors="$compiler produced no log file (crashed before starting?)"
fi

# Deduplicate, drop blanks, and keep only shell-safe package/font names.
missing_files="$(printf '%s\n' "$missing_files" | awk 'NF && !seen[$0]++')"
missing_fonts="$(printf '%s\n' "$missing_fonts" | awk 'NF && !seen[$0]++')"
safe_files=""
while IFS= read -r f; do
  [ -n "$f" ] || continue
  case "$f" in
    *[!A-Za-z0-9._+-]*) other_errors="${other_errors}${other_errors:+
}skipped unsafe missing-file name from log: $f" ;;
    *) safe_files="${safe_files}${safe_files:+
}$f" ;;
  esac
done <<EOF
$missing_files
EOF
missing_files="$safe_files"

distro="$(detect_distro)"
sudo_needed="no"
if [ "$distro" = "texlive" ]; then
  sudo_needed="$(tex_needs_sudo)"
fi
echo "preflight: distro=$distro sudo=$sudo_needed" >&2

case "$distro" in
  miktex|texlive) status="missing"; exit_code=1 ;;
  *)              status="no-distro"; exit_code=3 ;;
esac

# ---------- emit findings ----------
echo "STATUS=$status"
echo "DISTRO=$distro"
echo "COMPILER=$compiler"
echo "COMPILER_PATH=$compiler_path"
while IFS= read -r f; do
  [ -n "$f" ] || continue
  echo "MISSING_PKG=${f%.*}"
done <<EOF
$missing_files
EOF
while IFS= read -r f; do
  [ -n "$f" ] || continue
  echo "MISSING_FONT=$f"
done <<EOF
$missing_fonts
EOF
while IFS= read -r e; do
  [ -n "$e" ] || continue
  echo "OTHER_ERROR=$e"
done <<EOF
$other_errors
EOF
echo "NEEDS_UPDATE=$needs_update"
echo "SUDO=$sudo_needed"

# ---------- install commands ----------
install_cmds=""
add_cmd() {
  install_cmds="${install_cmds}${install_cmds:+
}$1"
}

sudo_prefix=""
[ "$sudo_needed" = "yes" ] && sudo_prefix="sudo "

case "$distro" in
  miktex)
    [ "$needs_update" = "yes" ] && add_cmd "miktex packages update --quiet && miktex update"
    while IFS= read -r f; do
      [ -n "$f" ] || continue
      add_cmd "miktex packages install ${f%.*}"
    done <<EOF
$missing_files
EOF
    while IFS= read -r f; do
      [ -n "$f" ] || continue
      add_cmd "# missing font '$f' - search MiKTeX's package repository for the providing package, then: miktex packages install <package>"
    done <<EOF
$missing_fonts
EOF
    ;;
  texlive)
    [ "$needs_update" = "yes" ] && add_cmd "${sudo_prefix}tlmgr update --self --all"
    while IFS= read -r f; do
      [ -n "$f" ] || continue
      add_cmd "${sudo_prefix}tlmgr install ${f%.*}"
    done <<EOF
$missing_files
EOF
    while IFS= read -r f; do
      [ -n "$f" ] || continue
      add_cmd "# missing font '$f' - find the providing package with: tlmgr search --global --file $f  then: ${sudo_prefix}tlmgr install <package>"
    done <<EOF
$missing_fonts
EOF
    ;;
  debian)
    add_cmd "sudo apt-get install texlive-latex-extra texlive-fonts-extra texlive-fonts-recommended texlive-xetex"
    while IFS= read -r f; do
      [ -n "$f" ] || continue
      add_cmd "# find the package providing $f: apt-file search $f"
    done <<EOF
$missing_files
EOF
    while IFS= read -r f; do
      [ -n "$f" ] || continue
      add_cmd "# missing font '$f' - find the providing package with: apt-file search $f"
    done <<EOF
$missing_fonts
EOF
    [ "$needs_update" = "yes" ] && add_cmd "# LaTeX release mismatch - update TeX via apt: sudo apt-get update && sudo apt-get upgrade texlive-base"
    ;;
  fedora)
    while IFS= read -r f; do
      [ -n "$f" ] || continue
      add_cmd "sudo dnf install 'tex($f)'"
    done <<EOF
$missing_files
EOF
    while IFS= read -r f; do
      [ -n "$f" ] || continue
      add_cmd "# missing font '$f' - find the providing package with: dnf provides '*/$f*'"
    done <<EOF
$missing_fonts
EOF
    [ "$needs_update" = "yes" ] && add_cmd "# LaTeX release mismatch - update TeX via dnf: sudo dnf upgrade texlive-base"
    ;;
  *)
    add_cmd "# no supported package manager found (miktex/tlmgr/apt/dnf) - install the items below with whatever provides your TeX (nix, conda, docker image, ...)"
    while IFS= read -r f; do
      [ -n "$f" ] || continue
      add_cmd "# missing file: $f (package ${f%.*})"
    done <<EOF
$missing_files
EOF
    while IFS= read -r f; do
      [ -n "$f" ] || continue
      add_cmd "# missing font: $f"
    done <<EOF
$missing_fonts
EOF
    [ "$needs_update" = "yes" ] && add_cmd "# LaTeX release mismatch - update your TeX distribution"
    ;;
esac

while IFS= read -r c; do
  [ -n "$c" ] || continue
  echo "INSTALL_CMD=$c"
done <<EOF
$install_cmds
EOF

# ---------- install mode ----------
if [ "$mode" = "install" ]; then
  case "$distro" in
    miktex|texlive) ;;
    *)
      echo "preflight: distro=$distro cannot auto-install - run the INSTALL_CMD hints manually" >&2
      exit 3
      ;;
  esac
  if [ "$sudo_needed" = "yes" ] && [ ! -t 0 ]; then
    echo "OTHER_ERROR=install needs sudo; run the INSTALL_CMD lines manually"
    exit 3
  fi

  echo "preflight: install mode active - running install commands" >&2
  ran=0
  while IFS= read -r c; do
    [ -n "$c" ] || continue
    case "$c" in
      '#'*) continue ;;
    esac
    ran=$((ran + 1))
    echo "preflight: $c" >&2
    eval "$c" 1>&2 || echo "preflight: command exited non-zero (continuing): $c" >&2
  done <<EOF
$install_cmds
EOF
  [ "$ran" -gt 0 ] || echo "preflight: nothing runnable to install (hints only)" >&2

  echo "preflight: re-running smoke compile" >&2
  if smoke_compile; then
    echo "POST_INSTALL_STATUS=ok" >&2
    emit_ok
    exit 0
  fi
  echo "POST_INSTALL_STATUS=still-failing" >&2
  echo "STATUS=install-failed"
  log_tail "$work/template.log" 20
  exit 5
fi

exit "$exit_code"
