# Generation — produce a tailored LaTeX resume + PDF

You are reading this because the gate in `SKILL.md` confirmed `knowledge.yaml` is filled (validator exit 0 or its manual equivalent; role-aware soft gate satisfied or explicitly waived).

`<SKILL_ROOT>` = the directory containing this file. `<cwd>` = the user's current working directory. `<dir>` = the output directory chosen in Step 3. `<N>` = the template number.

Sub-docs loaded on demand from here: `variants.md` (several resumes in one request), `deep-dive.md` (Step 4.5), `cover-letter.md` (Step 9).

---

## Inputs you should already have

- `knowledge.yaml` content (read once at the gate; re-read if it changed since) plus the validator's `OPTIONAL_PLACEHOLDER=` lines
- The `env-probe.sh` lines from `SKILL.md` Step 1: `SOURCE_ONLY=yes|no` (decided at entry when no compiler was found), `PYYAML=`, `PDFTOTEXT=`, `PDFTOPPM=`
- The mode: `generate` (default), `refresh <slug>`, `rebuild <slug>`, or `letter-only <slug>` (see "Re-entry modes")
- Job posting analysis, if a posting was given (pasted text analysed inline, or the analyser sub-agent's return), or the saved `outputs/<slug>/posting.json` in refresh / letter-only mode
- Optional: explicit template number, `--cover-letter`, `--skip-preflight`, the soft-gate gap list split into **asked** (user answered fill/proceed) and **deferred** (an `evidence:` entry may answer them; Step 4.6)

**Several postings or templates in one request?** Finish reading this file, then **read `<SKILL_ROOT>/variants.md`** before doing any work.

## Re-entry modes

Every output dir carries `posting.json` and `tailored.yaml` (Step 8), so later requests about the same application never re-fetch or re-ask.

| Mode | Trigger | What runs |
|---|---|---|
| **refresh** `<slug>` | `--refresh <slug>`, "redo the Stripe one after my edits to knowledge.yaml" | `<dir>` = `<cwd>/outputs/<slug>/`. Read `<dir>/posting.json` (analysis + template) and the previous `tailored.yaml` (for reference only). Ask the Step 3 overwrite-or-`-v2` question once. Then Steps 4 → 8 on the current `knowledge.yaml`: no template question, no fetch, no preflight if one passed this session. `posting.json` missing (pre-0.4 output) → use the posting section of `report.md`, and if that is too thin ask for the posting again. |
| **rebuild** `<slug>` | `--rebuild <slug>`, "I edited the tex by hand, rebuild it" | Step 6a on the existing `<dir>/resume.tex` (fix only what lint flags, and say so), Step 7 (`qa-gate.sh`), Step 7.5. Then replace the QA numbers block in `report.md`, update the `Pages` cell of the `index.md` row, and report. Never re-plan or re-render; `tailored.yaml` is left as is with a `# resume.tex edited by hand after this plan` note prepended. |
| **letter-only** `<slug>` | `--cover-letter --for <slug>`, "cover letter for the Stripe one" | Skip to Step 9; `cover-letter.md` reads `<dir>/posting.json` and `tailored.yaml`. |

Slug resolution: exact directory name under `outputs/`; else the unique row of `outputs/index.md` whose Slug or Company column contains the user's words; ambiguous or absent → list the candidates and ask.

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

`env-probe.sh` already established at entry whether a compiler exists; preflight is the per-template smoke compile. Skip it when `--skip-preflight` was given, when a preflight in this session already returned `STATUS=ok` for this template number, or when `SOURCE_ONLY=yes` was decided at entry (Steps 7 and 7.5 are skipped too; the user compiles elsewhere).

```bash
bash <SKILL_ROOT>/tests/preflight.sh <N>
```

The script smoke-compiles the bundled `template.tex` in a temp dir (ground truth, no hardcoded package list) and only looks at the TeX distribution when that fails. Stdout is `KEY=value`; stderr is progress.

| Exit | STATUS | Meaning | Action |
|---|---|---|---|
| 0 | `ok` | the template compiles here | proceed |
| 1 | `missing` | gaps found; `DISTRO=miktex` or `texlive` can auto-install | "Missing items" flow below |
| 2 | `no-compiler` | compiler not on PATH | cannot happen after `env-probe.sh` unless PATH changed; treat as at entry: ask install-or-source-only once (source-only = Steps 3-6 and 8 run, lint included; no PDF; the user compiles elsewhere, e.g. Overleaf). Non-interactive session → source-only. |
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

Only when a job posting is in context **and** at least one relevant entry carries a non-empty `evidence:` list (or the deferred-gap list names one): **read `<SKILL_ROOT>/deep-dive.md` and follow it.** Phase 1 fills or reads `<cwd>/.resume-cache/evidence/`; Phase 2 merges tailoring deltas into the in-memory yaml view and returns, per deferred gap, `addressed` or `still-open`. Otherwise every deferred gap is `still-open`; go to Step 4.6.

---

## Step 4.6 — Deferred gaps (one question at most)

`SKILL.md` Step 3 deferred the gaps that an `evidence:` entry might answer. Now they are settled:

- No deferred gaps, or all `addressed` → note the outcome for `report.md` and continue to Step 5a.
- Some `still-open` → ask **once**, listing them with what the evidence did say ("the Halcyon repo shows Kafka but nothing about Kafka Streams"): **Fill** → `onboarding.md` Branch 3 (write, validate, return here and re-run Step 4.5 for the touched entries) or **Proceed** → record the accepted gaps for `report.md` and continue.
- Variants: this question was already asked in main before fan-out (`variants.md`); a variant sub-agent never asks, it records.

---

## Step 5a — Plan (`tailored.yaml`, before any LaTeX)

Content decisions happen here and are written to `<dir>/tailored.yaml` immediately, headed by `# generated by resume-generator; edit knowledge.yaml, not this file`. The plan is the knowledge view that will be rendered plus one decision per entry. Trimming later (Step 7) edits this plan and re-renders; it never edits LaTeX by hand.

1. **Sentinels are absent**: any value matching `<[A-Z][A-Za-z0-9_]*>` (the gate's `OPTIONAL_PLACEHOLDER=` lines) is omitted; an entry whose key field (name/title/degree) is a sentinel is dropped.
2. **Score** every entry in `experience`, `projects`, `education`, `teaching`, `certifications`, `publications`, `events`, `awards`, `interests` for this posting: `relevance: 3` (matches a required skill or the domain via `tags`, `technologies`, or text), `2` (matches a preferred item), `1` (neutral), `0` (off-topic: a Photoshop teaching gig on a backend SWE resume). Without a posting every entry scores `1`. `pin: true` entries are always kept.
3. **Decide** per entry: `keep: true|false`, `reason:` (one line: "required: Kubernetes", "off-topic", "trimmed for page budget"), and `order:` within its section (most recent first by ISO `start`/`end`, else parsed `years`; deep-dive citations travel with their achievement lines).
4. **Section order** by relevance: experience before projects for senior roles; projects and education first for entry-level. Without a posting: keep everything, most recent first.
5. **Page budget**: `page_limit` from the yaml, else 1 for templates 1/2/6 (2 for template 2 when the yaml shows more than 8 years of experience: pass that number to `qa-gate.sh --experience-years` later) and 2 for 3/4/5. Estimate before rendering: a bullet ≈ 1 line at ~95 characters (templates 1/2/6) or ~80 (3/4/5); an entry header ≈ 2 lines; a section heading ≈ 2 lines; ≈ 52 lines per page. Over the estimate → set `keep: false`, lowest `relevance` first, in this order: oldest projects, oldest experience bullets (keep at least 2 per kept role), optional sections (interests, awards, events). Record `budget: {pages: N, estimated_lines: M}`.
6. **Coverage matrix** (posting only), one row per required or preferred item: `requirement`, `status: covered|partial|missing`, `where` (section + entry or Skills). `score = covered / total`; it measures keyword coverage, not hiring odds, and every report says so. The top-3 required items must map to kept content that renders in the first half of page 1; if one does not, raise that entry's `order` or set `keep: true` now, before rendering.
7. **Wording** is decided in the plan too: rephrase kept achievements in the posting's vocabulary, lead `profile` with the role's top requirements. Reordering and rephrasing are fine; never invent facts, numbers, employers, or dates.

Plan shape (the yaml sections keep their `knowledge.yaml` keys; these fields are added):

```yaml
# generated by resume-generator; edit knowledge.yaml, not this file
generated_at: 2026-09-03
template: 2
budget: {pages: 1, estimated_lines: 49}
coverage:
  score: 0.8
  rows:
    - {requirement: "Python, 5+ years", status: covered, where: "Experience: Halcyon; Skills"}
    - {requirement: "Kafka Streams", status: missing, where: ""}
experience:
  - title: Senior Engineer
    company: Halcyon
    relevance: 3
    keep: true
    reason: "required: Python, Kubernetes"
    order: 1
    achievements:
      - "Cut p99 latency 40% by moving the ingest path to Kafka (evidence: halcyon/docs/postmortem.md:12)"
```

---

## Step 5b — Render (`resume.tex` from the plan)

Open `templates/<N>/template.tex` as the structural reference (you already have `NOTES.md`). Write `<dir>/resume.tex` from `tailored.yaml`, rendering only `keep: true` entries in plan order:

1. **First line** is the compiler marker: copy `%!TEX program = xelatex` from `template.tex` when present, else write `%!TEX program = pdflatex`. `build.sh` and `lint-tex.sh` read it.
2. Mirror the preamble (`\documentclass`, packages, custom commands). For pdflatex templates add `\usepackage[T1]{fontenc}` when the text has non-ASCII characters.
3. **Drop every sample**: names, employers, lorem ipsum, the moderncv cover-letter block (unless `cover-letter.md` says otherwise), `\photo` unless `photo:` is set, date-of-birth/nationality rows unless set, sample referees (use `references:` from the plan, else "References available on request" or omit the section).
4. **Headings**: when `language:` is not `en`, read `<SKILL_ROOT>/assets/section-headings.yaml` and use those headings; body text stays as written. For pdflatex templates add `\usepackage[<italian|german|french|spanish>]{babel}`.
5. **LaTeX escaping** of every value taken from the plan: `&`→`\&`, `%`→`\%`, `$`→`\$`, `#`→`\#`, `_`→`\_`, `{`→`\{`, `}`→`\}`, `~`→`\textasciitilde{}`, `^`→`\textasciicircum{}`. Inside `\href{URL}{text}` the URL stays raw; the display text is escaped.
6. **Links**: always `\href{<url>}{<display>}`. Templates 1 and 2 load `hyperref` in the preamble, 3 and 4 in the class, 5 and 6 in `structure.tex`; never load it twice.
7. The template's preset below decides layout emphasis, never content; content was decided in 5a.

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

### 6b. Coverage check on the render (only with a posting)

The matrix was built in Step 5a. Verify it survived rendering: every `where` cell points at text that is actually in `resume.tex`; the top-3 required items sit in the first half of page 1 (by position in the source now, confirmed on the PNG in Step 7.5); achievements are quantified where the plan has numbers; nothing off-topic slipped in. A miss is a plan fix (Step 5a: raise `order`, flip `keep`) followed by a re-render, not a hand edit of LaTeX. Re-run 6a after any re-render.

---

## Step 7 — Build + QA gate (scripted)

Skip in source-only mode (say so; the user compiles elsewhere, e.g. Overleaf).

```bash
bash <SKILL_ROOT>/tests/qa-gate.sh <dir> --template <N> [--page-limit <L>] [--experience-years <Y>] [--allow "<string>"]...
```

Pass `--page-limit` when the yaml sets `page_limit`, `--experience-years` for template 2 (the number from Step 5a.5), and `--allow` for each `LEAK=` string already verified to come from `knowledge.yaml` (an alma mater such as MIT). The script runs `build.sh` (latexmk when available, else two passes), echoes its keys (`COMPILER`, `PDF`, `PAGES`, `OVERFULL`, `TEXT_EXTRACT`, `PLACEHOLDER_LEAK`, `UNRESOLVED_REFS`, `LEAK=`, `PNG`), then applies the budget and leak rules. Aux files are cleaned; `resume.log` stays.

| Exit | STATUS | Action |
|---|---|---|
| 0 | `pass` | Step 7.5 |
| 1 | `fail` | per `FAIL=` line: `pages:<n>/<budget>` → Step 5a, set `keep: false` on the next lowest-relevance item, re-render, re-run; one trim cycle, then report the overrun. `placeholder-leak:` / `leak:<string>` → fix the plan value or the render (a genuine string → add `--allow`), re-run. `unresolved-refs:` → re-run once (second pass), then fix the reference |
| 2 | `no-compiler` | source-only was decided at entry; otherwise back to Step 1.5 |
| 5 | `compile-failed` | classify flow below |

`WARN=` lines never block; they go to `report.md`: `overfull:<n>` above 5 → shorten long unbreakable tokens (URLs, comma-less tech lists) if a rebuild happens anyway; `text-extract:empty` → tell the user ATS parsers will see nothing; `text-extract:unavailable` → leak and reference checks were not measured (no `pdftotext`).

### Compile failed (exit 5)

```bash
bash <SKILL_ROOT>/tests/classify-log.sh <dir>/resume.log
```

| Exit | Meaning | Action |
|---|---|---|
| 0 | `CLASS=`, `LINE=`, `TOKEN=`, `HINT=` | apply the hinted fix inline: a missing asset → Step 4; a macro/arity/escape problem → edit `resume.tex` at `LINE`; a content problem (an unescaped value) → fix it in the plan too so a re-render keeps it. Re-run `qa-gate.sh` |
| 1 | `CLASS=unknown` | **dispatch a sub-agent** to diagnose (the log is verbose; keep it out of main): `subagent_type: general-purpose`, `model: sonnet`, `description: Diagnose LaTeX compile error`; prompt with the paths to `resume.log` and `resume.tex`, asking for the line number and replacement only, not the log content. Apply, re-run |
| 5 | no `!` line | the failure is outside LaTeX (timeout, disk, PATH); show the stderr tail and stop |

One retry after either path; then surface the diagnosis and the `!` lines to the user.

---

## Step 7.5 — Visual check

View `PNG=` once with the image reader: name header intact, no empty section, no orphan heading at a page bottom, columns balanced (template 3), nothing pushed off the page, the top-3 requirements visible in the upper half. One fix-and-rebuild cycle (plan fix → re-render → Step 7), then report what remains.

---

## Step 8 — Persist + report

Write into `<dir>`:

- `tailored.yaml`: already written in Step 5a; update it now with the final `keep` decisions after any trim, `rendered_at:`, and a `qa:` block (`pages`, `budget`, `overfull`, `leaks`, `warnings`).
- `posting.json`: the structured analysis so refresh, rebuild, and letter-only modes never re-fetch:
  ```json
  {
    "source": "<url | file path | pasted>",
    "fetched_at": "2026-09-03",
    "title": "Backend SWE", "company": "Stripe", "location": "Remote (EU)",
    "domain": "payments infrastructure",
    "required": ["Python", "Kubernetes", "Kafka Streams"],
    "preferred": ["Go"],
    "years": "5+",
    "expects": {"publications": false, "referees": false, "photo": false},
    "classification": "industry", "confidence": "high",
    "template": 2, "template_reason": "industry backend role"
  }
  ```
  No posting → write it with `"source": "none"` and the template fields only.
- `report.md`: template + reason; posting (title, company, source); coverage matrix and score with its caveat; per entry `keep`/`reason` (what was dropped, reordered, rephrased); deep-dive deltas with citations, per-entry `cache: hit|miss|failed`, and warnings; deferred gaps and their outcome (`addressed` / waived); `WARN=` lines and QA numbers (pages, budget, overfull, leaks); soft-gate gaps the user waived.

Append one row to `<cwd>/outputs/index.md` (create it with the header row when missing):

```
| Date | Slug | Company | Role | Template | Pages | PDF | Posting |
|---|---|---|---|---|---|---|---|
| 2026-09-02 | stripe-backend-swe-2026 | Stripe | Backend SWE | 2 | 1 | outputs/stripe-backend-swe-2026/resume.pdf | https://… |
```

Then report to the user, tightly: the PDF path (clickable), template + reason, coverage score with its caveat, warnings, the `report.md` path. Never write anything back to `<cwd>/knowledge.yaml`.

---

## Step 9 — Cover letter (only when requested)

`--cover-letter` or "and a cover letter" → **read `<SKILL_ROOT>/cover-letter.md`** and follow it. It reuses the posting analysis, the coverage matrix, and `<dir>`. In letter-only mode this is the only step that runs; `cover-letter.md` resolves `<dir>` from the slug.

---

## Critical rules

- Never hardcode personal data; every value comes from `knowledge.yaml` (or a deep-dive citation of the user's own evidence).
- Never invent facts during tailoring. Reordering and rephrasing OK; fabricating achievements not OK.
- Copy class/style/font files into `<dir>` before compiling; compile only there, never in the skill folder.
- The compiler comes from the `%!TEX program` marker (templates 3 and 5 are xelatex); `build.sh` reads it, so keep it on line 1 of `resume.tex`.
- Scripts run from `<SKILL_ROOT>/tests/`; never copy them into `<cwd>`.
- The tailored view goes to `<dir>/tailored.yaml`; `<cwd>/knowledge.yaml` is never modified here.
- Output slugs are lowercase kebab-case; collisions get `-v2`, never silent overwrites.
- `tailored.yaml` is the plan and is written **before** `resume.tex`. Content decisions (keep, order, trim, wording) happen in the plan; LaTeX is rendered from it. Trim in the plan, never by hand in LaTeX.
- Step 7 calls `qa-gate.sh`, never `build.sh` directly; the budget and leak arithmetic live in the script.
- `<cwd>/.resume-cache/evidence/` (deep-dive facts with citations) is the only write outside `<dir>`; `posting.json` stays inside `<dir>`.

## Common mistakes

| Mistake | Fix |
|---|---|
| `.cls`/`.sty`/fonts not copied to `<dir>` | Re-run Step 4 |
| pdflatex used on template 3 or 5 | Keep the `%!TEX program = xelatex` line; `build.sh` honours it |
| Missing `Fonts/` (3) or `fonts/` (5) | Copy the whole directory, preserve case |
| Missing `*.sty` for template 4 | Copy every `*.sty` from `templates/4/` |
| Sample name or `<PLACEHOLDER>` in the PDF | Lint (6a) and `build.sh` leak checks catch it; fix the source |
| `\photo{pictures/picture}` left in template 4 | Only emit `\photo` when `photo:` is set, pointing at the copied file |
| Resume over the page budget | Flip `keep: false` in the plan (Step 5a.5) and re-render; don't shrink fonts below the template's default |
| `&` in a company name | `\&`; lint flags it |
| Stale yaml data | Re-read `<cwd>/knowledge.yaml` |
| Overwrote a previous output | Collisions get `-v2`; overwrite only after asking |
| Trimming for the page budget by deleting LaTeX lines | Flip `keep: false` in `tailored.yaml` (Step 5a) and re-render |
| Sending every compile error to a sub-agent | `classify-log.sh` first; only `CLASS=unknown` needs the sub-agent |
| Re-fetching a posting for "redo the Stripe one" | Refresh mode reads `outputs/<slug>/posting.json` |
| Dispatching deep-dive sub-agents when `.resume-cache/` is fresh | Phase 1 freshness check first (`find -newer`) |
