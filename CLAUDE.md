# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this repo is

A **Claude Code plugin** containing a single skill, `resume-generator`. It is model-invoked (description triggers) and also user-invocable as `/resume-generator:resume-generator [posting] [--template N] [--cover-letter] [--skip-preflight]`. The plugin generates tailored LaTeX resumes + PDFs (and optional cover letters) from a `knowledge.yaml` placed in the user's CWD.

Layout follows the Claude Code plugin convention:

```
<repo>/
├── .claude-plugin/plugin.json     # plugin manifest (+ marketplace.json: self-hosted marketplace)
├── .github/workflows/ci.yml       # shellcheck, script tests, plugin validate, template compile in TeX Live
└── skills/resume-generator/        # the skill (SKILL.md + sub-docs + assets + templates + tests)
```

The skill itself is read-only from the user's perspective. All generated outputs land in `<user-cwd>/outputs/<role-slug>/`, never inside the plugin folder.

## Architecture — three control docs plus on-demand sub-docs

Control flows between markdown files inside `skills/resume-generator/`, not code:

1. **`SKILL.md`** — entry, gate, dispatch. Parses `$ARGUMENTS`, checks for `<cwd>/knowledge.yaml`, runs `tests/validate-knowledge.sh` (the hard gate: `name`, `email`, ≥1 `education` entry with degree+university, ≥1 `experience` entry with title+company or ≥1 `projects` entry with name; no sentinel in those), runs the role-aware soft gate when a job posting is supplied, then dispatches. Also intercepts explicit "bootstrap from dir(s)" requests and routes them to onboarding Branch 1c regardless of yaml state.
2. **`onboarding.md`** — loaded when the gate fails (or the user asks to bootstrap). Branches: 1a blank-template copy, 1b import from an existing resume (sub-agent), **1c bootstrap from work directories** (parallel sub-agents per dir, drafts entries with `evidence:` + `tags:`), 1d fallback, 2 mid-fill repair, **2b invalid-YAML repair**, 3 targeted fill for role gaps. Every write is followed by the validator.
3. **`generation.md`** — loaded when the gate passes. Steps: template resolve (then read `templates/<N>/NOTES.md`) → preflight → posting analysis → output dir → asset copy → deep-dive (conditional) → `resume.tex` → lint (`tests/lint-tex.sh`) + content review with a coverage matrix → build (`tests/build.sh`) → QA gate (page budget, leaks, PNG look) → persist (`tailored.yaml`, `report.md`, `outputs/index.md` row) → cover letter (optional).

On-demand sub-docs, loaded only when `generation.md` says so: **`deep-dive.md`** (Step 4.5, re-reads `evidence:` pointers via parallel sub-agents), **`variants.md`** (several resumes in one request: no worktree isolation, preflight and every user question resolved in main before fan-out, one `index.md` writer), **`cover-letter.md`** (Step 9).

Editing any of these docs changes runtime behavior. Read them all before structural edits; they reference each other by section name and by script contract. The DOT graph in `SKILL.md` is the source of truth for control flow; keep it in sync with prose changes.

`<SKILL_ROOT>` referenced throughout resolves at runtime to the directory containing `SKILL.md`, i.e. `skills/resume-generator/`. All template/asset/test paths are relative to that root.

### `evidence:` convention (deep-dive pointers)

Any entry under `experience`, `projects`, `education`, `teaching`, `certifications`, `publications`, `events` may carry an optional `evidence:` list of local paths or URLs pointing to richer raw material. Two flows consume these:

- **Onboarding Branch 1c** populates `evidence:` automatically when bootstrapping from a work dir.
- **Generation Step 4.5 / `deep-dive.md`** dispatches one parallel sub-agent per high-relevance entry (cap 5) to re-read the evidence and return `achievements_proposed`, `technologies_to_add`, `citations`, `warnings`. Deltas are merged into the in-memory view and written to `outputs/<slug>/tailored.yaml`, never back to `<cwd>/knowledge.yaml`.

`evidence:` are READ-ONLY pointers. Nothing in the skill writes to those locations, and sub-agents never open secret-looking files (`.env*`, `*.pem`, `*.key`, `id_*`, names containing secret/credential/token/password).

### Schema notes (`assets/knowledge.template.yaml`)

- Placeholder sentinel regex: `<[A-Z][A-Za-z0-9_]*>` (the old `<[A-Z_]+>` missed `<TECH_1>`, `<DEGREE_NAME_E_G_MSc_in_X>`). `tests/validate-knowledge.sh` is the source of truth; optional fields holding a sentinel are reported as `OPTIONAL_PLACEHOLDER=` and treated as absent by the generator.
- Tailoring hints per entry: `tags: []`, `pin: true`, ISO `start`/`end` (display string stays in `years`).
- Output preferences: `language` (headings translated via `assets/section-headings.yaml`), `page_limit`.
- European fields: `date_of_birth`, `nationality`, `photo` (templates 4/5 only). Sections `publications`, `references`, `interests` exist for templates 3/4/5/6.
- `assets/knowledge.example.yaml` is a complete fictional example used by tests; keep it passing the validator.

## Templates (`skills/resume-generator/templates/<N>/`)

Six LaTeX templates, each a self-contained source folder with a `NOTES.md` (macro arities, yaml→LaTeX mapping, gotchas). The compiler is declared by a `%!TEX program = xelatex` magic comment in `template.tex` (absent = pdflatex); `tests/lib.sh` `compiler_for` reads it, and the generator copies the marker to line 1 of `resume.tex` so `build.sh` picks the same compiler.

| N | Name | Compiler | Fit | Asset notes |
|---|---|---|---|---|
| 1 | Classic Graduate (res.cls) | pdflatex | students, new grads, internships | `res.cls`; hyperref added by us |
| 2 | Modern Professional (default) | pdflatex | industry SWE/ML/data/product | `resume.cls`; hyperref added by us |
| 3 | Freeman Academic CV | **xelatex** | research, PhD, faculty; publications + references | `FreemanCV.cls` + `Fonts/` (case matters) |
| 4 | ModernCV (European) | pdflatex | photo/DOB/nationality customary; built-in cover letter | `moderncv.cls` v1.2.0 + `*.sty`; `pictures/` is a sample, never copied |
| 5 | Wilson (UK-style) | **xelatex** | referees, personal profile; finance/consulting | `structure.tex` + `fonts/`; marker added by us |
| 6 | Cies (minimal one page) | pdflatex | clean one-pagers, creative/design | `structure.tex` |

The old labels ("Classic Academic" for 1, "Creative" for 3) were wrong: 3 is the template with Publications/Doctoral Research sections, 1 is a plain graduate resume. Don't reintroduce them.

Each template's `template.tex` is the structural reference + smoke-compile target. Generation never edits `template.tex`; it copies sibling assets (not `template.tex`/`NOTES.md`) to the output dir and writes a fresh `resume.tex`. Licences: every `template.tex` is CC BY-NC-SA (see `templates/LICENSES.md`); the repo's MIT covers only our own files.

## Scripts (`skills/resume-generator/tests/`)

All scripts are bash 3.2-compatible (stock macOS): no `declare -A`, `mapfile`, `readarray`, `|&`; arrays guarded for `set -u`; `timeout` optional. Stdout is machine-parseable `KEY=value`, stderr is human progress. Exit codes are contracts consumed by the docs; don't change them without updating `SKILL.md` / `generation.md`.

| Script | Purpose | Exit codes |
|---|---|---|
| `lib.sh` | shared helpers: `list_templates`, `compiler_for`, `run_with_timeout`, `detect_distro` (miktex/debian/fedora/texlive/unknown), `tex_needs_sudo` | sourced |
| `validate-knowledge.sh <yaml>` | the gate; python3+PyYAML, grep-only fallback | 0 ok, 1 missing, 2 invalid-yaml, 3 not-found, 4 args, 6 no-parser |
| `preflight.sh <N> [install]` | smoke-compile first, then distro detection + install hints; install mode only for MiKTeX/TeX Live | 0 ok, 1 missing (auto-installable), 2 no-compiler, 3 no-distro/manual, 4 args, 5 install-failed |
| `lint-tex.sh <file.tex>` | deterministic lint: escapes, braces, environments, placeholders, sample-data leaks (`leak-strings.txt`), hyperref | 0 ok, 1 errors |
| `build.sh <dir> [--template N] [--compiler X] [--file f.tex] [--no-render]` | latexmk or two passes; `PAGES`, `OVERFULL`, `PLACEHOLDER_LEAK`, `LEAK=`, `UNRESOLVED_REFS`, `TEXT_EXTRACT`, `PNG` | 0 ok, 1 compile-failed, 2 no-compiler, 4 args |
| `compile-all.sh` | smoke-compile every template (discovers `templates/*/template.tex`) | 0 all pass, 1 failures, 2 no compiler |
| `run-tests.sh` | script unit tests with fixtures, no TeX needed | 0/1 |
| `e2e.sh` | manual gate scenarios through `claude -p --plugin-dir .` (needs API access) | 0/1, skips without `claude` |
| `check-version-sync.sh` | plugin.json vs marketplace.json version | 0/1 |

```bash
bash skills/resume-generator/tests/run-tests.sh          # always, before committing
bash skills/resume-generator/tests/compile-all.sh        # after any template edit (needs TeX)
# no TeX installed? use the CI image:
docker run --rm -v "$PWD":/work -w /work texlive/texlive:latest bash skills/resume-generator/tests/compile-all.sh
```

## Sub-agent dispatch rules

- **Dispatch sub-agent**: parsing source documents (Branch 1b import), fetching + analysing a job posting given as URL or file path, walking dirs (Branch 1c, deep-dive), diagnosing a verbose `resume.log`, building parallel variants.
- **Inline (no sub-agent)**: pasted-text job postings, lint/content review of generated `.tex`, everything that needs the user.
- Sub-agents cannot ask the user anything; every decision (template, install consent, gap fill, overwrite) is resolved in main first. Variants never use `isolation: worktree` (gitignored `knowledge.yaml` would be missing and the PDFs would vanish with the worktree).

The reasoning everywhere: dispatch only when it isolates raw content from main; otherwise it doubles token cost.

## Critical invariants

- `knowledge.yaml` is read from `<user-cwd>`, never from the skill folder. Outputs go to `<user-cwd>/outputs/<slug>/`, never inside this repo. Nothing in generation writes to `knowledge.yaml`.
- The gate is the validator script, not an eyeball check. Regex `<[A-Z][A-Za-z0-9_]*>`.
- Output slugs are lowercase-kebab-case; collision policy is `-v2`/`-v3`, overwrite only after asking.
- Compiler comes from the `%!TEX program` marker (3 and 5 = xelatex). `build.sh` compiles twice or via latexmk.
- When copying template assets, preserve directory case (`Fonts/` vs `fonts/`).
- Post-compile QA: page budget (yaml `page_limit`, else 1 for templates 1/2/6, 2 for 3/4/5), zero placeholder/sample leaks, PNG viewed once.

## Plugin metadata

`.claude-plugin/plugin.json` carries `name`, `description`, `version`, `author`, `repository`; `.claude-plugin/marketplace.json` mirrors the version in `metadata.version`. Bump both on each release (`tests/check-version-sync.sh` enforces equality, CI runs it), add a `CHANGELOG.md` entry, and tag `v<version>`. Claude Code's `/plugin update` only re-fetches when the version changes.

## Editing this plugin

- Behavior changes mostly mean editing one of the control docs or sub-docs inside `skills/resume-generator/`.
- Adding a template: drop a folder under `templates/<N>/` with `template.tex` (add `%!TEX program = xelatex` if needed), its assets, and a `NOTES.md`; add rows to `generation.md` Step 1 and Step 4 tables, the README table, and `templates/LICENSES.md`. `compile-all.sh` and `preflight.sh` discover it automatically.
- After any template edit run `compile-all.sh` (or the docker one-liner); must be all-pass before committing.
- After any script edit run `run-tests.sh`; CI also runs shellcheck.
- For local dev: `claude --plugin-dir .` from the repo root, then `/reload-plugins` after edits. `tests/e2e.sh` exercises the gate end to end.
