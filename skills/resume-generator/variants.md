# Variants — several resumes in one request

Loaded from `generation.md` when the user wants more than one resume at once ("Industry + Academic versions", "tailor for these three postings"). Each variant is one full `generation.md` run in its own output directory. Sub-agents do the builds; main does everything that involves the user.

## Before dispatching (main, sequential)

1. The gate has passed once; it covers all variants.
2. Resolve for every variant, now:
   - posting analysis (URLs and files → one analyser sub-agent each, dispatched in parallel; pasted text → inline)
   - template number (Step 1 rules; ask now for any low-confidence pick)
   - output slug (Step 3 rules; collisions resolved now, so two variants never share a `<dir>`)
   - soft-gate decisions (`SKILL.md` Step 3), one round for all variants; deferred gaps are resolved here too (item 4)
3. Run preflight (Step 1.5) once per distinct template number, including any install consent (skipped entirely when `SOURCE_ONLY=yes`).
4. **Warm the evidence cache**: run `deep-dive.md` Phase 1 (Extract) in main for the union of entries selected across all variants' postings, so Phase 2 per variant is cheap and needs no sub-agent. With the facts in hand, settle every deferred gap for every variant in **one** question (generation Step 4.6); variants only record the outcome.
5. Sub-agents **cannot ask the user anything**; every question above is answered here first.

## Dispatch

One `Agent` call per variant, all in a single message (parallel). At most 4 concurrent; queue the rest and dispatch as returns arrive.

- `subagent_type`: `general-purpose`, `model`: `inherit`
- **no `isolation`**: a git worktree would lack the gitignored `knowledge.yaml` and would be removed as "unchanged" together with the PDFs written inside it
- `description`: `build <slug> variant`
- `prompt`, self-contained: absolute `<cwd>`, absolute `<SKILL_ROOT>`, absolute `<dir>`, the template number, the posting analysis (not the raw posting), the path to `knowledge.yaml`, the `OPTIONAL_PLACEHOLDER=` lines, `--skip-preflight`, and: "Read `<SKILL_ROOT>/generation.md`, `<SKILL_ROOT>/deep-dive.md` and `<SKILL_ROOT>/templates/<N>/NOTES.md`, then run Steps 4, 4.5 (Phase 2 only: read `<cwd>/.resume-cache/evidence/`, never dispatch; a miss is a warning), 5a, 5b, 6, 7, 7.5 and 8 exactly. Deferred gaps are already settled: <list with outcomes>. Never ask the user. Write only inside `<dir>`. Do not touch `outputs/index.md`. Return the `qa-gate.sh` STATUS and `FAIL=`/`WARN=` lines, the coverage score, the list of warnings, and the paths of `resume.pdf`, `report.md` and `posting.json`."

Phase 2 tailoring runs inside each variant against its own posting; extraction happened once in main.

## After the returns

- Main appends one `outputs/index.md` row per successful variant (one writer, no races).
- Report all PDFs in one message: per variant the path, template + reason, coverage score with its caveat, warnings.
- A failed variant is reported with its diagnosis; the others still ship. Retry a failed variant once only if the failure was environmental (compile error with a clear fix), not to paper over missing data.
