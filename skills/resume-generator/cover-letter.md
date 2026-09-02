# Cover letter — companion to a generated resume

Loaded when the user asks for a cover letter (`--cover-letter`, "write a cover letter for this posting"). Requires the gate to have passed and a job posting analysis; if there is no posting, ask for it, or at minimum company + role + one reason the user wants this job. Usually runs after a resume was built into `<dir>`. If no resume exists yet and the user wants only the letter, create `<dir>` per generation Step 3 and skip the resume.

## Content rules

- 250 to 350 words, four short paragraphs:
  1. **Hook**: why this role at this company, with one concrete detail from the posting (a product, a team, a stated problem).
  2. **Evidence**: the two or three strongest quantified matches, taken from the coverage matrix and `tailored.yaml`.
  3. **Context**: a gap or transition framed honestly with what the user brings instead; omit when there is none.
  4. **Close**: availability, a thank-you, one call to action.
- Every claim traces to `knowledge.yaml` or a deep-dive citation. No invented numbers, no enthusiasm about products the user knows nothing about.
- Mirror the posting's vocabulary without quoting it back verbatim.
- Address a named hiring manager only if the posting names one; otherwise "Dear Hiring Team".
- `language:` from the yaml applies to the whole letter.
- Date: today's date in the letter's language.

## Build

- **Template 4 (ModernCV)**: fill the class's own letter block inside `resume.tex` (see `templates/4/NOTES.md`: `\recipient`, `\opening`, `\closing`, `\enclosure`, `\makelettertitle` … `\makeletterclosing`, `\newpage`) and rebuild the resume. The letter is page 1 of the same PDF; the page budget grows by 1.
- **Every other template**: write `<dir>/cover-letter.tex` mirroring `<SKILL_ROOT>/assets/cover-letter.template.tex`. Match the resume's font: template 2 → `\usepackage{ebgaramond}`, template 6 → `\usepackage{tgpagella}`, templates 1, 3, 5 → keep `lmodern`. Then:

  ```bash
  bash <SKILL_ROOT>/tests/lint-tex.sh <dir>/cover-letter.tex
  bash <SKILL_ROOT>/tests/build.sh <dir> --file cover-letter.tex
  ```

  Fix `LINT_ERROR=` lines first. `PAGES` must be 1; if it isn't, cut the context paragraph, then tighten the evidence paragraph. View the PNG once (signature block on the page, no orphan line).
- Add the letter's PDF path to `report.md` and to the final message. No extra row in `outputs/index.md`; the resume row covers the application.
