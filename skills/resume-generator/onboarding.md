# Onboarding — knowledge.yaml setup

You are reading this because the gate in `SKILL.md` detected one of:

- no `knowledge.yaml` in the user's current working directory (Branch 1), or
- the user explicitly asked to bootstrap entries from directories (Branch 1c), or
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

## Branch 1 — knowledge.yaml is missing

Tell the user, verbatim formatting:

> No `knowledge.yaml` found in this directory. Three ways to start:
>
> 1. **Blank** — I'll drop a template here you fill in
> 2. **Import** — give me a path to your existing resume (PDF, .tex, .txt, .md, image) or a URL to a hosted resume, and I'll populate the template from it
> 3. **Bootstrap from work** — point me at one or more directories of your past work (project repos, writeups, talks, design files). I'll walk them, draft a knowledge.yaml describing each, and record `evidence:` pointers so I can re-read them later for deep-dives.
>
> Which?

Wait for the user's choice. Do not act before they answer. If the reply is ambiguous, ask once for clarification.

### Branch 1a — Blank

1. Copy `<SKILL_ROOT>/assets/knowledge.template.yaml` → `<cwd>/knowledge.yaml` with `cp` (not Read+Write: preserves the file exactly).
2. Confirm:
   > Created `knowledge.yaml` at `<cwd>/knowledge.yaml`. Open it, replace the `<PLACEHOLDER>` values with your real data (delete optional lines you don't need), then re-invoke me. `assets/knowledge.example.yaml` in the skill folder shows a filled-in example.
   >
   > **I can also fill sections incrementally on request.** For example: "fill the projects section from what I tell you about each project" or "ask me questions to populate the experience block."
3. End the turn. Do not generate a resume.

### Branch 1b — Import

1. Ask for the source: file path, URL, or pasted text. Accepted: PDF, `.tex`, `.txt`/`.md`, images (jpg/png, visual extraction), URLs to a hosted resume or personal site.
   - **LinkedIn profile URLs cannot be fetched** (login wall). Ask the user to export it instead: LinkedIn → Me → View profile → More → Save to PDF, then give the PDF path. The same applies to any page that needs a login.
2. **Dispatch a sub-agent** to parse. Do not read the source yourself; that defeats the token-isolation point.
   - `subagent_type`: `general-purpose`, `model`: `sonnet`, `description`: `Parse resume into knowledge.yaml`
   - `prompt`: the source location, the template path (`<SKILL_ROOT>/assets/knowledge.template.yaml`), the destination (`<cwd>/knowledge.yaml`), and instructions to:
     - Read the template first to learn the schema (including `tags:`, `start`/`end`, `publications:`, `evidence:`).
     - Read the source (`Read` for files, `WebFetch` for URLs, vision for images). If a fetch returns a login wall or an empty page, stop and report that instead of guessing.
     - Map source data into the schema, preserving the template's comments and section headers; fill `years` as written and `start`/`end` in ISO form when dates are unambiguous.
     - Leave any field not found in the source as its `<PLACEHOLDER>`; delete optional blocks the source has nothing for. Never invent.
     - Write `<cwd>/knowledge.yaml`. Return: fields populated, fields still holding placeholders, ambiguities.
3. Run the validator. Summarize:
   > Imported. Filled: [list]. Still missing (placeholders remain): [list from `MISSING=`/`PLACEHOLDER=`]. Optional placeholders left: [count].
   >
   > **I can also fill sections incrementally on request.** Re-invoke me when ready to generate.
4. End the turn.

### Branch 1c — Bootstrap from work

The user supplies one or more local directories (or repo URLs). For each top-level path, **dispatch a sub-agent** to walk it, infer project boundaries, and draft entries. Do not read the dirs yourself.

1. Ask (if not already provided):
   > Give me the directory path(s), one per line or comma-separated. Each is treated as a single project (if it looks like one repo/artifact) or a parent of several (if it holds many standalone subdirs); I decide per dir. Noise dirs (`.git`, `node_modules`, `__pycache__`, `dist`, `build`, `target`, `.venv`, `vendor`) and anything that looks like a secret (`.env`, keys, credentials) are skipped.
   >
   > Optional: tell me which dirs are a job's work (→ `experience`) vs personal work (→ `projects`). Default is `projects`.
2. Validate each path exists (`ls`/`stat`). Missing or unreadable → tell the user and ask before proceeding.
3. Dispatch one sub-agent per top-level path, all in **one message** (parallel):
   - `subagent_type`: `general-purpose`, `model`: `sonnet`, `description`: `Bootstrap knowledge entries from <dir>`
   - `prompt`: the dir path, the template path, and instructions to:
     - Read the template first (`experience`, `projects`, `events`, `tags:`, `evidence:` conventions).
     - Walk with `Glob`/`Read`. Skip `.git`, `node_modules`, `__pycache__`, `dist`, `build`, `target`, `.venv`, `vendor`, `.next`, `.cache`, binaries and files > 1 MB. **Never open** `.env*`, `*.pem`, `*.key`, `*.p12`, `id_rsa*`, `id_ed25519*`, `*.kdbx`, or any file whose name contains `secret`, `credential`, `token`, or `password`; never copy anything that looks like a key or password into the output.
     - Decide one-project vs many: a README/package.json/Cargo.toml/pyproject.toml/.git at the root → one project; many subdirs each with their own → many.
     - Per project draft an entry with: `name` (README title, package name, or dir name), `description` (2-3 sentences from README + structure), `technologies` (manifests, extensions, framework markers), `tags` (2-4 labels such as backend, ml, frontend, data, infra), `start`/`end` from git history or file dates when clear (else omit), `achievements: []` (never invent quantifications), `evidence` (absolute project root plus standout sub-paths such as `docs/postmortem.md`, `RESULTS.md`), `link` if a remote URL is detected.
     - Return: a YAML fragment with just the new entries (not the full file), one line per entry, and the list of dirs skipped with reasons.
4. Merge fragments into `<cwd>/knowledge.yaml`:
   - No file yet → copy the template first, then insert the entries into their sections, leaving personal-info placeholders intact.
   - File exists → `Edit` to append into the right sections; match existing entries by `name` and don't duplicate.
5. Run the validator. Summarize:
   > Bootstrapped from `<N>` dir(s). Drafted: `<count>` projects, `<count>` experience entries; `evidence:` and `tags:` recorded for all of them.
   >
   > **Still missing**: [from the validator: personal info, etc.], plus achievements/quantifications on each entry (left blank; fill them yourself or tell me and I'll write them in).
   >
   > Re-invoke me when ready. With a job posting I'll deep-dive the relevant `evidence:` for sharper details.
6. End the turn.

### Branch 1d — neither / unclear

Re-ask once. Still unclear → default to Blank.

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

Entered when the hard gate passed but the job-posting analysis flagged optional fields that matter for this role.

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
4. **Proceed without** → echo the accepted gaps so they're recorded, return to `SKILL.md` to dispatch `generation.md`, and pass the gap list along; generation reports it again in `report.md`.

---

## Hard rules during onboarding

- Never invent data. No value from the user → the placeholder stays.
- Never delete required fields to bypass the gate.
- Never start LaTeX generation while in onboarding; control returns to `SKILL.md` first.
- After every write to `knowledge.yaml`, run the validator and show the result.
- The skill folder (`<SKILL_ROOT>`) is read-only. Copy out of it, never into it.
- Sub-agents that walk directories never open secret-looking files and never write outside `<cwd>/knowledge.yaml`.
