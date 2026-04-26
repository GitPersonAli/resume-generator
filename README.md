# resume-generator

A [Claude Code](https://claude.com/claude-code) skill that generates tailored LaTeX resumes (and PDFs) from a single `knowledge.yaml` data file. Six bundled templates spanning academic, industry, creative, European, detailed, and minimal styles. Tailors content to any job posting (URL, file, or pasted text) you provide.

Model-invoked — no slash command. Just talk:

```text
> generate a resume tailored to this posting: <url>
> tailor my resume for a backend SWE role at Stripe
> import my old resume.pdf and set up a knowledge.yaml first
```

Claude routes through onboarding (if `knowledge.yaml` is missing or partially filled) and generation (when ready), runs an inline LaTeX + content review, then compiles to PDF in `<cwd>/outputs/<role-slug>/`.

## Install

This repo is structured as both a **Claude Code plugin** and its own **plugin marketplace** (the `.claude-plugin/marketplace.json` lets `/plugin marketplace add` resolve directly against this repo). Pick the install path that matches your tool:

### Option 1 — Claude Code (recommended)

Inside any Claude Code session:

```text
> /plugin marketplace add GitPersonAli/resume-generator
> /plugin install resume-generator@gitpersonali
> /reload-plugins
```

That's three commands: register the marketplace, install the plugin, activate it without restarting. The skill is then available in every session.

To update later: `/plugin marketplace update gitpersonali` then `/plugin update`.

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

Restart Claude Code; the skill is auto-discovered. No plugin namespace prefix — invoke directly.

### Option 3 — Local development mode

For iterating on the skill itself:

```bash
git clone https://github.com/GitPersonAli/resume-generator
cd resume-generator
claude --plugin-dir .
```

`/reload-plugins` after edits — no restart needed.

## Requirements

- **LaTeX**: MiKTeX (Win/macOS/Linux) or TeX Live (Linux/macOS). Both ship `pdflatex` and `xelatex`.
- **bash**: Git Bash or WSL on Windows. Used by `preflight.sh` and `compile-all.sh`.

The skill runs `preflight.sh` before generating — detects missing packages/fonts and offers to auto-install via your distro (`miktex packages install …` or `tlmgr install …`).

## Templates

| # | Style | Best for | Compiler |
|---|---|---|---|
| 1 | Classic Academic CV | research, PhD, postdoc, faculty | pdflatex |
| 2 | Modern Professional (default) | industry SWE, ML, data, product | pdflatex |
| 3 | Freeman CV | creative, design, UX | xelatex |
| 4 | ModernCV | European-style applications | pdflatex |
| 5 | Wilson Resume | finance, consulting, multi-section | xelatex |
| 6 | Cies Resume | minimal, single-page | pdflatex |

When you provide a job posting, Claude classifies the role and auto-picks the template (you can override: "use template 3").

## Repo structure

```
resume-generator/                          # plugin root
├── .claude-plugin/plugin.json             # plugin manifest
├── README.md  LICENSE  CLAUDE.md          # repo meta
└── skills/
    └── resume-generator/                  # the skill itself
        ├── SKILL.md                       # entry / gate / dispatch
        ├── onboarding.md                  # knowledge.yaml setup branch
        ├── generation.md                  # tex generation + compile branch
        ├── assets/
        │   └── knowledge.template.yaml
        ├── templates/<1-6>/               # LaTeX template sources
        └── tests/
            ├── preflight.sh               # env check + auto-installer
            └── compile-all.sh             # smoke-compile all six
```

See [CLAUDE.md](CLAUDE.md) for architecture details.

## Development

```bash
# After editing any template, smoke-compile all six:
bash skills/resume-generator/tests/compile-all.sh

# Test the env check:
bash skills/resume-generator/tests/preflight.sh 2          # check
bash skills/resume-generator/tests/preflight.sh 2 install  # check + install missing pkgs
```

When iterating on the skill prompts, run Claude Code with `claude --plugin-dir .` and `/reload-plugins` after each edit.

## Privacy

The skill operates entirely locally. `knowledge.yaml` (your personal data) and `outputs/` are git-ignored — they never leave your machine.

## License

MIT — see [LICENSE](LICENSE).

## Credits

LaTeX templates adapted from public sources (moderncv, FreemanCV, Wilson, Cies, and others). Original notices preserved per template under `skills/resume-generator/templates/<N>/`.
