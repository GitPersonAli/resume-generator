# Generation — produce a tailored LaTeX resume + PDF

You are reading this because the gate in `SKILL.md` confirmed `knowledge.yaml` is filled (required fields present, no placeholders in required fields, role-aware soft gate either satisfied or explicitly waived by the user).

`<SKILL_ROOT>` below = the directory containing this file.
`<cwd>` = the user's current working directory.

---

## Inputs you should already have

- `knowledge.yaml` content (read once at gate; re-read if it has changed since)
- Job posting summary (if user provided one — already in main context, either pasted or extracted by the job-analyzer sub-agent during the gate)
- Optional: explicit template number from the user

If you don't have the yaml content in context, read `<cwd>/knowledge.yaml` now.

---

## Step 1 — Resolve template

Pick the template number using this order:

1. **User explicitly named one** (e.g. "use template 3", "academic"). Use it. Skip auto-pick.
2. **Job posting available + no explicit choice.** Classify the role inline (no sub-agent — the summary is already in your context). Apply this mapping with confidence assessment:

   | Role signal | Template | Confidence rule |
   |---|---|---|
   | Academic / research / PhD / postdoc / faculty / strong publications focus | 1 (Classic Academic CV) | high if title contains "research"/"PhD"/"postdoc"/"professor" |
   | Industry SWE / ML / data / backend / frontend / product | 2 (Modern Professional, default) | high if industry tech role with no academic signals |
   | Creative / design / UX / UI / brand / motion | 3 (Freeman CV) | medium-to-high if creative-track |
   | European-style application explicitly requested or country expects moderncv | 4 (ModernCV) | low unless explicit |
   | Heavily detailed professional with many sections, finance/consulting | 5 (Wilson Resume) | low unless explicit |
   | Minimal one-page constraint, "clean", "minimalist" | 6 (Cies Resume) | medium if length-constrained |

   - **High/medium confidence** → auto-pick. Tell the user once: "Picked Template N because <one-line reason>. Say so to override."
   - **Low confidence** → ask the user, with default of 2.

3. **No job posting + no explicit choice.** Ask the user. Default to Template 2.

---

## Step 1.5 — Preflight (LaTeX environment check)

Before doing any further work, verify the user's machine can compile the chosen template. This catches missing packages, missing fonts, and missing compilers up front instead of after generation. The check is cross-OS and uses the bundled `template.tex` as the smoke test (no hardcoded package list — the script discovers what's missing by trying to compile).

Skip this step entirely if the user passed `--skip-preflight` in the request, or if a preflight in the current session already returned `STATUS=ok` for this template number.

### How to run

```bash
bash <SKILL_ROOT>/tests/preflight.sh <template-number>
```

Capture both stdout (machine-parseable `KEY=value` lines) and the exit code:

| Exit | STATUS | Meaning | Action |
|---|---|---|---|
| 0 | `ok` | template smoke-compiles | proceed to Step 2 |
| 1 | `missing` | packages/fonts/other gaps detected | see "Missing items" below |
| 2 | `no-compiler` | the required compiler is not on PATH | show `INSTALL_CMD` lines (TeX-distro install URL) and abort |
| 3 | `no-distro` | compiler exists but neither `miktex` nor `tlmgr` on PATH — auto-install impossible | show error, ask user to install missing packages manually, abort |
| 4 | `invalid` | bad arguments — bug in this skill, surface and abort |
| 5 | `install-failed` | install attempted but smoke-compile still fails | surface the post-install log tail, abort |

### Missing items (exit 1) flow

1. Parse the stdout `MISSING_PKG=`, `MISSING_FONT=`, `OTHER_ERROR=`, and `INSTALL_CMD=` lines.
2. Show the user a tight summary:
   > LaTeX environment check found gaps before generating Template `<N>`:
   >
   > Missing packages: `<list>`
   > Missing fonts: `<list>`
   > Other errors: `<list>`
   >
   > I can run these install commands automatically:
   > ```
   > <each INSTALL_CMD line>
   > ```
   > Install? (y/n)
3. Wait for explicit `y`/`yes` from the user. Anything else = no.
4. **On y:** re-invoke preflight in install mode:
   ```bash
   bash <SKILL_ROOT>/tests/preflight.sh <template-number> install
   ```
   Stream stderr (progress lines) so the user sees what's installing. The script re-runs the smoke compile after install:
   - If post-install smoke-compile passes → exit 0, `STATUS=ok` — proceed to Step 2.
   - If still failing → exit 5, `STATUS=install-failed` — surface the diagnosis to the user, ask if they want to continue anyway (last-chance compile may still produce a usable PDF for some failures) or abort.
5. **On n:** abort generation. Tell the user the install commands so they can run them manually, then re-invoke the skill.

### When preflight fails for environmental reasons unrelated to the template

Some failures (e.g. a `figureversions` package version that requires a newer LaTeX format than the user's TeX distribution carries) are not fixable by `<package> install`. The script surfaces these via `OTHER_ERROR=…` with a hint (often "update your TeX distribution"). In those cases the install commands list will start with the distro update command — agreeing to install runs that update first.

---

## Step 2 — Resolve job posting analysis

Already done at the gate.

- If pasted text → analysis was inline; keep using it.
- If URL or file path → sub-agent dispatched at the gate; reuse its return value.
- Don't re-fetch.

If no job posting was given, skip role-tailoring (use yaml as-is, broad framing).

---

## Step 3 — Resolve output directory

Path: `<cwd>/outputs/<role-slug>/`

Slug rules:
- Lowercase kebab-case.
- Include company + role + year when available, e.g. `google-swe-2026`, `iit-ml-research-2026`.
- If only role known: `<role>-<yyyy>`.
- If neither: `general-<template-N>-<yyyy>`.

Collisions: if directory exists with content, append `-v2`, `-v3`, etc. Don't overwrite.

Create the directory.

---

## Step 4 — Copy template assets

Source: `<SKILL_ROOT>/templates/<N>/`
Destination: `<cwd>/outputs/<slug>/`

Copy **everything** in the template's source folder, **except** `template.tex` itself (which becomes `resume.tex` after generation in Step 5). Specifically, copy these per template:

| Template | Files / dirs to copy |
|---|---|
| 1 | `res.cls` |
| 2 | `resume.cls` |
| 3 | `FreemanCV.cls`, `Fonts/` |
| 4 | `moderncv.cls`, all `*.sty`, `pictures/` |
| 5 | `structure.tex`, `fonts/` |
| 6 | `structure.tex` |

Use `cp -r` so subdirectories and font files are preserved verbatim. **Preserve directory case** (`Fonts/` vs `fonts/`) — case matters on Linux/macOS even though Windows is case-insensitive.

---

## Step 4.5 — Deep-dive on relevant `sources:`

Skip this step entirely if **no job posting** was provided — without a target role there's no signal for "which item deserves a deep-dive". Use the YAML achievements/descriptions as-written and proceed to Step 5.

If a job posting IS in context, the generator can sharpen items by re-reading the local `sources:` pointers attached to high-relevance entries.

### Selection — which entries deserve a deep-dive?

For each entry in `experience`, `projects`, `education`, `events` (any section that supports `sources:`), score it:

- **Skip** if the entry has no `sources:` field or the list is empty.
- **Skip** if the entry is clearly off-topic for this posting (e.g. a Photoshop teaching gig on a backend SWE resume).
- **Select** if **both**:
  1. The entry's `technologies` / `description` / domain overlaps the posting's required skills or domain language.
  2. The entry's current `achievements` are thin (≤2 entries, no quantifications, or generic phrasing) — i.e. there's room to improve.

Select at most **5 entries** total per generation pass to bound sub-agent fan-out and total cost. If more than 5 qualify, pick the top 5 by relevance to the posting.

### Dispatch — one sub-agent per selected entry, parallel

For each selected entry, dispatch via `Agent` tool. Send all calls in a **single message** so they run concurrently:

- `subagent_type`: `general-purpose`
- `model`: `sonnet`
- `description`: `Deep-dive: <entry name>`
- `prompt`: must be self-contained. Include:
  - The entry's current YAML block (verbatim — name, description, achievements, technologies, sources)
  - The job posting summary (the analysis from Step 2, not the raw posting)
  - Each path in `sources:` — the agent will use `Read` for files, `Glob`+`Read` for dirs, `WebFetch` for URLs
  - Instructions to:
    - Read the `sources:` (skip files > 200KB, skip binaries, prefer README/docs/top-level code over deep traversal)
    - Resolve `~` to home dir; resolve relative paths against the directory containing `<cwd>/knowledge.yaml`
    - Extract concrete details that align with the posting: quantifications (latency, throughput, user count, $ saved), specific tech used (frameworks, infra, patterns), measurable outcomes
    - Return ONLY a JSON object with these keys (don't paraphrase; be precise):
      ```json
      {
        "entry_name": "<unchanged>",
        "achievements_proposed": ["<sharp quantified line>", "..."],
        "technologies_to_add": ["<tech>", "..."],
        "evidence": ["<one-line citation per claim, with file:line where possible>"],
        "warnings": ["<anything you found that contradicts the YAML — e.g. yaml says 'Python' but repo is all TS>"]
      }
      ```
    - Do not invent: every `achievements_proposed` line must be backed by an `evidence` entry. If a source is unreadable or empty, return empty arrays and a warning.

### Apply — merge proposals back into the working YAML view

When all sub-agents return:

1. For each proposal, merge into the in-memory copy of `knowledge.yaml` (do **not** write back to `<cwd>/knowledge.yaml` — these are tailoring deltas for THIS resume, not durable edits to the user's data):
   - Append `achievements_proposed` to the entry's `achievements` (dedupe — drop any line that's a near-duplicate of an existing one)
   - Union `technologies_to_add` into the entry's `technologies`
2. If any sub-agent returned `warnings`, surface them at the end of generation Step 8 so the user can correct their YAML.
3. If a sub-agent failed (timeout, unreadable sources, returned nothing useful), proceed with the original entry — log the failure in the Step 8 report.

### Failure mode — none of the sources readable

If every dispatch returned empty/error, proceed with the original YAML and surface a single warning in Step 8: `Deep-dive ran but no sources/yielded content. Check that the paths in your knowledge.yaml resolve from <cwd>.`

---

## Step 5 — Generate `resume.tex`

Open `<SKILL_ROOT>/templates/<N>/template.tex` as your structural reference. Build `<cwd>/outputs/<slug>/resume.tex` by:

1. Mirror the template's preamble (`\documentclass`, `\usepackage`, custom commands).
2. Replace the template's example data with values from `knowledge.yaml`.
3. **Tailor for the role** if a job posting is in context:
   - Reorder sections so highest-relevance comes first.
   - Filter `projects[]` to those whose `technologies` overlap the job's required skills.
   - Rephrase achievements to use the posting's domain language (without inventing facts).
   - Adjust `profile` to lead with role-relevant strengths.
4. **LaTeX escaping** — these characters in yaml string values must be escaped in the `.tex` output: `&` → `\&`, `%` → `\%`, `$` → `\$`, `#` → `\#`, `_` → `\_`, `{` → `\{`, `}` → `\}`. The `~` and `^` characters need `\textasciitilde{}` and `\textasciicircum{}`. URLs in `\href{}` arguments are exempt.
5. **Links** — always `\href{<url>}{<display text>}`. Templates already include `\usepackage[hidelinks]{hyperref}` (verify in the template file; add if missing).

### Data mapping reference (Template 2 — default)

```latex
% Header
\name{<name>}
\address{<location>}
\address{<email> \addressSep \ <phone>}
\address{\href{<linkedin-url>}{<linkedin-display>}}

% Education
\textbf{<university>} \hfill \textit{<years>} \\
<degree> \\
<details joined with line breaks>

% Experience
\begin{rSubsection}{<company>}{<years>}{<title>}{<company_location>}
    \item <achievement>
\end{rSubsection}

% Projects
\textbf{<project name>} \\
<technologies joined with commas> \\
<description>
```

Other templates have their own conventions — read `template.tex` in the chosen template folder before generating to learn the exact macros.

### Tailoring presets

| Template | Emphasis |
|---|---|
| 1 (Academic) | Thesis details, research interests, teaching, course grades, collaborations |
| 2 (Industry) | Quantified achievements, project tech stacks, recent experience first |
| 3 (Creative) | Visual hierarchy, design-tooling skills, portfolio links front-and-center |
| 4 (ModernCV) | European conventions: include date of birth, nationality, photo if applicable |
| 5 (Wilson) | Detailed, multi-section; certifications and awards prominent |
| 6 (Cies) | Single page, ruthless filtering — only top-N most relevant items per section |

---

## Step 6 — Inline reviews (sequential, in main)

Both reviews happen inline. Do not dispatch sub-agents — both you (main) and the sub-agent would need the full `.tex` content, so dispatching wastes tokens.

### 6a. LaTeX syntax review

Self-check the generated `resume.tex` for:
- Unescaped `&`, `%`, `#`, `_`, `$` outside of `\href` and math mode.
- Mismatched `{` / `}` braces.
- Unclosed environments (`\begin{X}` without matching `\end{X}`).
- Stale `<PLACEHOLDER>` literals from the template that you forgot to replace.
- Missing `\usepackage[hidelinks]{hyperref}` if you used `\href`.
- Font commands referencing fonts not in the bundled font directory.

Fix any issue found before moving on.

### 6b. Content review (only if job posting in context)

Self-check the resume against the job posting:
- Are the top-3 required skills in the posting actually visible on the resume?
- Are sections ordered so the recruiter sees relevance first?
- Are achievements quantified (numbers, percentages, durations) where the yaml has them?
- Did you drop high-impact items from yaml that match the posting?
- Did you accidentally include items from yaml that look misaligned with the role (e.g. a Photoshop teaching gig on a backend SWE resume)?

Apply edits.

---

## Step 7 — Compile

Working directory: `<cwd>/outputs/<slug>/`
Compiler depends on template:

| Template | Compiler |
|---|---|
| 1, 2, 4, 6 | `pdflatex` |
| 3, 5 | `xelatex` |

Run twice for cross-references:

```bash
cd <cwd>/outputs/<slug> && <compiler> -interaction=nonstopmode resume.tex && <compiler> -interaction=nonstopmode resume.tex
```

If compilation fails:

1. Show the user the last ~20 lines of `resume.log`.
2. **Dispatch a sub-agent** to diagnose. The `.log` is verbose; isolating it from main saves tokens.
   - `subagent_type`: `general-purpose`
   - `model`: `sonnet`
   - `description`: `Diagnose LaTeX compile error`
   - `prompt`: include the path to `resume.log`, the path to `resume.tex`, and ask for a diagnosis + concrete fix (line number + replacement). Tell the agent to read both files and return only the fix, not the log content.
3. Apply the fix and retry compile (one retry max). If second compile still fails, surface the failure to the user with the agent's diagnosis.

---

## Step 8 — Report to user

When the PDF is produced, report:
- Path to PDF (clickable markdown link).
- Template used + reason if auto-picked.
- Reviewer summary (what you adjusted in steps 6a/6b).
- Any soft warnings carried forward (role-aware gaps the user chose to proceed past during onboarding Branch 3).

Keep the report tight.

---

## Variants — multiple resumes in one request

If the user wants several variants in one go (e.g. "build me Industry + Academic versions" or "tailor for these three job postings"), dispatch parallel sub-agents.

For each variant:
- `subagent_type`: `general-purpose`
- `model`: inherit
- `isolation`: `worktree`
- `description`: short variant name (e.g. "build google-swe-2026 variant")
- `prompt`: must be self-contained — include the cwd, the variant params (template number, job posting summary, output slug), the path to `<cwd>/knowledge.yaml`, the path to `<SKILL_ROOT>`, and instructions to follow this `generation.md` end-to-end. Return: PDF path + brief summary.

Send all variant `Agent` calls in a single message so they run concurrently.

---

## Critical rules

- Never hardcode personal data — pull every value from `knowledge.yaml`.
- Never invent facts during tailoring. Reordering and rephrasing OK; fabricating achievements not OK.
- Always copy class/style/font files into the output dir before compiling.
- Templates 3 and 5 are xelatex; the rest pdflatex.
- Compile twice for cross-references.
- Output slug: lowercase kebab-case.
- Don't compile inside the skill folder — only in the user's `<cwd>/outputs/<slug>/`.

## Common mistakes

| Mistake | Fix |
|---|---|
| `.cls` not copied to output dir | Re-run Step 4 |
| Used pdflatex on Template 3 or 5 | Use xelatex |
| Missing `Fonts/` for Template 3 | Copy whole `Fonts/` directory, preserve case |
| Missing `*.sty` files for Template 4 | Copy every `*.sty` from `<SKILL_ROOT>/templates/4/` |
| `<PLACEHOLDER>` text leaked into PDF | Step 6a missed it — re-check before compile |
| Stale yaml data in resume | Re-read `<cwd>/knowledge.yaml` |
| Output slug uses spaces or capitals | Use lowercase-kebab-case |
| `&` in company name renders as alignment break | Escape as `\&` |
