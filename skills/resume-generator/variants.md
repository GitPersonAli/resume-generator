# Variants — several resumes in one request

Loaded from `generation.md` when the user wants more than one resume at once ("Industry + Academic versions", "tailor for these three postings"). Each variant is one full `generation.md` run in its own output directory. Sub-agents do the builds; main does everything that involves the user.

## Before dispatching (main, sequential)

1. The gate has passed once; it covers all variants.
2. Resolve for every variant, now:
   - posting analysis (URLs and files → one analyser sub-agent each, dispatched in parallel; pasted text → inline)
   - template number (Step 1 rules; ask now for any low-confidence pick)
   - output slug (Step 3 rules; collisions resolved now, so two variants never share a `<dir>`)
   - soft-gate decisions (Step 3 of `SKILL.md`), one round for all variants
3. Run preflight (Step 1.5) once per distinct template number, including any install consent.
4. Sub-agents **cannot ask the user anything**; every question above is answered here first.

## Dispatch

One `Agent` call per variant, all in a single message (parallel). At most 4 concurrent; queue the rest and dispatch as returns arrive.

- `subagent_type`: `general-purpose`, `model`: `inherit`
- **no `isolation`**: a git worktree would lack the gitignored `knowledge.yaml` and would be removed as "unchanged" together with the PDFs written inside it
- `description`: `build <slug> variant`
- `prompt`, self-contained: absolute `<cwd>`, absolute `<SKILL_ROOT>`, absolute `<dir>`, the template number, the posting analysis (not the raw posting), the path to `knowledge.yaml`, the `OPTIONAL_PLACEHOLDER=` lines, `--skip-preflight`, and: "Read `<SKILL_ROOT>/generation.md` and `<SKILL_ROOT>/templates/<N>/NOTES.md`, then run Steps 4 through 8 exactly. Never ask the user. Write only inside `<dir>`. Do not touch `outputs/index.md`. Return the `build.sh` keys, the coverage score, the list of warnings, and the paths of `resume.pdf` and `report.md`."

Deep-dive (Step 4.5) runs inside each variant against its own posting; that is intended.

## After the returns

- Main appends one `outputs/index.md` row per successful variant (one writer, no races).
- Report all PDFs in one message: per variant the path, template + reason, coverage score with its caveat, warnings.
- A failed variant is reported with its diagnosis; the others still ship. Retry a failed variant once only if the failure was environmental (compile error with a clear fix), not to paper over missing data.
