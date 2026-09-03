# Deep-dive — sharpen entries from their `evidence:` pointers

Loaded from `generation.md` Step 4.5, only when a job posting is in context and at least one relevant entry carries a non-empty `evidence:` list. Two phases: **Extract** (sub-agents read the evidence and return posting-agnostic facts, cached) and **Tailor** (main picks and phrases the facts for this posting, inline). Nothing here writes to `<cwd>/knowledge.yaml` or to any `evidence:` location.

## Selection — which entries deserve a deep-dive?

Score every entry in `experience`, `projects`, `education`, `teaching`, `certifications`, `publications`, `events`:

- **Skip** if `evidence:` is absent or empty.
- **Skip** if the entry is clearly off-topic for this posting.
- **Select** when both:
  1. its `tags`, `technologies`, description, or domain overlap the posting's required skills or domain language, and
  2. its current `achievements` are thin (≤ 2 lines, no quantifications, generic phrasing), so there is room to improve.
- **Also select** any entry named in the deferred-gap list from `SKILL.md` Step 3, even if its achievements are not thin.

Cap at **5 entries** per generation pass; if more qualify, take the top 5 by relevance to the posting (deferred-gap entries first).

## Path rules (put them in every Extract prompt)

- `~` → the home directory; relative paths resolve against the directory containing `<cwd>/knowledge.yaml`; globs are allowed.
- **Never open secret-looking files**: `.env*`, `*.pem`, `*.key`, `*.p12`, `id_rsa*`, `id_ed25519*`, `*.kdbx`, browser profile directories, or any file whose name contains `secret`, `credential`, `token`, or `password`. Nothing from such files may appear in the output even if found by accident.
- Skip `.git/`, `node_modules/`, `__pycache__/`, `dist/`, `build/`, `target/`, `.venv/`, `vendor/`, `.next/`, `.cache/`, binaries, and files > 200 KB.
- Prefer README, docs, CHANGELOG, postmortems, results files, and top-level code over deep traversal.

## Phase 1 — Extract (cached; sub-agents only on a miss)

The cache lives at `<cwd>/.resume-cache/evidence/<entry-slug>.json` (`<entry-slug>` = the entry's `name` or `title + company`, lowercase kebab-case). It holds posting-agnostic facts, so one extraction serves every posting, variant, and refresh.

For each selected entry:

1. **Freshness check** (main, no sub-agent). The cache is fresh when the file exists and no evidence path has changed since it was written:
   ```bash
   # any output = stale (a file under the evidence path is newer than the cache)
   find <evidence-path> -type f -newer <cwd>/.resume-cache/evidence/<entry-slug>.json -print -quit
   ```
   Run it for every local path in `evidence:`; a single evidence file is checked the same way. URL evidence is stale after 30 days (`extracted_at`). The user saying "re-read the evidence" or passing `--no-cache` forces a miss for every entry. Record each entry as `cache: hit` or `cache: miss` for the report.
2. **Miss → dispatch**, one sub-agent per stale/missing entry, every `Agent` call in a **single message** so they run concurrently:
   - `subagent_type`: `general-purpose`, `model`: `sonnet`, `description`: `Extract facts: <entry name>`
   - `prompt`, self-contained: the entry's current YAML block verbatim (name, description, achievements, technologies, tags, evidence); each `evidence:` path or URL (`Read` for files, `Glob` + `Read` for dirs, `WebFetch` for URLs); the path rules above; and what to extract **without reference to any posting**: quantifications (latency, throughput, users, money, time saved), technologies and patterns actually used, measurable outcomes, scope (team size, ownership, duration). Return **only** this JSON:
     ```json
     {
       "entry_name": "<unchanged>",
       "facts": [
         {"text": "<one concrete, quantified statement>", "kind": "outcome|quantification|technology|scope", "citation": "<file:line or URL>"}
       ],
       "technologies": ["<tech>", "..."],
       "fingerprints": [{"path": "<absolute path as read>", "files": 0}],
       "warnings": ["<anything contradicting the yaml, e.g. yaml says Python but the repo is TypeScript>"]
     }
     ```
     Every fact must carry a citation; unreadable or empty sources → empty arrays plus a warning. Never invent.
   - A failed dispatch (timeout, unreadable paths) → no cache write, `cache: failed`, keep the original entry.
3. **Write the cache** (main): `<cwd>/.resume-cache/evidence/<entry-slug>.json` = the JSON above plus `"extracted_at": "<ISO date>"` and `"source_entry": "<entry name>"`. Create the directory if missing. Tell the user once per session that `.resume-cache/` exists and belongs in `.gitignore` next to `knowledge.yaml` and `outputs/`.
4. **Hit → load** the JSON; no dispatch.

## Phase 2 — Tailor (inline, in main)

Facts are compact; the posting analysis is already in context. For each selected entry:

1. Keep facts whose text or kind overlaps the posting's required or preferred items, domain language, or a deferred gap. Drop the rest for this run (they stay in the cache).
2. Phrase each kept fact as one achievement line in the posting's vocabulary; keep the number and the citation. Append to the entry's `achievements` in the in-memory view, dropping near-duplicates of existing lines.
3. Union the cache's `technologies` into the entry's `technologies` when the posting mentions them or they are clearly relevant.
4. For every deferred gap from `SKILL.md` Step 3, decide `addressed` (a fact or technology now covers it, name it) or `still-open`. Return this list to `generation.md` Step 4.6.
5. Keep every delta, citation, warning, and the per-entry `cache:` status for `report.md` (generation Step 8), so the user can promote good lines into `knowledge.yaml` themselves and fix contradictions.

## Failure mode — nothing usable

If every entry came back empty (fresh cache with no facts, or every dispatch failed), proceed with the original yaml, mark every deferred gap `still-open`, and add one warning to the report: `Deep-dive ran but no evidence yielded content. Check that the paths in knowledge.yaml resolve from <cwd>.`

## Rules

- The cache holds only what the evidence files already say, with citations; never personal data from `knowledge.yaml`, never posting text.
- `.resume-cache/` is the only write outside `outputs/`; delete it any time (`rm -rf .resume-cache`) and the next run re-extracts.
- Variants: Phase 1 runs in main before fan-out (`variants.md`); variant sub-agents run Phase 2 only and treat a miss as a warning, never a dispatch.
