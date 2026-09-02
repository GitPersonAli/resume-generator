# resume-generator

A [Claude Code](https://claude.com/claude-code) skill that generates tailored LaTeX resumes (and PDFs) from a single `knowledge.yaml` data file. Six bundled templates: graduate, industry, academic, European, UK-style, and minimal one-page. Tailors content to any job posting (URL, file, or pasted text), checks the result before it reaches you, and can write the matching cover letter.

Model-invoked, so you can just talk:

```text
> generate a resume tailored to this posting: <url>
> tailor my resume for a backend SWE role at Stripe, and write a cover letter
> import my old resume.pdf and set up a knowledge.yaml first
> build a knowledge.yaml from ~/work/projects
```

Or call it directly as a slash command:

```text
/resume-generator:resume-generator https://jobs.example.com/123 --template 2 --cover-letter
```

Claude routes through onboarding (if `knowledge.yaml` is missing, invalid, or partially filled) and generation (when ready), lints the LaTeX, compiles, checks page count and leaks, looks at page 1, and leaves everything in `<cwd>/outputs/<role-slug>/`:

```
outputs/stripe-backend-swe-2026/
├── resume.pdf        # the deliverable
├── resume.tex        # regenerate by hand if you like
├── report.md         # template choice, coverage matrix vs the posting, what was cut, QA numbers
├── tailored.yaml     # the exact data that was rendered (never written back to knowledge.yaml)
├── cover-letter.pdf  # when requested
└── resume-p1.png     # page-1 render used for the visual check
outputs/index.md      # one row per application you generated
```

## Install

This repo is structured as both a **Claude Code plugin** and its own **plugin marketplace** (the `.claude-plugin/marketplace.json` lets `/plugin marketplace add` resolve directly against this repo). Pick the install path that matches your tool:

### Option 1 — Claude Code (recommended)

**From your terminal** (no Claude Code session needed):

```bash
claude plugin marketplace add GitPersonAli/resume-generator
claude plugin install resume-generator@gitpersonali
```

Or **inside an already-running Claude Code session**, type the same as slash commands at the prompt:

```
/plugin marketplace add GitPersonAli/resume-generator
/plugin install resume-generator@gitpersonali
/reload-plugins
```

(`/reload-plugins` is only needed in-session to activate without restarting; the terminal form picks up automatically on next session start.)

#### Updating an installed plugin

Third-party marketplaces have auto-update **disabled** by default. To pull the latest:

In-session:

```
/plugin marketplace update gitpersonali
/plugin update resume-generator@gitpersonali
/reload-plugins
```

From terminal:

```bash
claude plugin marketplace update gitpersonali
```

Then start a fresh `claude` session. To enable auto-update permanently: `/plugin` → **Marketplaces** tab → select `gitpersonali` → **Enable auto-update**. Verify the version under `/plugin` → **Installed**.

### Option 2 — Standalone skill (no plugin layer)

Copy just the inner skill folder into your user-level skills dir:

```bash
# Linux / macOS
git clone https://github.com/GitPersonAli/resume-generator /tmp/rg \
  && cp -r /tmp/rg/skills/resume-generator ~/.claude/skills/ \
  && rm -rf /tmp/rg
```

```powershell
# Windows (PowerShell)
git clone https://github.com/GitPersonAli/resume-generator $env:TEMP\rg
Copy-Item -Recurse $env:TEMP\rg\skills\resume-generator $env:USERPROFILE\.claude\skills\
Remove-Item -Recurse -Force $env:TEMP\rg
```

Restart Claude Code; the skill is auto-discovered and invocable as `/resume-generator`.

### Option 3 — Local development mode

```bash
git clone https://github.com/GitPersonAli/resume-generator
cd resume-generator
claude --plugin-dir .
```

`/reload-plugins` after edits, no restart needed.

## Requirements

- **LaTeX**: MiKTeX (Windows/macOS/Linux) or TeX Live (Linux/macOS, including the Debian/Fedora packages). Both ship `pdflatex` and `xelatex`. `latexmk` is used when present.
- **bash** 3.2 or newer: stock macOS works; on Windows use Git Bash or WSL.
- **python3 with PyYAML** (recommended): powers the deterministic `knowledge.yaml` check. Without it Claude falls back to reading the file itself.
- **poppler-utils** (optional: `pdftotext`, `pdfinfo`, `pdftoppm`): enables the leak/ATS text check and the page-1 preview.

Before generating, the skill runs `preflight.sh`: it smoke-compiles the chosen template, and if packages or fonts are missing it offers to install them through your distro (`miktex packages install …`, `tlmgr install …`) or prints the `apt`/`dnf` commands for OS-packaged TeX.

## Templates

| # | Style | Best for | Compiler |
|---|---|---|---|
| 1 | Classic Graduate | students, new grads, internships, first jobs | pdflatex |
| 2 | Modern Professional (default) | industry SWE, ML, data, product | pdflatex |
| 3 | Freeman Academic CV | research, PhD, postdoc, faculty; publications and references | xelatex |
| 4 | ModernCV | continental-European applications (photo, date of birth, nationality); built-in cover letter | pdflatex |
| 5 | Wilson | UK-style CVs with referees; finance, consulting, senior engineering | xelatex |
| 6 | Cies | minimal one page; creative/design/UX with portfolio links | pdflatex |

With a job posting, Claude classifies the role and auto-picks the template; override with "use template 3" or `--template 3`.

## knowledge.yaml

One file, your data, git-ignored. `skills/resume-generator/assets/knowledge.template.yaml` is the blank template; `knowledge.example.yaml` next to it is a complete fictional example. Beyond the basics you can add:

- `tags:` and `pin: true` per entry to steer tailoring; ISO `start`/`end` dates for reliable ordering
- `evidence:` pointers (repos, docs, PDFs) that Claude re-reads for sharper, quantified bullets when a posting is in context
- `publications`, `references`, `interests` for the academic/European/UK templates
- `language: it|de|fr|es` for translated section headings, `page_limit` to override the page budget

Check it any time:

```bash
bash skills/resume-generator/tests/validate-knowledge.sh knowledge.yaml
```

## Repo structure

```
resume-generator/                          # plugin root
├── .claude-plugin/                        # plugin.json + marketplace.json
├── .github/workflows/ci.yml               # shellcheck, script tests, plugin validate, TeX Live compile
├── README.md  LICENSE  CHANGELOG.md  CLAUDE.md
└── skills/
    └── resume-generator/                  # the skill itself
        ├── SKILL.md                       # entry / gate / dispatch
        ├── onboarding.md                  # knowledge.yaml setup and repair
        ├── generation.md                  # tex generation, lint, build, QA, report
        ├── deep-dive.md  variants.md  cover-letter.md   # loaded on demand
        ├── assets/                        # knowledge template + example, heading translations, cover-letter template
        ├── templates/<1-6>/               # LaTeX sources, each with NOTES.md; LICENSES.md
        └── tests/                         # validate-knowledge, preflight, lint-tex, build, compile-all, run-tests, e2e
```

See [CLAUDE.md](CLAUDE.md) for architecture details.

## Development

```bash
bash skills/resume-generator/tests/run-tests.sh            # script tests, no TeX needed
bash skills/resume-generator/tests/compile-all.sh          # smoke-compile all six templates (needs TeX)
docker run --rm -v "$PWD":/work -w /work texlive/texlive:latest \
  bash skills/resume-generator/tests/compile-all.sh        # same, without a local TeX
bash skills/resume-generator/tests/e2e.sh                  # gate scenarios through `claude -p` (needs API access)
claude plugin validate .
```

When iterating on the skill prompts, run Claude Code with `claude --plugin-dir .` and `/reload-plugins` after each edit.

## Privacy

The skill operates entirely locally. `knowledge.yaml` (your personal data) and `outputs/` are git-ignored and never leave your machine. Directory walks and `evidence:` reads skip secret-looking files (`.env`, keys, credentials).

## License

The skill's own code and docs are MIT (see [LICENSE](LICENSE)). The bundled LaTeX templates are third-party work under their own licences, mostly **CC BY-NC-SA** from LaTeXTemplates.com; see [templates/LICENSES.md](skills/resume-generator/templates/LICENSES.md) before using the output commercially.

## Credits

LaTeX templates adapted from public sources (res.cls, Trey Hunner's resume.cls, FreemanCV, moderncv, Wilson, Cies). Original notices preserved per template under `skills/resume-generator/templates/<N>/`.
