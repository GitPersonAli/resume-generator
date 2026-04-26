# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this repo is

A **Claude Code plugin** containing a single model-invoked skill, `resume-generator`. The plugin generates tailored LaTeX resumes + PDFs from a `knowledge.yaml` placed in the user's CWD.

Layout follows the Claude Code plugin convention:

```
<repo>/
├── .claude-plugin/plugin.json     # plugin manifest
└── skills/resume-generator/        # the skill (SKILL.md + assets)
```

The skill itself is read-only from the user's perspective. All generated outputs land in `<user-cwd>/outputs/<role-slug>/`, never inside the plugin folder.

## Architecture — the three-doc state machine

Control flows between three markdown files inside `skills/resume-generator/`, not code:

1. **`SKILL.md`** — entry, gate, dispatch. Checks for `<cwd>/knowledge.yaml`, validates required fields (`name`, `email`, ≥1 `education`, ≥1 of `experience`/`projects`), runs the role-aware soft gate when a job posting is supplied, then dispatches to one of the next two docs. Also intercepts explicit "bootstrap from dir(s)" requests and routes them to onboarding Branch 1c regardless of yaml state.
2. **`onboarding.md`** — loaded only when the gate fails (or the user explicitly asks to bootstrap). Branches: 1a blank-template copy, 1b import from existing resume (PDF/tex/URL/image via sub-agent), **1c bootstrap from work directories (parallel sub-agents per dir, drafts entries with `evidence:` pointers)**, 1d fallback, 2 mid-fill repair, 3 targeted fill for role gaps.
3. **`generation.md`** — loaded only when the gate passes. Nine steps: template resolve → preflight → posting analysis → output dir → asset copy → **deep-dive on relevant `evidence:` (parallel sub-agents, only if a posting is in context)** → `resume.tex` build → inline LaTeX+content review → compile (twice).

Editing any one of these docs changes runtime behavior. Read all three before structural edits — they reference each other by section name. The DOT graph in `SKILL.md` is the source of truth for control flow; keep it in sync with prose changes.

`<SKILL_ROOT>` referenced throughout the docs resolves at runtime to the directory containing `SKILL.md` — i.e. `skills/resume-generator/`. All template/asset/test paths are relative to that root.

### `evidence:` convention (deep-dive pointers)

Any entry under `experience`, `projects`, `education`, `teaching`, `certifications`, `events`, etc. in `knowledge.yaml` may carry an optional `evidence:` list — local paths or URLs that point to richer raw material (a code repo, a project README, a postmortem, a thesis PDF). Two flows consume these:

- **Onboarding Branch 1c** populates `evidence:` automatically when bootstrapping from a work dir, so the pointer stays reproducible.
- **Generation Step 4.5** dispatches one parallel sub-agent per high-relevance entry to re-read the `evidence:` and return sharpened achievements/quantifications tailored to the active job posting. Caps at 5 sub-agents per generation pass to bound fan-out. Deltas are merged into the in-memory yaml view only — never written back to `<cwd>/knowledge.yaml`.

`evidence:` are READ-ONLY pointers. Nothing in the skill writes to those locations.

## Templates (`skills/resume-generator/templates/<N>/`)

Six LaTeX templates, each a self-contained source folder. Compiler is fixed per template:

| N | Name | Compiler | Asset notes |
|---|---|---|---|
| 1 | Classic Academic | pdflatex | `res.cls` |
| 2 | Modern Professional (default) | pdflatex | `resume.cls` |
| 3 | Freeman CV | **xelatex** | `FreemanCV.cls` + `Fonts/` (case matters) |
| 4 | ModernCV | pdflatex | `moderncv.cls` + many `*.sty` + `pictures/` |
| 5 | Wilson | **xelatex** | `structure.tex` + `fonts/` |
| 6 | Cies | pdflatex | `structure.tex` |

Each template's `template.tex` is the structural reference + smoke-compile target. Generation never edits `template.tex` directly — it copies all sibling assets to the output dir, then writes a fresh `resume.tex` populated from `knowledge.yaml`.

Mapping rules + tailoring presets live in `generation.md` Step 5. LaTeX escape rules (especially `&`, `%`, `_`, `#`, `$`) are enforced in the inline review at Step 6a.

## Scripts

```bash
# Smoke-compile every template in an isolated tmpdir. Run after editing any template.
bash skills/resume-generator/tests/compile-all.sh

# LaTeX env check before generation. Detects missing pkgs/fonts via real compile.
bash skills/resume-generator/tests/preflight.sh <N>            # check only
bash skills/resume-generator/tests/preflight.sh <N> install    # check, then auto-install on caller consent
```

`preflight.sh` is invoked from `generation.md` Step 1.5. Stdout is machine-parseable `KEY=value`; stderr is human progress. Exit codes are contract: 0 ok, 1 missing, 2 no-compiler, 3 no-distro, 4 invalid-args, 5 install-failed. Don't change the exit-code table without updating `generation.md` Step 1.5.

Distro auto-detect: presence of `miktex` → MiKTeX, else `tlmgr` → TeX Live, else `unknown` (abort with exit 3).

Both scripts use `cd "$(dirname "$0")/.." && pwd` to find the skill root, so they're robust to where the plugin ends up on disk.

## Sub-agent dispatch rules

The skill is opinionated about when to dispatch and when to inline:

- **Dispatch sub-agent**: parsing source documents (Branch 1b import — PDF/tex/URL/image), fetching+analysing a job posting given as URL or file path, diagnosing a verbose `resume.log` after compile failure, building parallel resume variants in worktrees.
- **Inline (no sub-agent)**: pasted-text job postings (already in main context), inline LaTeX/content reviews of generated `.tex` (main needs the content anyway).

The reasoning everywhere: dispatch only when it isolates raw content from main; otherwise it doubles token cost.

## Critical invariants

- `knowledge.yaml` is read from `<user-cwd>`, never from the skill folder. Outputs go to `<user-cwd>/outputs/<slug>/`, never inside this repo.
- Placeholder sentinel regex is `<[A-Z_]+>`. Required fields holding a sentinel = gate failure.
- Output slugs are lowercase-kebab-case; collision policy is `-v2`/`-v3` suffix, never overwrite.
- Compile twice for cross-references. Templates 3 and 5 are xelatex; the other four are pdflatex — getting this wrong is the most common bug.
- When copying template assets, **preserve directory case** (`Fonts/` vs `fonts/`) — Linux/macOS are case-sensitive.

## Plugin metadata

`.claude-plugin/plugin.json` carries `name`, `description`, `version`, `author`, `repository`. Bump `version` on each release — Claude Code's `/plugin update` only re-fetches when the version changes (or every commit if version is omitted, for git-distributed plugins).

## Editing this plugin

- Behavior changes mostly mean editing one of the three top-level `.md` files inside `skills/resume-generator/`.
- Adding a template: drop folder under `skills/resume-generator/templates/<N>/`, register compiler in `compile-all.sh` and `preflight.sh` (case statement), add a row to the template table in `generation.md` Step 1, add asset-copy row to Step 4.
- After any template edit run `bash skills/resume-generator/tests/compile-all.sh` — must be 6/6 pass before committing (env failures aside; preflight handles those at user runtime).
- For local dev: `claude --plugin-dir .` from the repo root, then `/reload-plugins` after edits.
