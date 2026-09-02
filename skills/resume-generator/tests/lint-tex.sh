#!/usr/bin/env bash
# lint-tex.sh - deterministic lint of a generated resume.tex (or cover-letter.tex).
#
# Usage:
#   lint-tex.sh <file.tex>
#
# Comments are stripped first (a `%` not preceded by a backslash starts a
# comment), then the checks below run on the remaining source.
#
# ERROR checks:
#   - placeholder sentinels          <[A-Z][A-Za-z0-9_]*>  (e.g. <YOUR_NAME>)
#   - template sample-data leaks     every string in leak-strings.txt, matched
#                                    case-insensitively as a fixed string
#   - \begin{X}/\end{X} mismatch or unclosed environment (verbatim-like
#                                    environments are skipped)
#   - unbalanced { } over the file   (escaped \{ \} ignored)
#   - \href/\url without hyperref    (hyperref counts as present when the file
#                                    loads it, uses the FreemanCV/moderncv class,
#                                    or pulls in structure.tex via \input/\include)
#   - unescaped &                    outside table environments (tabular,
#                                    tabular*, tabularx, longtable, supertabular,
#                                    array, align, ...), outside \href{...}/\url{...}
#                                    arguments and macro definitions
#   - unescaped _ or #               outside math ($...$, \(...\)), outside
#                                    \href{...}/\url{...} (and other path-like
#                                    arguments such as \includegraphics{...}) and
#                                    outside \newcommand/\renewcommand/\def bodies
# WARN checks:
#   - odd number of unescaped $ on a line (likely an unescaped dollar amount)
#   - \usepackage{lipsum}
#   - no `%!TEX program = ...` magic comment in the first 30 lines
#
# Stdout:
#   LINT_ERROR=<line>: <message>      (zero or more)
#   LINT_WARN=<line>: <message>       (zero or more)
#   STATUS=ok|errors
#   ERRORS=<n>
#   WARNINGS=<n>
#
# Exit codes: 0 no errors (warnings allowed), 1 at least one error, 4 bad args.
# Heuristic by design: it aims for zero false positives on the bundled
# templates (apart from their intentional sample data).

set -u

# shellcheck source-path=SCRIPTDIR
# shellcheck source=lib.sh
. "$(dirname "$0")/lib.sh"

if [ "$#" -ne 1 ] || [ -z "${1:-}" ]; then
  echo "usage: $0 <file.tex>" >&2
  exit 4
fi
file="$1"
if [ ! -f "$file" ]; then
  echo "lint-tex: no such file: $file" >&2
  exit 4
fi

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
stripped="$tmp/stripped.tex"
findings="$tmp/findings.tsv"
leaks="$tmp/leaks.txt"
: > "$findings"

# ---- 1. strip comments (line numbers preserved) -------------------------------
awk '
{
  line = $0
  sub(/\r$/, "", line)
  out = ""
  n = length(line)
  i = 1
  while (i <= n) {
    c = substr(line, i, 1)
    if (c == "\\") {
      out = out substr(line, i, 2)
      i += 2
      continue
    }
    if (c == "%") break
    out = out c
    i++
  }
  print out
}' "$file" > "$stripped"

# ---- 2. placeholder sentinels ---------------------------------------------------
awk -v re="$RG_SENTINEL_RE" '
{
  if (match($0, re)) {
    printf "%d\tERROR\ttemplate placeholder left in the document: %s\n", NR, substr($0, RSTART, RLENGTH)
  }
}' "$stripped" >> "$findings"

# ---- 3. sample-data leaks --------------------------------------------------------
leak_strings > "$leaks"
if [ -s "$leaks" ]; then
  awk -v leakfile="$leaks" '
  FILENAME == leakfile {
    s = $0
    if (s == "") next
    nl++
    orig[nl] = s
    low[nl] = tolower(s)
    next
  }
  {
    l = tolower($0)
    for (k = 1; k <= nl; k++) {
      if (index(l, low[k]) > 0) {
        printf "%d\tERROR\ttemplate sample data leaked (verify against knowledge.yaml): \"%s\"\n", FNR, orig[k]
      }
    }
  }' "$leaks" "$stripped" >> "$findings"
fi

# ---- 4. structural scan: environments, braces, & _ # $ ------------------------------
awk '
function report(kind, line, msg) {
  printf "%d\t%s\t%s\n", line, kind, msg
}
function push_env(e) {
  envtop++
  envname[envtop] = e
  envline[envtop] = ln
  if (e in istable) tblactive++
  if (e in israw) {
    rawmode = 1
    rawend = "\\end{" e "}"
  }
}
function pop_env(e,    k, m) {
  if (envtop == 0) {
    report("ERROR", ln, "\\end{" e "} without a matching \\begin{" e "}")
    return
  }
  if (envname[envtop] == e) {
    if (e in istable) tblactive--
    envtop--
    return
  }
  for (k = envtop; k >= 1; k--) if (envname[k] == e) break
  if (k >= 1) {
    for (m = envtop; m > k; m--) {
      report("ERROR", ln, "\\end{" e "} reached while \\begin{" envname[m] "} (line " envline[m] ") is still open - missing \\end{" envname[m] "}")
      if (envname[m] in istable) tblactive--
    }
    if (e in istable) tblactive--
    envtop = k - 1
  } else {
    report("ERROR", ln, "\\end{" e "} does not match the innermost open environment \\begin{" envname[envtop] "} (line " envline[envtop] ")")
  }
}
function handle_command(name,    r, ename, delim, q, base) {
  base = name
  sub(/\*$/, "", base)
  if (name == "begin" || name == "end") {
    r = substr(line, i)
    if (match(r, /^[[:space:]]*\{[^}]*\}/)) {
      ename = substr(r, RSTART, RLENGTH)
      sub(/^[[:space:]]*\{/, "", ename)
      sub(/\}$/, "", ename)
      i += RLENGTH
      if (name == "begin") push_env(ename)
      else pop_env(ename)
    }
    return
  }
  if (name == "verb" || name == "verb*") {
    delim = substr(line, i, 1)
    q = index(substr(line, i + 1), delim)
    if (q > 0) i += q + 1
    else i = n + 1
    return
  }
  if (base in ispath) {
    wantgroup = 1
    return
  }
  if (base in isdefn) {
    if (!in_defn) {
      in_defn = 1
      defn_depth = depth
      defn_entered = 0
      defn_wait = 0
    }
    return
  }
}
BEGIN {
  split("tabular tabular* tabularx tabulary tabu longtable longtabu supertabular supertabular* xtabular xtabular* mpsupertabular array matrix pmatrix bmatrix vmatrix Vmatrix smallmatrix cases align align* alignat alignat* aligned alignedat flalign flalign* eqnarray eqnarray* split gathered", a, " ")
  for (k in a) istable[a[k]] = 1
  split("verbatim verbatim* Verbatim lstlisting minted comment filecontents filecontents*", b, " ")
  for (k in b) israw[b[k]] = 1
  split("href url path nolinkurl includegraphics input include label ref pageref eqref cite citep citet nocite bibliography bibliographystyle photo email homepage social setmainfont setsansfont setmonofont newfontfamily newfontface hypersetup graphicspath lstinputlisting verbatiminput InputIfFileExists", c, " ")
  for (k in c) ispath[c[k]] = 1
  split("newcommand renewcommand providecommand def edef gdef xdef newenvironment renewenvironment DeclareRobustCommand newcolumntype NewDocumentCommand RenewDocumentCommand ProvideDocumentCommand DeclareDocumentCommand NewDocumentEnvironment RenewDocumentEnvironment", d, " ")
  for (k in d) isdefn[d[k]] = 1
  depth = 0; nopen = 0; nclose = 0; negline = 0
  envtop = 0; tblactive = 0; math = 0
  skipping = 0; skip_depth = 0; wantgroup = 0
  in_defn = 0; defn_depth = 0; defn_entered = 0; defn_wait = 0
  rawmode = 0; rawend = ""
}
{
  line = $0
  ln = NR
  dollars = 0
  if (in_defn && defn_wait) {
    defn_wait = 0
    if (line !~ /^[[:space:]]*[{[]/) in_defn = 0
  }
  n = length(line)
  i = 1
  while (i <= n) {
    if (rawmode) {
      p = index(substr(line, i), rawend)
      if (p == 0) { i = n + 1; continue }
      i = i + p - 1 + length(rawend)
      rawmode = 0
      envtop--
      continue
    }
    ch = substr(line, i, 1)
    if (ch == "\\") {
      nx = substr(line, i + 1, 1)
      if (nx ~ /[A-Za-z]/) {
        j = i + 1
        while (j <= n && substr(line, j, 1) ~ /[A-Za-z]/) j++
        cname = substr(line, i + 1, j - i - 1)
        if (substr(line, j, 1) == "*") { cname = cname "*"; j++ }
        i = j
        handle_command(cname)
        continue
      }
      if (nx == "(" || nx == "[") math = 1
      else if (nx == ")" || nx == "]") math = 0
      i += 2
      continue
    }
    if (wantgroup) {
      if (ch == " " || ch == "\t") { i++; continue }
      if (ch == "[") {
        q = index(substr(line, i), "]")
        if (q == 0) { i = n + 1; continue }
        i += q
        continue
      }
      wantgroup = 0
      if (ch == "{") {
        skipping = 1
        skip_depth = depth
      }
    }
    if (ch == "{") {
      if (in_defn && depth == defn_depth) defn_entered = 1
      depth++
      nopen++
      openline[depth] = ln
      i++
      continue
    }
    if (ch == "}") {
      nclose++
      depth--
      if (depth < 0) {
        if (!negline) negline = ln
        depth = 0
      }
      if (skipping && depth <= skip_depth) skipping = 0
      if (in_defn && defn_entered && depth == defn_depth) {
        rest = substr(line, i + 1)
        if (rest ~ /^[[:space:]]*$/) defn_wait = 1
        else if (rest !~ /^[[:space:]]*[{[]/) in_defn = 0
      }
      i++
      continue
    }
    if (skipping) { i++; continue }
    if (ch == "$") {
      if (substr(line, i + 1, 1) == "$") { math = !math; dollars += 2; i += 2; continue }
      math = !math
      dollars++
      i++
      continue
    }
    if (ch == "&") {
      if (tblactive == 0 && !in_defn) report("ERROR", ln, "unescaped & outside a table environment (write \\&)")
      i++
      continue
    }
    if (ch == "_") {
      if (!math && !in_defn) report("ERROR", ln, "unescaped _ in text mode (write \\_)")
      i++
      continue
    }
    if (ch == "#") {
      if (!in_defn) report("ERROR", ln, "unescaped # in text mode (write \\#)")
      i++
      continue
    }
    i++
  }
  if (dollars % 2 == 1) report("WARN", ln, "odd number of unescaped $ on this line (unescaped dollar amount? write \\$)")
}
END {
  for (k = envtop; k >= 1; k--) report("ERROR", envline[k], "unclosed \\begin{" envname[k] "} - no matching \\end{" envname[k] "}")
  if (nopen != nclose) {
    where = negline
    if (where == 0 && depth > 0) where = openline[1]
    if (where == 0) where = NR
    report("ERROR", where, "unbalanced braces: " nopen " opening { vs " nclose " closing } over the whole file")
  }
}' "$stripped" >> "$findings"

# ---- 5. \href / \url without hyperref -------------------------------------------
link_line="$(grep -nE '\\(href|url)[{|]' "$stripped" | head -n 1 | cut -d: -f1)"
if [ -n "$link_line" ]; then
  if ! grep -qE '\\(usepackage|RequirePackage)(\[[^]]*\])?\{[^}]*hyperref' "$stripped" \
     && ! grep -qE '\{(FreemanCV|moderncv)\}' "$stripped" \
     && ! grep -qE '\\(input|include)\{structure(\.tex)?\}' "$stripped"; then
    printf '%s\tERROR\t%s\n' "$link_line" '\href/\url used but hyperref is not loaded (add \usepackage[hidelinks]{hyperref})' >> "$findings"
  fi
fi

# ---- 6. warnings -----------------------------------------------------------------
lipsum_line="$(grep -nE '\\usepackage(\[[^]]*\])?\{[^}]*lipsum' "$stripped" | head -n 1 | cut -d: -f1)"
if [ -n "$lipsum_line" ]; then
  printf '%s\tWARN\t%s\n' "$lipsum_line" '\usepackage{lipsum} loaded - dummy text package does not belong in a resume' >> "$findings"
fi
if [ -z "$(magic_program "$file")" ]; then
  printf '%s\tWARN\t%s\n' 1 'no "%!TEX program = <compiler>" magic comment in the first 30 lines (carry it over from the template so build.sh picks the right compiler)' >> "$findings"
fi

# ---- emit ----------------------------------------------------------------------------
tab="$(printf '\t')"
errors=0
warnings=0
sorted="$tmp/sorted.tsv"
sort -t "$tab" -k1,1n -k2,2 -k3,3 "$findings" > "$sorted"
while IFS="$tab" read -r line kind msg; do
  [ -n "$kind" ] || continue
  if [ "$kind" = "ERROR" ]; then
    echo "LINT_ERROR=$line: $msg"
    errors=$((errors + 1))
  else
    echo "LINT_WARN=$line: $msg"
    warnings=$((warnings + 1))
  fi
done < "$sorted"

if [ "$errors" -gt 0 ]; then
  echo "STATUS=errors"
else
  echo "STATUS=ok"
fi
echo "ERRORS=$errors"
echo "WARNINGS=$warnings"
[ "$errors" -eq 0 ]
