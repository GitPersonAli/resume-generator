# Onboarding — knowledge.yaml setup

You are reading this because the gate in `SKILL.md` detected one of:

- no `knowledge.yaml` in the user's current working directory (Branch 1), or
- the user handed over sources (a resume file/URL and/or work directories) in the request (Branch 1 with sources), or
- `knowledge.yaml` exists but does not parse as YAML (Branch 2b), or
- it parses but a required field is empty or still holds a `<PLACEHOLDER>` (Branch 2), or
- the role-aware soft gate flagged gaps and the user chose to fill them (Branch 3).

Stay in onboarding until the gate passes. Do not start generating a resume.

---

## The gate, restated

```bash
bash <SKILL_ROOT>/tests/validate-knowledge.sh <cwd>/knowledge.yaml
```

Exit 0 = pass. Exit 1 = required data missing (`MISSING=` / `PLACEHOLDER=` lines name the paths). Exit 2 = invalid YAML (`PARSE_ERROR=line:col: message`). Exit 6 = no YAML parser on this machine; apply the rules by hand.

Required: `name`, `email`; at least one `education` entry with `degree` and `university`; at least one `experience` entry with `title` and `company` **or** one `projects` entry with `name`. Placeholders match `<[A-Z][A-Za-z0-9_]*>`. Everything else is optional; optional placeholders are reported as `OPTIONAL_PLACEHOLDER=` warnings and are treated as empty by the generator.

Bundled files (`<SKILL_ROOT>` = the directory containing this file):
- `assets/knowledge.template.yaml`: blank template with sentinels. Copy it for the user.
- `assets/knowledge.example.yaml`: a complete, fictional example. Show it or quote from it when the user asks what a filled entry looks like; never copy it as their data.

Run the validator after **every** write to `knowledge.yaml` and show the result before claiming the user can proceed.

---

## Branch 1 — knowledge.yaml is missing (or sources were handed over)

Sources are composable: a resume (file, URL, pasted text) fills personal info, education, and employment; work directories fill projects, `evidence:`, and `tags:`. The user can give one, both, or neither.

If no source came with the request, ask, verbatim formatting:

> No `knowledge.yaml` found in this directory. Give me any of these, in one message:
>
> 1. **Blank** — I drop a template here and you fill it in
> 2. **A resume** — a path to your existing resume (PDF, .tex, .txt, .md, image) or a URL to a hosted one; I populate the template from it
> 3. **Work directories** — one or more folders of past work (project repos, writeups, talks, design files); I walk them, draft an entry per project, and record `evidence:` pointers for later deep-dives
>
> 2 and 3 combine ("resume.pdf and ~/work/projects"). Which?

Wait for the answer. If the reply is ambiguous, ask once for clarification; still unclear → Blank.

### Branch 1a — Blank (no sources)

1. Copy `<SKILL_ROOT>/assets/knowledge.template.yaml` → `<cwd>/knowledge.yaml` with `cp` (not Read+Write: preserves the file exactly).
2. Confirm:
   > Created `knowledge.yaml` at `<cwd>/knowledge.yaml`. Open it, replace the `<PLACEHOLDER>` values with your real data (delete optional lines you don't need), then re-invoke me. `assets/knowledge.example.yaml` in the skill folder shows a filled-in example.
   >
   > **I can also fill sections incrementally on request.** For example: "fill the projects section from what I tell you about each project" or "ask me questions to populate the experience block."
3. End the turn. Do not generate a resume.

### Branch 1 with sources — import and/or bootstrap, one turn

1. **Validate sources first** (main). A LinkedIn profile URL cannot be fetched (login wall): ask for the export instead (LinkedIn → Me → View profile → More → Save to PDF). Each directory must exist (`ls`/`stat`); missing or unreadable → tell the user and ask before proceeding. Optional: which dirs are a job's work (→ `experience`) vs personal work (→ `projects`); default `projects`.
2. If `<cwd>/knowledge.yaml` does not exist, `cp` the template there now (personal-info placeholders stay until a source fills them).
3. **Dispatch every source handler in one message** (parallel). Handlers return YAML **fragments**, never the whole file; main merges.

   **Resume handler** (one, when a resume was given): `subagent_type: general-purpose`, `model: sonnet`, `description: Parse resume into knowledge fragments`. Prompt: the source (`Read` for files, `WebFetch` for URLs, vision for images), the template path (`<SKILL_ROOT>/assets/knowledge.template.yaml`) to learn the schema (`tags:`, `start`/`end`, `publications:`, `evidence:`), and instructions to map the source into the schema, fill `years` as written and `start`/`end` in ISO form when unambiguous, leave anything not found as its `<PLACEHOLDER>`, omit optional blocks the source has nothing for, never invent, and if a fetch returns a login wall or an empty page stop and report. Return: a YAML fragment with the populated top-level keys (`name`, `email`, …, `education`, `experience`, `skills`, …), the list of fields still holding placeholders, and ambiguities.

   **Directory handler** (one per top-level path): `subagent_type: general-purpose`, `model: sonnet`, `description: Bootstrap knowledge entries from <dir>`. Prompt: the dir path, the template path, and instructions to read the template first (`experience`, `projects`, `events`, `tags:`, `evidence:` conventions); walk with `Glob`/`Read`, skipping `.git`, `node_modules`, `__pycache__`, `dist`, `build`, `target`, `.venv`, `vendor`, `.next`, `.cache`, binaries and files > 1 MB; **never open** `.env*`, `*.pem`, `*.key`, `*.p12`, `id_rsa*`, `id_ed25519*`, `*.kdbx`, or any file whose name contains `secret`, `credential`, `token`, or `password`, and never copy anything that looks like a key or password into the output; decide one-project vs many (a README/package.json/Cargo.toml/pyproject.toml/.git at the root → one project; many subdirs each with their own → many); per project draft `name` (README title, package name, or dir name), `description` (2-3 sentences), `technologies` (manifests, extensions, framework markers), `tags` (2-4 labels such as backend, ml, frontend, data, infra), `start`/`end` from git history or file dates when clear (else omit), `achievements: []` (never invent quantifications), `evidence` (absolute project root plus standout sub-paths such as `docs/postmortem.md`, `RESULTS.md`), `link` if a remote URL is detected. Return: a YAML fragment with just the new entries under `projects:` (or `experience:` when told), one line per entry, and the list of dirs skipped with reasons.

4. **Merge** (main, `Edit` into `<cwd>/knowledge.yaml`), fixed precedence:
   - Resume fragment fills `name`, `email`, `phone`, `links`, `profile`, `education`, `experience`, `skills`, `languages`, `certifications`, `publications`: a value replaces a placeholder, never an existing real value.
   - Directory fragments fill `projects` (or `experience` when the user said so), `evidence:`, `tags:`.
   - Same entry in both (matched by `name`, or `title` + `company`, case-insensitive): keep the resume's dates and wording, union `technologies`, add the directory's `evidence:` and `tags:`. Never duplicate an entry.
   - Keep the template's comments and section order.
5. Run the validator once. Summarize:
   > Set up `knowledge.yaml` from <N> source(s). Filled: [list]. Drafted <count> projects / <count> experience entries with `evidence:` and `tags:`. Still missing (placeholders remain): [from `MISSING=`/`PLACEHOLDER=`]. Optional placeholders left: [count]. Achievements on bootstrapped entries are blank: fill them yourself or tell me and I'll write them in.
   >
   > If this directory is a git repo, add `knowledge.yaml`, `outputs/`, and `.resume-cache/` to `.gitignore`.
   >
   > Re-invoke me when ready. With a job posting I'll deep-dive the relevant `evidence:` for sharper details.
6. End the turn.

---

## Branch 2 — knowledge.yaml exists but mid-fill

The validator exited 1. List the failures precisely, straight from its output:

> `knowledge.yaml` is missing some required data:
> - `name` still holds `<YOUR_NAME>`
> - `education[0].university` is empty
> - …
>
> How would you like to fill these?
> 1. You edit `knowledge.yaml` directly and re-invoke me
> 2. Tell me the values here and I'll write them in
> 3. I ask you each missing field one by one

Wait for the choice. For 2 or 3, write the values with `Edit` (preserve the rest of the file), then re-run the validator. Loop until exit 0. When it passes, control returns to `SKILL.md` (Step 3 if a posting was given, otherwise `generation.md`).

Mention optional placeholders once ("N optional placeholders remain; they'll be left out of the resume") and move on; they do not block.

---

## Branch 2b — knowledge.yaml does not parse

The validator exited 2 with `PARSE_ERROR=<line>:<col>: <message>`.

1. Show the offending region (`sed -n '<line-2>,<line+2>p' knowledge.yaml`) and the message in plain words.
2. Most common causes: a value containing `: ` or ` #` that isn't quoted (`title: Lead: Platform`), tab characters used for indentation, a `>`/`|` block whose lines aren't indented, unbalanced quotes, a value starting with `*`, `&`, `%`, `@`, or `` ` ``, a stray `- ` at the wrong depth.
3. Propose the exact fix. Apply it with `Edit` only after the user agrees (this is their data), then re-run the validator. Repeat until exit 0 or 1; exit 1 continues in Branch 2.
4. Never "repair" by deleting content or rewriting the whole file.

---

## Branch 3 — Targeted fill (role-aware soft gate)

Entered from `SKILL.md` Step 3 (gaps no evidence could answer) or from generation Step 4.6 (deferred gaps the deep-dive left `still-open`, presented with what the evidence did say). The hard gate has already passed.

1. List each gap with the role-specific reason:
   > For this role, these fields would strengthen your resume but are empty or placeholder:
   > - `skills.programming`: the posting requires Python and SQL
   > - `projects`: the posting emphasises ML pipelines and you have one project entry
   > - `publications`: the posting expects a publication record
   >
   > 1. **Fill**: tell me the missing data (or edit `knowledge.yaml` directly), then I'll re-run the scan
   > 2. **Proceed without**: I'll generate as-is; the screening will see the gaps the posting marked as required
2. Wait for the choice.
3. **Fill** → same write-back loop as Branch 2 (validator after each write), then re-run the role-aware scan.
4. **Proceed without** → echo the accepted gaps so they're recorded, return to where this branch was entered from (`SKILL.md` Step 4, or generation Step 4.6), and pass the gap list along; generation reports it again in `report.md`.

---

## Hard rules during onboarding

- Never invent data. No value from the user → the placeholder stays.
- Never delete required fields to bypass the gate.
- Never start LaTeX generation while in onboarding; control returns to `SKILL.md` first.
- After every write to `knowledge.yaml`, run the validator and show the result.
- The skill folder (`<SKILL_ROOT>`) is read-only. Copy out of it, never into it.
- Sub-agents that walk directories never open secret-looking files and never write anything: they return fragments; only main writes `knowledge.yaml`, and only through the merge rules above.
