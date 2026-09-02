# Generation — produce a tailored LaTeX resume + PDF

You are reading this because the gate in `SKILL.md` confirmed `knowledge.yaml` is filled (validator exit 0 or its manual equivalent; role-aware soft gate satisfied or explicitly waived).

`<SKILL_ROOT>` = the directory containing this file. `<cwd>` = the user's current working directory. `<dir>` = the output directory chosen in Step 3. `<N>` = the template number.

Sub-docs loaded on demand from here: `variants.md` (several resumes in one request), `deep-dive.md` (Step 4.5), `cover-letter.md` (Step 9).

---

## Inputs you should already have

- `knowledge.yaml` content (read once at the gate; re-read if it changed since) plus the validator's `OPTIONAL_PLACEHOLDER=` lines
- Job posting analysis, if a posting was given (pasted text analysed inline, or the analyser sub-agent's return)
- Optional: explicit template number, `--cover-letter`, `--skip-preflight`, the soft-gate gap list

**Several postings or templates in one request?** Finish reading this file, then **read `<SKILL_ROOT>/variants.md`** before doing any work.

---

## Step 1 — Resolve template

1. **User explicitly named one** ("use template 3", "the academic one", `--template N`). Use it.
2. **Posting available, no explicit choice.** Classify inline (the analysis is already in context):

   | Role signal | Template | Confidence rule |
   |---|---|---|
   | Academic / research / PhD / postdoc / faculty; posting asks for publications | 3 (Freeman Academic CV) | high if the title contains research/PhD/postdoc/professor/fellow |
   | Industry SWE / ML / data / backend / frontend / product / ops | 2 (Modern Professional, default) | high for an industry tech role with no academic signal |
   | Student / new grad / internship / junior; yaml shows ≤ 2 years of experience | 1 (Classic Graduate) | medium-high if the posting says intern/graduate/junior/entry-level |
   | Continental-European application: photo, date of birth, nationality customary; user says "European CV" | 4 (ModernCV) | low unless explicit |
   | UK/Commonwealth professional CV: referees expected; finance, consulting, legal | 5 (Wilson) | low unless explicit, or the posting is UK-based and asks for referees |
   | Minimal one page, "clean", "concise"; creative/design/UX where portfolio links lead | 6 (Cies) | medium if length-constrained or creative-track |

   High/medium → auto-pick and tell the user once: "Picked Template N because <reason>. Say so to override." Low → ask, default 2.
3. **No posting, no explicit choice.** Ask; default 2.

Then **read `<SKILL_ROOT>/templates/<N>/NOTES.md`**: the macro cheat-sheet, yaml→LaTeX mapping, and gotchas for that template.

---

## Step 1.5 — Preflight (LaTeX environment check)

Skip if `--skip-preflight` was given, or a preflight in this session already returned `STATUS=ok` for this template number.

```bash
bash <SKILL_ROOT>/tests/preflight.sh <N>
```

The script smoke-compiles the bundled `template.tex` in a temp dir (ground truth, no hardcoded package list) and only looks at the TeX distribution when that fails. Stdout is `KEY=value`; stderr is progress.

| Exit | STATUS | Meaning | Action |
|---|---|---|---|
| 0 | `ok` | the template compiles here | proceed |
| 1 | `missing` | gaps found; `DISTRO=miktex` or `texlive` can auto-install | "Missing items" flow below |
| 2 | `no-compiler` | compiler not on PATH | show the `INSTALL_CMD` hint (install MiKTeX or TeX Live) and offer two ways forward: install TeX and re-invoke, or continue **source-only** (Steps 3-6 and 8 run, lint included; no PDF, QA numbers unmeasured, the user compiles elsewhere, e.g. Overleaf). Non-interactive session → source-only. |
| 3 | `no-distro` | gaps found but no auto-install path: Debian/Fedora-packaged TeX (`DISTRO=debian`/`fedora`), unknown distro, or `sudo` needed without a terminal | show the `MISSING_*` and `INSTALL_CMD` lines for the user to run themselves, abort |
| 4 | `invalid` | bad arguments: a bug in this skill | surface, abort |
| 5 | `install-failed` | install ran, the smoke compile still fails | show the log tail from stderr; ask: continue anyway (rarely works) or abort |

### Missing items (exit 1) flow

1. Parse `MISSING_PKG=`, `MISSING_FONT=`, `OTHER_ERROR=`, `NEEDS_UPDATE=`, `SUDO=`, `INSTALL_CMD=`.
2. Show a tight summary plus the exact commands, then ask `Install? (y/n)`. Only `y`/`yes` counts.
3. Yes → `bash <SKILL_ROOT>/tests/preflight.sh <N> install`, streaming stderr. With `SUDO=yes` the commands need a password and only run when a terminal is attached; otherwise the script exits 3 and the user runs them manually.
4. No → abort, leaving the commands on screen.

`NEEDS_UPDATE=yes` means the log showed a LaTeX release mismatch, so the distro update command is included first. It never runs otherwise (slow, needs privileges).

---

## Step 2 — Resolve job posting analysis

Already done at the gate: pasted text → inline analysis; URL/file → the sub-agent's return. Don't re-fetch. No posting → no role tailoring: broad framing, everything in, most recent first.

---

## Step 3 — Resolve output directory

`<dir>` = `<cwd>/outputs/<slug>/`; slug lowercase kebab-case:

- company + role + year when known: `google-swe-2026`, `iit-ml-research-2026`
- role only: `<role>-<yyyy>`; neither: `general-t<N>-<yyyy>`

Collisions: `<dir>` exists with content → append `-v2`, `-v3`, … Exception: the user asked to regenerate the same application ("redo the Stripe one after my edits") → ask once whether to overwrite `<slug>` or create `-v2`. Never overwrite without that answer.

Create the directory.

---

## Step 4 — Copy template assets

From `<SKILL_ROOT>/templates/<N>/` into `<dir>`, everything except `template.tex` and `NOTES.md`:

| Template | Copy |
|---|---|
| 1 | `res.cls` |
| 2 | `resume.cls` |
| 3 | `FreemanCV.cls`, `Fonts/` |
| 4 | `moderncv.cls`, every `*.sty` (never `pictures/`; it holds a sample photo) |
| 5 | `structure.tex`, `fonts/` |
| 6 | `structure.tex` |

Use `cp -r`; **preserve directory case** (`Fonts/` vs `fonts/`; Linux/macOS are case-sensitive). If the yaml sets `photo:` (template 4), copy that file into `<dir>` as `photo.<ext>`.

---

## Step 4.5 — Deep-dive on `evidence:` (conditional)

Only when a job posting is in context **and** at least one relevant entry carries a non-empty `evidence:` list: **read `<SKILL_ROOT>/deep-dive.md` and follow it.** It returns tailoring deltas that you merge into the in-memory yaml view. Otherwise skip to Step 5.

---

## Step 5 — Generate `resume.tex`

Open `templates/<N>/template.tex` as the structural reference (you already have `NOTES.md`). Write `<dir>/resume.tex`:

1. **First line** is the compiler marker: copy `%!TEX program = xelatex` from `template.tex` when present, else write `%!TEX program = pdflatex`. `build.sh` and `lint-tex.sh` read it.
2. Mirror the preamble (`\documentclass`, packages, custom commands). For pdflatex templates add `\usepackage[T1]{fontenc}` when the text has non-ASCII characters.
3. **Drop every sample**: names, employers, lorem ipsum, the moderncv cover-letter block (unless `cover-letter.md` says otherwise), `\photo` unless `photo:` is set, date-of-birth/nationality rows unless set, sample referees (use `references:` from the yaml, else "References available on request" or omit the section).
4. **Sentinel values are absent**: any value matching `<[A-Z][A-Za-z0-9_]*>` (the gate's `OPTIONAL_PLACEHOLDER=` lines) is omitted; if an entry's key field (name/title/degree) is a sentinel, drop the whole entry.
5. **Select and order** (posting in context):
   - `pin: true` entries always stay.
   - Keep entries whose `tags`, `technologies`, or text overlap the posting's required skills or domain; cut clearly off-topic ones (a Photoshop teaching gig on a backend SWE resume).
   - Within a section, most recent first: use `start`/`end` (ISO) and else parse `years`.
   - Order sections by relevance: experience before projects for senior roles; projects and education first for entry-level.
   - Without a posting: keep everything, most recent first.
6. **Page budget**: `page_limit` from the yaml, else Template 1: 1; Template 2: 1 (2 when the yaml shows more than ~8 years of experience); 3, 4, 5: 2; 6: 1. Trim lowest-relevance content first: oldest projects, then oldest experience bullets, then optional sections (interests, awards, events). Step 7.5 measures the real count.
7. **Tailor wording**: rephrase achievements in the posting's vocabulary, lead `profile` with the role's top requirements. Never invent facts, numbers, employers, or dates; reordering and rephrasing are fine.
8. **Headings**: when `language:` is not `en`, read `<SKILL_ROOT>/assets/section-headings.yaml` and use those headings; body text stays as written. For pdflatex templates add `\usepackage[<italian|german|french|spanish>]{babel}`.
9. **LaTeX escaping** of every value taken from the yaml: `&`→`\&`, `%`→`\%`, `$`→`\$`, `#`→`\#`, `_`→`\_`, `{`→`\{`, `}`→`\}`, `~`→`\textasciitilde{}`, `^`→`\textasciicircum{}`. Inside `\href{URL}{text}` the URL stays raw; the display text is escaped.
10. **Links**: always `\href{<url>}{<display>}`. Templates 1 and 2 load `hyperref` in the preamble, 3 and 4 in the class, 5 and 6 in `structure.tex`; never load it twice.

### Tailoring presets

| Template | Emphasis |
|---|---|
| 1 (Classic Graduate) | Objective line, education first with coursework/GPA, projects and internships as experience, skills block |
| 2 (Modern Professional) | Quantified achievements, project tech stacks, recent experience first, one page |
| 3 (Freeman Academic) | Research/thesis prose, publications (citations + DOI table), teaching, awards, references |
| 4 (ModernCV) | European conventions: photo/date of birth/nationality when provided, languages with levels, interests |
| 5 (Wilson) | UK conventions: personal profile, employment history with a "Technologies:" line, referees |
| 6 (Cies) | Ruthless one page: two-column summary, top 4 experiences, top 3 projects, prose skills |

---

## Step 6 — Reviews (inline, in main)

### 6a. Lint (deterministic)

```bash
bash <SKILL_ROOT>/tests/lint-tex.sh <dir>/resume.tex
```

Fix every `LINT_ERROR=` (unescaped specials, unbalanced braces or environments, leaked sample data or placeholders, `\href` without hyperref) and re-run; stop after three rounds and tell the user what remains. A `template sample data leaked` hit is a false positive when the string genuinely comes from `knowledge.yaml` (an alma mater such as MIT or Berkeley); check the yaml before changing anything. `LINT_WARN=` lines are hints. Then read the file once yourself for what lint cannot see: macros with the wrong number of brace arguments (NOTES.md lists the arities), headings that no longer match their content.

### 6b. Content review + coverage matrix (only with a posting)

Build the coverage matrix from the posting analysis, one row per required or preferred item:

| Requirement | Status | Where on the resume |
|---|---|---|
| Python, 5+ years | covered | Experience: Halcyon (2021-), Skills |
| Kubernetes | covered | Experience: Halcyon, bullet 2 |
| Go | partial | Skills only; no achievement mentions it |
| Kafka Streams | missing | not in knowledge.yaml |

Coverage score = covered / total. It measures keyword coverage, not hiring odds; say so whenever you report it. Then check: the top-3 required skills are visible in the first half of page 1; achievements are quantified where the yaml has numbers; nothing misaligned with the role slipped in; nothing high-impact and matching was dropped. Apply edits and re-run 6a if you touched LaTeX.

---

## Step 7 — Build

```bash
bash <SKILL_ROOT>/tests/build.sh <dir> --template <N>
```

Uses `latexmk` when available, otherwise two compiler passes, then runs the post-compile checks. Stdout keys: `STATUS`, `COMPILER`, `PDF`, `PAGES`, `OVERFULL`, `UNDERFULL`, `TEXT_EXTRACT`, `PLACEHOLDER_LEAK`, `UNRESOLVED_REFS`, `LEAK=` lines, `PNG`. Aux files are cleaned; `resume.log` stays.

`STATUS=compile-failed` (exit 1):
1. The last 40 log lines are on stderr; show the user the `!` lines.
2. **Dispatch a sub-agent** to diagnose (the log is verbose; keep it out of main): `subagent_type: general-purpose`, `model: sonnet`, `description: Diagnose LaTeX compile error`; prompt with the paths to `resume.log` and `resume.tex`, asking for the line number and replacement only, not the log content.
3. Apply, rebuild. One retry; then surface the diagnosis to the user.

`STATUS=no-compiler` means preflight was skipped on a machine without TeX: go back to Step 1.5.

---

## Step 7.5 — QA gate on the PDF

| Check | Rule | Fix |
|---|---|---|
| `PAGES` | ≤ the page budget from Step 5.6 | trim per Step 5.6 and rebuild; one trim cycle, then report the overrun |
| `PLACEHOLDER_LEAK`, `LEAK=` | 0 / none (both only reported when `TEXT_EXTRACT=ok`) | fix the source, rebuild; a `LEAK=` string that genuinely comes from `knowledge.yaml` is a false positive |
| `UNRESOLVED_REFS` | 0 | rebuild (needs the second pass) or fix the reference |
| `OVERFULL` | > 5 → inspect | shorten long unbreakable tokens (URLs, comma-less tech lists) |
| `TEXT_EXTRACT=empty` | warn the user | the PDF has no extractable text; ATS parsers will see nothing |
| `PNG` | view it once with the image reader | name header intact, no empty section, no orphan heading at a page bottom, columns balanced (template 3), nothing pushed off the page; one fix-and-rebuild cycle |

---

## Step 8 — Persist + report

Write into `<dir>`:

- `tailored.yaml`: the in-memory view that was actually rendered (after deep-dive merges and selection), headed by `# generated by resume-generator; edit knowledge.yaml, not this file`.
- `report.md`: template + reason; posting (title, company, source); coverage matrix and score; what was dropped, reordered, or rephrased; deep-dive deltas and warnings; QA numbers (pages, overfull, leaks); soft-gate gaps the user waived.

Append one row to `<cwd>/outputs/index.md` (create it with the header row when missing):

```
| Date | Slug | Company | Role | Template | Pages | PDF | Posting |
|---|---|---|---|---|---|---|---|
| 2026-09-02 | stripe-backend-swe-2026 | Stripe | Backend SWE | 2 | 1 | outputs/stripe-backend-swe-2026/resume.pdf | https://… |
```

Then report to the user, tightly: the PDF path (clickable), template + reason, coverage score with its caveat, warnings, the `report.md` path. Never write anything back to `<cwd>/knowledge.yaml`.

---

## Step 9 — Cover letter (only when requested)

`--cover-letter` or "and a cover letter" → **read `<SKILL_ROOT>/cover-letter.md`** and follow it. It reuses the posting analysis, the coverage matrix, and `<dir>`.

---

## Critical rules

- Never hardcode personal data; every value comes from `knowledge.yaml` (or a deep-dive citation of the user's own evidence).
- Never invent facts during tailoring. Reordering and rephrasing OK; fabricating achievements not OK.
- Copy class/style/font files into `<dir>` before compiling; compile only there, never in the skill folder.
- The compiler comes from the `%!TEX program` marker (templates 3 and 5 are xelatex); `build.sh` reads it, so keep it on line 1 of `resume.tex`.
- Scripts run from `<SKILL_ROOT>/tests/`; never copy them into `<cwd>`.
- The tailored view goes to `<dir>/tailored.yaml`; `<cwd>/knowledge.yaml` is never modified here.
- Output slugs are lowercase kebab-case; collisions get `-v2`, never silent overwrites.

## Common mistakes

| Mistake | Fix |
|---|---|
| `.cls`/`.sty`/fonts not copied to `<dir>` | Re-run Step 4 |
| pdflatex used on template 3 or 5 | Keep the `%!TEX program = xelatex` line; `build.sh` honours it |
| Missing `Fonts/` (3) or `fonts/` (5) | Copy the whole directory, preserve case |
| Missing `*.sty` for template 4 | Copy every `*.sty` from `templates/4/` |
| Sample name or `<PLACEHOLDER>` in the PDF | Lint (6a) and `build.sh` leak checks catch it; fix the source |
| `\photo{pictures/picture}` left in template 4 | Only emit `\photo` when `photo:` is set, pointing at the copied file |
| Resume over the page budget | Trim per Step 5.6; don't shrink fonts below the template's default |
| `&` in a company name | `\&`; lint flags it |
| Stale yaml data | Re-read `<cwd>/knowledge.yaml` |
| Overwrote a previous output | Collisions get `-v2`; overwrite only after asking |
