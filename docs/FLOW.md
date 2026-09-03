# resume-generator — control flow and suggested changes

Traced from `skills/resume-generator/` at v0.3.0 (`SKILL.md`, `onboarding.md`, `generation.md`, `deep-dive.md`, `variants.md`, `cover-letter.md`, `tests/*.sh`). The DOT graph in `SKILL.md` stays the source of truth for the entry gate; this document is a derived explainer plus a set of proposals. **Status (2026-09-03): the Part 3 suggestions S1-S7 are implemented in v0.4.0. Part 1 documents the v0.3.0 flow they replaced; Part 4 is the flow that now ships.**

Every diagram starts with `%%{init: {"theme": "dark"}}%%` so it renders readably on a dark editor background regardless of the preview extension's theme setting. On a light theme, delete that line from each block (or set `markdown-mermaid.lightModeTheme` / `darkModeTheme` in VS Code and drop the directives).

Diagram legend (all `flowchart` diagrams):

| Shape | Meaning |
|---|---|
| `[[ ... ]]` | a bash script under `tests/` or a dispatched sub-agent (labelled) |
| `{ ... }` | a decision taken in main context |
| `[( ... )]` | a file written or read |
| `([ ... ])` | entry / exit of a doc |
| dotted edge | control returns through the gate |

---

## Part 1 — Current flow

### 1.1 Bird's-eye

Control moves between markdown docs. Each doc is loaded only when the previous one says so, which keeps the per-run context small.

```mermaid
%%{init: {"theme": "dark"}}%%
flowchart LR
  U([User request]) --> S["SKILL.md<br/>entry, gate, dispatch"]
  S -->|gate fails| O["onboarding.md<br/>Branches 1, 1a-1d, 2, 2b, 3"]
  O -.->|validator exit 0| S
  S -->|gate passes| G["generation.md<br/>Steps 1 - 9"]
  G -.->|Step 4.5| D[deep-dive.md]
  G -.->|several resumes| V[variants.md]
  G -.->|Step 9| C[cover-letter.md]
  G --> OUT[("cwd/outputs/slug/")]
```

### 1.2 Entry and gate (`SKILL.md`)

The gate is `tests/validate-knowledge.sh`, never an eyeball check. Its exit code selects the onboarding branch. A job posting given as URL or file goes to a haiku sub-agent so raw page content never enters main context; pasted text is analysed inline.

```mermaid
%%{init: {"theme": "dark"}}%%
flowchart TD
  A([Skill invoked]) --> B["Parse arguments<br/>posting, --template N, --cover-letter, --skip-preflight"]
  B --> C{"User asked to bootstrap<br/>from directories?"}
  C -->|yes| O1c["onboarding.md<br/>Branch 1c"]
  C -->|no| D{"cwd/knowledge.yaml exists?"}
  D -->|no| O1["onboarding.md<br/>Branch 1"]
  D -->|yes| E[["validate-knowledge.sh"]]
  E -->|"exit 2 invalid-yaml"| O2b["onboarding.md<br/>Branch 2b"]
  E -->|"exit 1 missing"| O2["onboarding.md<br/>Branch 2"]
  E -->|"exit 6 no-parser"| F{Manual gate check}
  F -->|fails| O2
  F -->|passes| G
  E -->|"exit 0 ok, carry OPTIONAL_PLACEHOLDER lines"| G{Job posting given?}
  G -->|no| GEN[generation.md]
  G -->|yes| H{Posting form?}
  H -->|pasted text| I[Analyse inline]
  H -->|URL or file| J[["Sub-agent haiku<br/>fetch and analyse"]]
  J -->|fetch blocked| K([Ask user to paste text, stop])
  J --> L
  I --> L["Role-aware gap scan<br/>vs knowledge.yaml"]
  L --> M{Critical gaps?}
  M -->|no| GEN
  M -->|yes| N{Ask: fill or proceed?}
  N -->|fill| O3["onboarding.md<br/>Branch 3"]
  N -->|proceed| GEN2["generation.md<br/>carry gap list"]
  O1c -.->|validator exit 0| E
  O1 -.->|validator exit 0| E
  O2b -.->|validator exit 0| E
  O2 -.->|validator exit 0| E
  O3 -.->|validator exit 0| E
```

Two paths bypass nothing: "I'm in a hurry, invent placeholders" is answered with the 60-second path (Branch 1a plus five facts) or import, never with a fabricated `resume.tex`.

### 1.3 Onboarding (`onboarding.md`)

Branches 1a, 1b and 1c end the turn after one validator run; the user re-invokes. Branches 2, 2b and 3 loop on the validator until exit 0 and then hand control back to `SKILL.md`.

```mermaid
%%{init: {"theme": "dark"}}%%
flowchart TD
  IN([Entered from SKILL.md]) --> W{Why?}
  W -->|no file| B1["Branch 1: ask<br/>Blank / Import / Bootstrap"]
  W -->|bootstrap request| B1c
  W -->|"validator exit 2"| B2b["Branch 2b: invalid YAML<br/>show region and PARSE_ERROR,<br/>propose fix, apply after consent"]
  W -->|"validator exit 1"| B2["Branch 2: mid-fill<br/>list MISSING / PLACEHOLDER,<br/>ask: you edit / tell me / one by one"]
  W -->|soft-gate fill| B3["Branch 3: targeted fill<br/>gaps with role-specific reasons"]
  B1 -->|blank| B1a["1a: cp knowledge.template.yaml"]
  B1 -->|import| B1b[["1b: sub-agent sonnet<br/>parse PDF / tex / txt / md / image / URL<br/>write knowledge.yaml"]]
  B1 -->|bootstrap| B1c[["1c: one sub-agent per dir, parallel<br/>draft projects / experience with evidence and tags<br/>main merges fragments by name"]]
  B1 -->|unclear| B1d["1d: re-ask once, else Blank"] --> B1a
  B1a --> END([End turn, user re-invokes])
  B1b --> V1[["validate-knowledge.sh"]] --> SUM[Summary: filled / missing / optional] --> END
  B1c --> V1
  B2 -->|"write values with Edit"| V2[["validate-knowledge.sh"]]
  B2b -->|"apply agreed fix with Edit"| V2
  B3 -->|fill| V2
  B3 -->|proceed without| RET
  V2 -->|"exit 1"| B2
  V2 -->|"exit 2"| B2b
  V2 -->|"exit 0"| RET([Return to SKILL.md<br/>Step 3 if posting, else generation])
```

### 1.4 Generation (`generation.md`, Steps 1 - 9)

One resume per run. Three repair loops exist, all operating on `resume.tex`: lint (max three rounds), compile failure (one retry via a sonnet sub-agent), and the QA gate (one trim cycle).

```mermaid
%%{init: {"theme": "dark"}}%%
flowchart TD
  IN(["From SKILL.md: yaml view, optional placeholders,<br/>posting analysis, flags, gap list"]) --> MV{Several resumes?}
  MV -->|yes| VAR[read variants.md]
  MV -->|no| S1
  S1["Step 1: resolve template<br/>explicit, else classify from posting, else ask (default 2)<br/>read templates/N/NOTES.md"] --> S15{"--skip-preflight, or<br/>already ok this session?"}
  S15 -->|yes| S2
  S15 -->|no| PF[["preflight.sh N"]]
  PF -->|"0 ok"| S2
  PF -->|"1 missing"| INST{Install? y/n}
  INST -->|y| PFI[["preflight.sh N install"]] --> PF
  INST -->|n| ABORT([Abort, commands left on screen])
  PF -->|"2 no-compiler"| SRC{"Install TeX and re-invoke,<br/>or continue source-only?"}
  SRC -->|"source-only: Steps 7 and 7.5 skipped"| S2
  SRC -->|install| ABORT
  PF -->|"3 no-distro / 4 invalid / 5 install-failed"| ABORT
  S2["Step 2: reuse posting analysis<br/>never re-fetch"] --> S3["Step 3: output dir<br/>cwd/outputs/slug, -v2 on collision,<br/>ask before overwrite"]
  S3 --> S4["Step 4: copy template assets<br/>not template.tex / NOTES.md, preserve dir case"]
  S4 --> S45{"Posting in context AND<br/>a relevant entry has evidence:?"}
  S45 -->|yes| DD["read deep-dive.md<br/>merge deltas into in-memory view"]
  S45 -->|no| S5
  DD --> S5["Step 5: write resume.tex<br/>compiler marker on line 1, drop samples, omit sentinels,<br/>select and order (tags, pin, ISO dates), page budget,<br/>tailor wording, headings by language, escape, href"]
  S5 --> S6a[["Step 6a: lint-tex.sh"]]
  S6a -->|"LINT_ERROR, fewer than 3 rounds"| FIX6[fix resume.tex] --> S6a
  S6a -->|"ok, or 3 rounds spent"| S6b{Posting?}
  S6b -->|yes| CM["Step 6b: coverage matrix and score,<br/>top-3 skills in the first half of page 1,<br/>edit and re-lint if touched"]
  S6b -->|no| S7
  CM --> S7[["Step 7: build.sh dir --template N"]]
  S7 -->|"1 compile-failed"| DIAG[["Sub-agent sonnet<br/>diagnose resume.log"]] -->|"apply, one retry"| S7
  S7 -->|"2 no-compiler"| PF
  S7 -->|"0 ok"| S75{"Step 7.5 QA gate<br/>PAGES within budget, leaks 0,<br/>UNRESOLVED_REFS 0, OVERFULL at most 5,<br/>PNG viewed once"}
  S75 -->|"fail, one cycle"| TRIM[trim or fix source] --> S7
  S75 -->|"pass, or cycle spent"| S8["Step 8: persist<br/>tailored.yaml, report.md, outputs/index.md row,<br/>report to user"]
  S8 --> S9{Cover letter requested?}
  S9 -->|yes| CL[read cover-letter.md] --> DONE
  S9 -->|no| DONE([Done])
```

### 1.5 Deep-dive (`deep-dive.md`, Step 4.5)

Runs only with a posting in context. One sonnet sub-agent per selected entry, all dispatched in one message. Output is a JSON delta merged into the in-memory view; `knowledge.yaml` is never written.

```mermaid
%%{init: {"theme": "dark"}}%%
flowchart TD
  IN([generation Step 4.5]) --> SC["Score entries in experience, projects, education,<br/>teaching, certifications, publications, events"]
  SC --> F1{"evidence: present<br/>and non-empty?"}
  F1 -->|no| SKIP[skip entry]
  F1 -->|yes| F2{"Overlaps posting<br/>AND achievements thin?"}
  F2 -->|no| SKIP
  F2 -->|yes| SEL["select, cap 5 by relevance"]
  SEL --> DISP[["One sub-agent per entry, parallel, sonnet<br/>prompt: entry block, posting analysis,<br/>evidence paths, path and secret rules"]]
  DISP --> R["JSON: achievements_proposed,<br/>technologies_to_add, citations, warnings"]
  R --> CHK{"Every proposed line<br/>has a citation?"}
  CHK -->|no| DROP[drop the line, keep the warning]
  CHK -->|yes| MERGE["Merge into in-memory view<br/>append achievements, union technologies"]
  DROP --> MERGE
  MERGE --> ALL{All returns empty?}
  ALL -->|yes| WARN["Warning for report.md:<br/>no evidence yielded content"] --> OUT
  ALL -->|no| OUT([Back to Step 5, deltas and warnings go to report.md])
```

### 1.6 Variants (`variants.md`)

Every user-facing decision is resolved in main before fan-out because sub-agents cannot ask. Each variant sub-agent runs Steps 4 - 8 in its own output dir, including its own deep-dive. Main is the only writer of `outputs/index.md`.

```mermaid
%%{init: {"theme": "dark"}}%%
flowchart TD
  IN([generation.md: several resumes requested]) --> P1["Main resolves per variant:<br/>posting analysis (parallel analyser sub-agents for URLs and files),<br/>template, slug without collisions, soft-gate decisions"]
  P1 --> P2[["preflight.sh once per distinct template<br/>install consent taken in main"]]
  P2 --> D[["Dispatch one sub-agent per variant<br/>model inherit, no isolation, at most 4 concurrent<br/>prompt: cwd, SKILL_ROOT, dir, N, analysis, yaml path,<br/>OPTIONAL_PLACEHOLDER lines, --skip-preflight"]]
  D --> R["Each variant: generation Steps 4 - 8<br/>own deep-dive against its own posting,<br/>never touches index.md"]
  R -->|success| M["Main: one index.md row per success,<br/>one combined report to the user"]
  R -->|failure| RT{Environmental cause?}
  RT -->|"yes, clear fix"| RETRY[retry once] --> M
  RT -->|no| M
```

### 1.7 Cover letter (`cover-letter.md`, Step 9)

```mermaid
%%{init: {"theme": "dark"}}%%
flowchart TD
  IN([Step 9, or a standalone request]) --> HAS{Posting analysis available?}
  HAS -->|no| ASK["Ask for the posting, or at least<br/>company, role, one reason"] --> W
  HAS -->|yes| W["Write 250 - 350 words, four paragraphs<br/>hook / evidence / context / close<br/>from coverage matrix and tailored.yaml"]
  W --> T{Template 4?}
  T -->|yes| M4["Fill the moderncv letter block in resume.tex,<br/>rebuild, page budget grows by 1"] --> REP
  T -->|no| CLT["cover-letter.tex from assets template,<br/>font matched to the resume"]
  CLT --> L[["lint-tex.sh cover-letter.tex"]] --> B[["build.sh dir --file cover-letter.tex"]]
  B --> P{PAGES equals 1?}
  P -->|no| CUT["cut context paragraph,<br/>then tighten evidence"] --> B
  P -->|yes| PNG[view the PNG once] --> REP["Add path to report.md and final message<br/>no extra index.md row"]
```

### 1.8 Who talks to whom

Sub-agents are dispatched only when they keep raw content out of main: fetched pages, parsed source documents, directory walks, verbose logs, parallel builds. Everything that needs the user stays in main.

```mermaid
%%{init: {"theme": "dark"}}%%
sequenceDiagram
  participant U as User
  participant M as Main (skill context)
  participant A as Analyser (haiku)
  participant I as Importer / Bootstrapper (sonnet)
  participant D as Deep-dive (sonnet, one per entry)
  participant V as Variant builder (inherit, up to 4)
  participant X as Log diagnoser (sonnet)
  U->>M: request, optional posting URL or file
  M->>M: validate-knowledge.sh
  opt gate fails
    M->>U: onboarding menu / questions
    opt import or bootstrap
      M->>I: source path(s) + template schema
      I-->>M: knowledge.yaml written, summary
    end
  end
  opt posting is a URL or file
    M->>A: fetch and analyse
    A-->>M: structured analysis, or "blocked"
  end
  M->>U: soft-gate gaps, template pick, install consent
  M->>M: preflight, output dir, asset copy
  opt evidence: on relevant entries
    par one per entry
      M->>D: entry block + analysis + paths
      D-->>M: JSON deltas
    end
  end
  alt several variants
    par one per variant
      M->>V: Steps 4 - 8 prompt
      V-->>M: build keys, coverage, paths
    end
  else single resume
    M->>M: resume.tex, lint, coverage, build, QA
    opt compile failed
      M->>X: paths to resume.log and resume.tex
      X-->>M: line number + replacement
    end
  end
  M->>M: tailored.yaml, report.md, index.md
  M->>U: PDF path, template + reason, coverage score, warnings
```

### 1.9 Files: what reads and writes what

```mermaid
%%{init: {"theme": "dark"}}%%
flowchart LR
  subgraph cwd ["user cwd"]
    KY[("knowledge.yaml")]
    EV[("evidence: paths and URLs")]
    IDX[("outputs/index.md")]
    subgraph dir ["outputs/slug/"]
      TEX[resume.tex]
      PDF[resume.pdf]
      PNG[resume-p1.png]
      TY[tailored.yaml]
      RP[report.md]
      CLF[cover-letter.tex and .pdf]
    end
  end
  subgraph skill ["SKILL_ROOT, read-only"]
    TPL["templates/N/ cls, sty, fonts"]
    NOTES["templates/N/NOTES.md"]
    ASSETS["assets/ template, example, headings, letter"]
    SCR["tests/*.sh"]
  end
  POST["posting: URL / file / text"] --> MEM
  KY -->|read once at the gate| MEM["in-memory view"]
  EV -->|deep-dive, read-only| MEM
  NOTES --> MEM
  ASSETS --> MEM
  MEM --> TEX
  TPL -->|copied, case preserved| dir
  TEX -->|build.sh| PDF --> PNG
  MEM --> TY
  MEM --> RP
  RP --> IDX
  MEM --> CLF
```

### 1.10 Step ownership

| Stage | Doc | Script | Sub-agent |
|---|---|---|---|
| Argument parse, bootstrap intercept | SKILL.md | - | - |
| Hard gate | SKILL.md | `validate-knowledge.sh` | - |
| Posting analysis | SKILL.md Step 3 | - | haiku (URL / file only) |
| Soft gate | SKILL.md Step 3 | - | - |
| Onboarding writes | onboarding.md | `validate-knowledge.sh` after every write | sonnet (import, bootstrap) |
| Template resolve | generation.md Step 1 | - | - |
| Preflight | generation.md Step 1.5 | `preflight.sh` | - |
| Output dir, assets | generation.md Steps 3 - 4 | - | - |
| Deep-dive | deep-dive.md | - | sonnet, one per entry, cap 5 |
| Render `resume.tex` | generation.md Step 5 | - | - |
| Lint, coverage | generation.md Step 6 | `lint-tex.sh` | - |
| Build | generation.md Step 7 | `build.sh` | sonnet (log diagnosis) |
| QA gate | generation.md Step 7.5 | reads `build.sh` keys | - |
| Persist, report | generation.md Step 8 | - | - |
| Variants | variants.md | `preflight.sh` per template | inherit, one per variant |
| Cover letter | cover-letter.md | `lint-tex.sh`, `build.sh --file` | - |

---

## Part 2 — Friction points found while tracing

1. **The compiler check comes late.** `preflight.sh` needs a template number, so it runs at Step 1.5, after the gate, the posting fetch, the soft-gate question and the template pick. A user without TeX answers several questions before learning they must install or go source-only.
2. **Three repair loops all edit LaTeX.** Lint, compile failure and page-budget trimming each patch `resume.tex`, the hardest representation to change safely. `tailored.yaml` is dumped afterwards, so it can disagree with what hand-trimming actually removed.
3. **Coverage is measured after rendering.** The coverage matrix is built in Step 6b from a finished `resume.tex`, so a missing top-3 skill means another LaTeX edit and re-lint instead of a selection decision.
4. **Deep-dive re-reads the same evidence every run.** The sub-agent prompt mixes extraction with posting-specific phrasing, so nothing is reusable across postings, regenerations or variants. Variants dispatch their own deep-dives per posting.
5. **The posting analysis is not persisted structurally.** Only prose in `report.md`. "Redo the Stripe one after my edits" or "now a cover letter for that one" re-fetches (often blocked) or re-derives.
6. **The QA gate is applied by the model, not a script.** The repo's own rule is "the gate is the script"; that holds for the knowledge gate and lint, but Step 7.5's thresholds and the page-budget arithmetic are model-applied.
7. **The soft gate asks before the deep-dive can answer.** Gaps such as "SQL missing from skills" or "only one ML project" are often exactly what `evidence:` would surface a few steps later.
8. **Onboarding sources are exclusive.** Blank / Import / Bootstrap is a three-way choice; users with a resume PDF and work dirs need two turns.

---

## Part 3 — Suggestions

Each suggestion is self-contained. Diagrams show the changed portion only; unchanged steps are collapsed.

### S1 — Probe the environment at entry, not at Step 1.5

**Problem.** Friction point 1.

**Change.** Add a template-agnostic `tests/env-probe.sh` (or `preflight.sh --quick`) that reports `PDFLATEX=`, `XELATEX=`, `LATEXMK=`, `PDFTOTEXT=`, `PYYAML=` in under a second. Run it in `SKILL.md` alongside the file check. If no compiler is present, ask the install-vs-source-only question first, before any other question. Step 1.5 keeps the smoke compile (it needs `N`) but skips the PATH checks already done. The probe also predicts validator exit 6.

```mermaid
%%{init: {"theme": "dark"}}%%
flowchart TD
  A([Skill invoked]) --> B[Parse arguments]
  B --> C[["env-probe.sh<br/>compilers, latexmk, poppler, python3 + PyYAML"]]
  B --> D[["validate-knowledge.sh"]]
  C --> E{Any TeX compiler?}
  E -->|no| F["Tell the user now: install TeX, or source-only<br/>one question, before anything else"] --> G
  E -->|yes| G["carry ENV lines forward"]
  D --> G
  G --> H[Step 3: posting, soft gate]
  H --> GEN[generation.md]
  GEN --> S15[["Step 1.5 preflight.sh N<br/>smoke compile only"]]
```

**Touches.** `SKILL.md` Steps 1 - 2, `generation.md` Step 1.5, new script + `run-tests.sh` cases, the script table in `CLAUDE.md` and `SKILL.md`.
**Risk.** Low. One extra process at entry.

### S2 — Plan, then render: `tailored.yaml` before `resume.tex`

**Problem.** Friction points 2 and 3.

**Change.** Split Step 5 into a plan and a render. 5a builds the plan: a relevance score per entry (tags, technologies, text overlap, `pin`, recency), a keep / cut / order decision with a one-line reason, a length estimate against the page budget, and the coverage matrix computed from plan × posting. The "top-3 requirements visible on the upper half of page 1" rule becomes a plan constraint. The plan is written as `tailored.yaml` immediately. 5b renders `resume.tex` mechanically from the plan (escaping, `\href`, headings). The page-budget trim loop then drops the next lowest-scored item in the plan and re-renders, instead of editing LaTeX. `report.md` reads the plan for "what was dropped and why".

```mermaid
%%{init: {"theme": "dark"}}%%
flowchart TD
  IN(["after Step 4 / 4.5: in-memory view + posting analysis"]) --> P1["5a Plan: score each entry<br/>tags, technologies, text overlap, pin, recency"]
  P1 --> P2["Keep / cut / order with a reason per entry<br/>estimate length vs page budget"]
  P2 --> P3["Coverage matrix from plan x posting<br/>before any LaTeX exists"]
  P3 --> P4{"Top-3 requirements land<br/>on page-1 upper half?"}
  P4 -->|no| P2
  P4 -->|yes| W[("write tailored.yaml = the plan")]
  W --> R["5b Render resume.tex from tailored.yaml<br/>escape, href, headings by language"]
  R --> L[["lint-tex.sh"]] --> B[["build.sh"]] --> Q{PAGES within budget?}
  Q -->|no| T["Trim in the plan:<br/>drop the next lowest-scored item"] --> W
  Q -->|yes| S8["Step 8: report.md reads the plan"]
```

**Touches.** `generation.md` Step 5 (split), 6b (moves before render, re-verified after), 7.5 (trim targets the plan), 8 (`tailored.yaml` already written; add the score and reason fields). No script changes.
**Risk.** Slightly more tokens per run (plan written, then LaTeX). Offsets the LaTeX repair loops it removes and makes `tailored.yaml` honest.

### S3 — Cache evidence facts; tailor inline

**Problem.** Friction point 4.

**Change.** Split the deep-dive sub-agent's job in two. The sub-agent extracts **posting-agnostic facts** for an entry: quantified outcomes, technologies, scope, each with a citation. Main caches them in `<cwd>/.resume-cache/evidence/<entry-slug>.json` together with fingerprints (path + mtime or URL + fetch date) of the evidence read. Posting-specific phrasing happens inline in main from the compact facts. A cache hit with matching fingerprints skips the dispatch. Variants extract once in main before fan-out and pass the cache path, so variant sub-agents never dispatch their own deep-dives. The cache is gitignored, lives in the user's cwd, and is the only write outside `outputs/`; a later "promote these facts into knowledge.yaml" request routes through onboarding, the one sanctioned writer.

```mermaid
%%{init: {"theme": "dark"}}%%
flowchart TD
  IN([Step 4.5: selected entries, cap 5]) --> C{".resume-cache/evidence/entry.json exists<br/>and evidence fingerprints match?"}
  C -->|hit| F[load facts JSON]
  C -->|"miss or stale"| D[["Sub-agent sonnet: extract posting-agnostic facts<br/>quantifications, technologies, scope, citations"]]
  D --> W[("write cache entry + fingerprints")] --> F
  F --> T["Main, inline: pick facts matching the posting,<br/>phrase as achievements, union technologies"]
  T --> M["merge into the in-memory view / plan"]
  M --> OUT([Step 5])
  subgraph variants ["variants.md"]
    V0["extract once in main, before fan-out"] --> V1["variant sub-agents read the cache only"]
  end
```

**Touches.** `deep-dive.md` (two phases, JSON shape gains `facts` and `fingerprints`), `variants.md` (extraction before dispatch), `generation.md` Step 8 (report cache hits and misses), `SKILL.md` critical rules (name the cache as the one permitted write), onboarding note on `.gitignore`.
**Risk.** Stale-cache bugs if fingerprints are weak; use mtime + size for files, fetch date for URLs, and a `--no-cache` escape hatch.

### S4 — Persist `posting.json`; add refresh, rebuild and cover-letter-later modes

**Problem.** Friction point 5. Hand edits to `resume.tex` are also never re-checked.

**Change.** Step 8 writes `<dir>/posting.json`: the structured analysis, the source (URL / file / "pasted"), the fetch date and the classification. `SKILL.md` gains three modes beyond generate. **refresh `<slug>`** re-reads `knowledge.yaml`, reuses `posting.json` and the plan, asks the existing overwrite-or-`-v2` question, and runs Steps 4.5 - 8 without re-fetching or re-asking the template. **rebuild `<slug>`** runs only lint, build and QA on the user's edited `resume.tex`, then refreshes the QA block in `report.md` and the `index.md` row. **cover letter for `<slug>`** resolves `<dir>` from `index.md` and reads `posting.json` plus `tailored.yaml`.

```mermaid
%%{init: {"theme": "dark"}}%%
flowchart TD
  A([Skill invoked]) --> M{Mode?}
  M -->|"new posting, no slug"| GEN["generate: full flow"] --> P[("Step 8 also writes posting.json")]
  M -->|"refresh slug"| R1[("read outputs/slug/posting.json + tailored.yaml")]
  R1 --> R2[["validate-knowledge.sh"]] --> R3{Overwrite or -v2?} --> R4["generation Steps 4.5 - 8<br/>no re-fetch, no template question"]
  M -->|"rebuild slug"| B1[["lint-tex.sh resume.tex"]] --> B2[["build.sh"]] --> B3[QA gate] --> B4["update report.md QA block + index.md row"]
  M -->|"cover letter for slug"| C1["resolve dir via index.md"] --> C2[("posting.json + tailored.yaml")] --> C3[cover-letter.md]
```

**Touches.** `SKILL.md` (argument table and mode dispatch), `generation.md` Step 8, `cover-letter.md` (resolution when no resume run precedes it). Variants unaffected.
**Risk.** Low. `posting.json` may hold copied posting text; it stays under gitignored `outputs/`.

### S5 — Script the QA gate and classify compile errors before dispatching

**Problem.** Friction point 6, plus every compile failure goes to a sonnet sub-agent even for mechanical error classes.

**Change.** Two scripts. `tests/qa-gate.sh <dir> --template N [--page-limit L] [--file f.tex]` consumes `build.sh` output, applies the budget rule (yaml `page_limit`, else template default, else the experience-years bump for template 2), the leak, refs and overfull thresholds, and emits `STATUS=pass|fail` with one `FAIL=<reason>` line per breach; exit 0/1. `tests/classify-log.sh <resume.log>` maps the `!` lines through a regex table to `CLASS=undefined-control-sequence|missing-file|missing-package|font-not-found|runaway-argument|unknown`, `LINE=`, `TOKEN=`, `HINT=`. Only `unknown` reaches the sub-agent.

```mermaid
%%{init: {"theme": "dark"}}%%
flowchart TD
  B[["build.sh"]] -->|"exit 1"| CL[["classify-log.sh resume.log"]]
  CL -->|"CLASS known, LINE, HINT"| FIX["apply the hinted fix inline"] --> B
  CL -->|"CLASS=unknown"| SUB[["Sub-agent sonnet: diagnose"]] --> FIX
  B -->|"exit 0"| QA[["qa-gate.sh dir --template N --page-limit L"]]
  QA -->|"FAIL=pages"| TRIM["trim the plan"] --> B
  QA -->|"FAIL=leak / refs / overfull"| SRC["fix the source"] --> B
  QA -->|"STATUS=pass"| PNG["view the PNG once"] --> S8[Step 8]
```

**Touches.** Two new scripts with `run-tests.sh` fixtures (sample logs for each class), `generation.md` Steps 7 and 7.5 (shrink to the exit-code table), `cover-letter.md` (`qa-gate.sh --file cover-letter.tex --page-limit 1`), `CLAUDE.md` script table. CI already runs shellcheck and `run-tests.sh`.
**Risk.** Low. Same pattern as the existing gate scripts; bash 3.2 rules apply.

### S6 — Let the soft gate defer to evidence

**Problem.** Friction point 7.

**Change.** In the Step 3 gap scan, for each gap check whether a relevant entry carries `evidence:`. If so, mark the gap deferred instead of asking. After the deep-dive (or the S3 cache) merges, re-evaluate: only gaps still open go to the user via Branch 3, now with the evidence-backed context in hand. Variants keep the rule "every question before fan-out" because with S3 the extraction itself moves into main.

```mermaid
%%{init: {"theme": "dark"}}%%
flowchart TD
  L["Role-aware gap scan"] --> G{Gap list empty?}
  G -->|yes| GEN
  G -->|no| E{"A relevant entry has evidence:<br/>for this gap?"}
  E -->|yes| DEF["mark the gap deferred"] --> GEN
  E -->|no| ASK{Ask now: fill or proceed?}
  ASK -->|fill| O3["onboarding Branch 3"]
  ASK -->|proceed| GEN["generation.md"]
  GEN --> DD["Step 4.5: deep-dive or cache"]
  DD --> RE{Deferred gaps still open?}
  RE -->|no| S5["Step 5"]
  RE -->|yes| ASK2{"Ask once, with evidence context:<br/>fill or proceed?"}
  ASK2 -->|fill| O3
  ASK2 -->|proceed| S5
```

**Touches.** `SKILL.md` Step 3 (deferred list carried forward), `deep-dive.md` (return which deferred gaps it addressed), `onboarding.md` Branch 3 (may be entered from generation), `variants.md` (extraction before fan-out, from S3).
**Risk.** One user question can now appear mid-generation. Acceptable for single runs; forbidden for variants, hence the S3 dependency.

### S7 — Composable onboarding sources

**Problem.** Friction point 8.

**Change.** Branch 1 asks for any combination: a resume file or URL, one or more work directories, or nothing. Sources run as parallel sub-agents in one message (importer plus one bootstrapper per dir) and each returns a fragment. Main merges with fixed precedence: the import fills personal info, education and experience; bootstrappers fill projects, `evidence:` and `tags:`; an entry present in both (matched by `name`) keeps the import's dates and unions technologies and evidence. One validator run, one summary, one turn. The `SKILL.md` bootstrap intercept becomes "a source was given" rather than a separate branch.

```mermaid
%%{init: {"theme": "dark"}}%%
flowchart TD
  B1["Branch 1: no knowledge.yaml<br/>Ask: resume file or URL? work dirs? both? neither?"] --> S{Sources given?}
  S -->|none| BLANK["1a: copy the template, end turn"]
  S -->|one or more| CP["cp template to knowledge.yaml"] --> PAR
  subgraph PAR ["parallel sub-agents, one message"]
    IMP[["Importer, if a resume was given<br/>returns fragment A"]]
    BS1[["Bootstrapper dir 1<br/>returns fragment B1"]]
    BSN[["Bootstrapper dir N<br/>returns fragment BN"]]
  end
  PAR --> MERGE["Main merges by precedence:<br/>A for personal, education, experience;<br/>B for projects, evidence, tags;<br/>same name: keep A dates, union technologies"]
  MERGE --> V[["validate-knowledge.sh"]] --> SUM["one summary, end turn"]
```

**Touches.** `onboarding.md` Branches 1, 1b, 1c (merge rules become shared), `SKILL.md` bootstrap intercept.
**Risk.** Merge conflicts on `name` need a deterministic rule; the one above is simple and documented.

### Priority

| # | Suggestion | Impact | Effort | Depends on |
|---|---|---|---|---|
| S5 | Scripted QA gate + log classifier | high: determinism, fewer sub-agent dispatches | medium: 2 scripts + fixtures | - |
| S2 | Plan then render | high: kills two LaTeX repair loops, honest `tailored.yaml` | medium: docs only | - |
| S4 | `posting.json` + refresh / rebuild / letter-later | high: iteration UX | low - medium | - |
| S3 | Evidence fact cache | medium - high: tokens on variants and regenerations | medium | S4 helps |
| S1 | Env probe at entry | medium: no late TeX surprise | low | - |
| S6 | Evidence-aware soft gate | medium: fewer questions | low | S3 |
| S7 | Composable onboarding | medium: one turn instead of two | low - medium | - |

---

## Part 4 — Combined target flow

All seven applied. Compare with 1.2 and 1.4: the same gates, fewer loops on LaTeX, more of the decisions scripted, and three re-entry modes.

```mermaid
%%{init: {"theme": "dark"}}%%
flowchart TD
  A([Invoke]) --> B["parse arguments + mode"]
  B --> C[["env-probe.sh"]]
  B --> D[["validate-knowledge.sh"]]
  C --> E{Mode}
  D --> E
  E -->|"rebuild slug"| RB[["lint-tex.sh, build.sh, qa-gate.sh"]] --> RBU["update report.md QA block + index.md"]
  E -->|"refresh slug / cover letter for slug"| RF[("load posting.json + tailored.yaml")]
  E -->|generate| PA["posting analysis (inline or haiku)"]
  PA --> SG["gap scan; defer gaps that have evidence"]
  SG --> T["template + NOTES.md"]
  T --> PF[["preflight.sh N (smoke compile)"]]
  PF --> DIR["output dir + assets"]
  RF --> DIR
  DIR --> EX["evidence facts via cache;<br/>extract sub-agents only on miss"]
  EX --> RG{Deferred gaps still open?}
  RG -->|"yes, ask once"| PL
  RG -->|no| PL["5a plan: scores, keep / cut, coverage<br/>write tailored.yaml"]
  PL --> RD["5b render resume.tex from the plan"]
  RD --> LN[["lint-tex.sh"]] --> BD[["build.sh"]]
  BD -->|fail| CLS[["classify-log.sh"]]
  CLS -->|known| RD
  CLS -->|unknown| SUBD[["sub-agent diagnose"]] --> RD
  BD -->|ok| QG[["qa-gate.sh"]]
  QG -->|"FAIL=pages"| PL
  QG -->|"FAIL=leak / refs"| RD
  QG -->|pass| PNG["view the PNG once"]
  PNG --> P8[("persist: tailored.yaml, report.md,<br/>posting.json, index.md row")]
  P8 --> CLQ{Cover letter?}
  CLQ -->|yes| CLD["cover-letter.md, qa-gate.sh --page-limit 1"] --> DONE
  CLQ -->|no| DONE([Done])
  subgraph variants ["variants.md, unchanged shape"]
    VX["all questions + preflight + evidence extraction in main"] --> VD[["one sub-agent per variant, Steps 5a - 8"]]
  end
```

Invariants that every suggestion preserves: `knowledge.yaml` is read from the cwd and written only by onboarding; outputs stay under `<cwd>/outputs/<slug>/`; the compiler comes from the `%!TEX program` marker; sub-agents never ask the user; nothing is fabricated.
