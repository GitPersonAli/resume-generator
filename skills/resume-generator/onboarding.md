# Onboarding — knowledge.yaml setup

You are reading this because the gate in `SKILL.md` detected one of:

- `knowledge.yaml` does not exist in the user's current working directory, OR
- `knowledge.yaml` exists but a required field is empty or still holds a `<PLACEHOLDER>` sentinel.

Stay in onboarding until the gate passes. Do not start generating a resume.

---

## Required fields (the hard gate)

A `knowledge.yaml` passes the gate when **all** of the following are filled (no `<PLACEHOLDER>` sentinels, no empty strings):

- `name`
- `email`
- at least one entry in `education`
- at least one entry in **either** `experience` or `projects`

Other fields are optional. They may stay as placeholders or be deleted. They only become important during role-aware gap analysis (see §"Targeted fill" below and `generation.md`).

The placeholder regex you use to detect unfilled fields: `<[A-Z_]+>`.

Bundled blank template path:
`<SKILL_ROOT>/assets/knowledge.template.yaml`
where `<SKILL_ROOT>` is the directory containing this file.

---

## Branch 1 — knowledge.yaml is missing

Tell the user, verbatim formatting:

> No `knowledge.yaml` found in this directory. Two ways to start:
>
> 1. **Blank** — I'll drop a template here you fill in
> 2. **Import** — give me a path/URL to your existing resume (PDF, .tex, .txt, .md, image, or LinkedIn URL) and I'll populate the template from it
>
> Which?

Wait for the user's choice. Do not act before they answer. If their reply is ambiguous, ask once for clarification.

### Branch 1a — User picked Blank

1. Copy `<SKILL_ROOT>/assets/knowledge.template.yaml` → `<cwd>/knowledge.yaml`. Use the `Bash` `cp` command, not `Read`+`Write` (preserves file exactly).
2. Confirm to user:
   > Created `knowledge.yaml` at `<cwd>/knowledge.yaml`. Open it, replace the `<PLACEHOLDER>` values with your real data, then re-invoke me to continue.
   >
   > **Note: I can also fill sections incrementally on request — just ask. For example: "fill the projects section based on what I tell you about each project" or "ask me questions to populate the experience block."**
3. End the turn. Do not generate a resume.

### Branch 1b — User picked Import

1. Ask the user for the source: file path, URL, or pasted text. Accepted formats:
   - PDF (`.pdf`)
   - LaTeX source (`.tex`)
   - Plain text or markdown (`.txt`, `.md`)
   - Image (jpg, png) — visual extraction
   - URL (LinkedIn profile, personal site, hosted resume)
2. Once you have the source, **dispatch a sub-agent** to do the parsing. Do not read the source yourself — that defeats the token-isolation point of using a sub-agent.

   Dispatch via `Agent` tool:
   - `subagent_type`: `general-purpose`
   - `model`: `sonnet`
   - `description`: `Parse resume into knowledge.yaml`
   - `prompt`: include the source location, the path to the bundled template (`<SKILL_ROOT>/assets/knowledge.template.yaml`), the path the agent should write the result to (`<cwd>/knowledge.yaml`), and instructions to:
     - Read the bundled template first to learn the schema.
     - Read the source (use `Read` for files, `WebFetch` for URLs, vision for images).
     - Map source data into the template's schema, preserving all comments and section headers.
     - Leave any field not found in the source as the original `<PLACEHOLDER>` sentinel — do not guess or invent.
     - Write the populated yaml to `<cwd>/knowledge.yaml`.
     - Return: (a) list of fields populated, (b) list of fields still holding `<PLACEHOLDER>`, (c) any ambiguities encountered.
3. When the sub-agent returns, summarize to the user:
   > Imported. Filled: [list]. Still missing (placeholders remain): [list].
   >
   > **Note: I can also fill sections incrementally on request — just ask. For example: "fill the projects section based on what I tell you about each project" or "ask me questions to populate the experience block."**
   >
   > Re-invoke me when ready to generate.
4. End the turn.

### Branch 1c — User picked neither / unclear

Re-ask once. If still unclear, default to Blank.

---

## Branch 2 — knowledge.yaml exists but mid-fill

The gate ran, the file parsed as valid yaml, but at least one required field is empty or holds a `<PLACEHOLDER>`.

1. List the specific failures to the user. Be precise — name each path:
   > `knowledge.yaml` is missing some required data:
   > - `name` still holds `<YOUR_NAME>`
   > - `education[0].university` is empty
   > - …
   >
   > How would you like to fill these? Three options:
   > 1. You edit `knowledge.yaml` directly and re-invoke me
   > 2. Tell me the values here and I'll write them in
   > 3. I ask you each missing field one by one
2. Wait for choice.
3. If option 2 or 3, after the user provides values, write back to `<cwd>/knowledge.yaml` using `Edit` (preserving the rest of the file). Re-run the gate (re-read the file, re-check required fields).
4. When the hard gate passes, control returns to `SKILL.md`. Either it dispatches to `generation.md` (no job posting given), or it runs the role-aware gap scan (job posting given).

---

## Branch 3 — Targeted fill (role-aware soft gate)

Entered when `SKILL.md`'s gate passed the hard requirements but a job-posting analyzer flagged optional fields that are critical for the target role.

1. List each gap with the role-specific reason:
   > For this role, the following knowledge fields would strengthen your resume but are currently empty or placeholder:
   > - `skills.programming` — the posting requires Python and SQL
   > - `projects` — the posting emphasizes ML pipelines and you have only one project entry
   > - …
   >
   > Two options:
   > 1. **Fill** — tell me the missing data (or edit `knowledge.yaml` directly), then I'll regenerate the gate scan
   > 2. **Proceed without** — I'll generate the resume as-is, but be aware this **reduces your fit score for this position**. The recruiter screening will see gaps the posting flagged as required.
2. Wait for choice.
3. If "Fill", run the same write-back loop as Branch 2 then re-run the role-aware scan.
4. If "Proceed without", echo the warning back so it's recorded in the conversation, then return control to `SKILL.md` to dispatch `generation.md`. Pass the list of accepted gaps along — the generation flow will surface them again in the final report.

---

## Hard rules during onboarding

- Never invent data. If the user hasn't given you a value, leave the placeholder.
- Never delete required fields to bypass the gate. Required fields are required because the templates expect them.
- Never start LaTeX generation while in onboarding — control must return to `SKILL.md` first.
- After every write to `knowledge.yaml`, re-read it and re-run the gate logic before claiming the user can proceed.
- The skill folder (`<SKILL_ROOT>`) is read-only from the user's perspective. Never copy `knowledge.yaml` into the skill folder, only out of it.
