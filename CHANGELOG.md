# Changelog

## 0.3.0 — 2026-09-02

### Fixed
- Gate: the placeholder regex `<[A-Z_]+>` missed 21 of the shipped template's sentinels (`<TECH_1>`, `<DEGREE_NAME_E_G_MSc_in_X>`, …), so a still-blank `degree` passed the gate and placeholders could leak into the PDF. New regex `<[A-Z][A-Za-z0-9_]*>`, enforced by `tests/validate-knowledge.sh`.
- `preflight.sh` aborted (exit 3) when neither `tlmgr` nor `miktex` was on PATH, before ever trying to compile; working Debian/Fedora/Nix/docker TeX installs were rejected. It now smoke-compiles first and only inspects the distro on failure; OS-packaged TeX gets `apt`/`dnf` hints.
- Scripts required bash ≥ 4 (`declare -A`, `mapfile`) and GNU `timeout`; stock macOS broke. All scripts are bash 3.2-compatible with a `timeout` fallback.
- `compile-all.sh` passed the MiKTeX-only `--enable-installer` flag to every compiler.
- `tlmgr update --self --all` was run before every install; now only on a detected LaTeX release mismatch, and `sudo` is handled explicitly.
- Multi-variant builds used `isolation: worktree`, which drops the gitignored `knowledge.yaml` and deletes the PDFs with the "unchanged" worktree; sub-agents were also expected to ask for install consent, which they cannot. See `variants.md`.
- Invalid YAML had no handling path; onboarding Branch 2b now shows the parse error and proposes the fix.
- Templates 1 and 2 lacked `hyperref` while the generator emitted `\href`; template 4 shipped `lipsum`; template 5 lacked the `%!TEX program = xelatex` marker.
- Template labels were wrong: 3 (Freeman, with Doctoral Research and Publications sections) is the academic CV, 1 (res.cls) is a graduate resume, not "Classic Academic"; nothing was "Creative".
- README claimed MIT for everything; the bundled `template.tex` files are CC BY-NC-SA (`templates/LICENSES.md`).
- Stale `docs/` entry in the SKILL.md asset tree.
- Deep-dive JSON returned `evidence` (citations) next to the yaml's `evidence:` (pointers); renamed to `citations`.

### Added
- Scripts: `validate-knowledge.sh` (deterministic gate), `lint-tex.sh` (escapes, braces, environments, placeholders, sample-data leaks), `build.sh` (latexmk or two passes, page count, overfull count, placeholder/leak scan via pdftotext, page-1 PNG), `lib.sh`, `run-tests.sh` with fixtures, `e2e.sh`, `check-version-sync.sh`; GitHub Actions CI (shellcheck, tests, `claude plugin validate`, template compile in `texlive/texlive`).
- Generation: post-compile QA gate (page budget, zero leaks, visual check), coverage matrix and score against the posting, persisted `tailored.yaml` + `report.md`, `outputs/index.md` application log, overwrite-or-`-v2` prompt on regeneration.
- Schema: `tags`/`pin`, ISO `start`/`end`, `page_limit`, `language` (heading translations for it/de/fr/es), `date_of_birth`/`nationality`/`photo`, `publications`, `references`, `interests`; `assets/knowledge.example.yaml`.
- Per-template `NOTES.md` (macro arities, yaml→LaTeX mapping, gotchas); compiler discovered from the `%!TEX program` marker everywhere.
- Cover letters (`cover-letter.md`, `assets/cover-letter.template.tex`; moderncv's built-in letter for template 4).
- Slash-command arguments: `[posting] [--template N] [--cover-letter] [--skip-preflight]`.
- Job-posting fetch fallback (login walls, JS-only pages → ask for pasted text); LinkedIn import via "Save to PDF"; secret-file exclusions for directory walks and deep-dives.
- `CHANGELOG.md`; version-sync check between `plugin.json` and `marketplace.json`.

## 0.2.1

- `sources:` renamed to `evidence:`; onboarding Branch 1c (bootstrap from directories); deep-dive step; plugin update instructions.

## 0.1.0

- Initial release: six templates, onboarding + generation flow, preflight script.
