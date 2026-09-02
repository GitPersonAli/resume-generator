# Deep-dive — sharpen entries from their `evidence:` pointers

Loaded from `generation.md` Step 4.5, only when a job posting is in context and at least one relevant entry carries a non-empty `evidence:` list. The output is a set of tailoring deltas merged into the **in-memory** yaml view. Nothing here writes to `<cwd>/knowledge.yaml` or to any `evidence:` location.

## Selection — which entries deserve a deep-dive?

Score every entry in `experience`, `projects`, `education`, `teaching`, `certifications`, `publications`, `events`:

- **Skip** if `evidence:` is absent or empty.
- **Skip** if the entry is clearly off-topic for this posting.
- **Select** when both:
  1. its `tags`, `technologies`, description, or domain overlap the posting's required skills or domain language, and
  2. its current `achievements` are thin (≤ 2 lines, no quantifications, generic phrasing), so there is room to improve.

Cap at **5 entries** per generation pass; if more qualify, take the top 5 by relevance to the posting.

## Path rules (put them in every prompt)

- `~` → the home directory; relative paths resolve against the directory containing `<cwd>/knowledge.yaml`; globs are allowed.
- **Never open secret-looking files**: `.env*`, `*.pem`, `*.key`, `*.p12`, `id_rsa*`, `id_ed25519*`, `*.kdbx`, browser profile directories, or any file whose name contains `secret`, `credential`, `token`, or `password`. Nothing from such files may appear in the output even if found by accident.
- Skip `.git/`, `node_modules/`, `__pycache__/`, `dist/`, `build/`, `target/`, `.venv/`, `vendor/`, `.next/`, `.cache/`, binaries, and files > 200 KB.
- Prefer README, docs, CHANGELOG, postmortems, results files, and top-level code over deep traversal.

## Dispatch — one sub-agent per selected entry, in parallel

Send every `Agent` call in a **single message** so they run concurrently.

- `subagent_type`: `general-purpose`, `model`: `sonnet`, `description`: `Deep-dive: <entry name>`
- `prompt`, self-contained:
  - the entry's current YAML block verbatim (name, description, achievements, technologies, tags, evidence)
  - the job posting **analysis** from the gate (not the raw posting)
  - each `evidence:` path or URL; `Read` for files, `Glob` + `Read` for dirs, `WebFetch` for URLs
  - the path rules above
  - what to extract: concrete details aligned with the posting: quantifications (latency, throughput, users, money, time saved), specific technologies and patterns, measurable outcomes, scope (team size, ownership)
  - return **only** this JSON:
    ```json
    {
      "entry_name": "<unchanged>",
      "achievements_proposed": ["<sharp quantified line>", "..."],
      "technologies_to_add": ["<tech>", "..."],
      "citations": ["<one line per claim: file:line or URL>"],
      "warnings": ["<anything contradicting the yaml, e.g. yaml says Python but the repo is TypeScript>"]
    }
    ```
  - every `achievements_proposed` line must be backed by a `citations` entry; unreadable or empty sources → empty arrays plus a warning. Never invent.

## Apply — merge into the working yaml view

1. For each return, merge into the in-memory copy (never into `<cwd>/knowledge.yaml`):
   - append `achievements_proposed` to the entry's `achievements`, dropping near-duplicates of existing lines
   - union `technologies_to_add` into `technologies`
2. Keep every delta and warning: `report.md` (generation Step 8) lists them so the user can promote good lines into `knowledge.yaml` themselves and fix contradictions.
3. A failed dispatch (timeout, unreadable paths, nothing useful) → keep the original entry, note the failure for the report.

## Failure mode — nothing readable

If every dispatch came back empty, proceed with the original yaml and add one warning to the report: `Deep-dive ran but no evidence yielded content. Check that the paths in knowledge.yaml resolve from <cwd>.`
