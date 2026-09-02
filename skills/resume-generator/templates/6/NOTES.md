# Template 6 — Cies Resume (`structure.tex`, minimal one-page)

**Compiler:** pdflatex. **Best for:** clean one-page resumes, senior engineers and consultants who want whitespace, creative/design/UX roles that lead with portfolio links; A4, TeX Gyre Pagella serif.

## Skeleton

```latex
\documentclass[10pt,a4paper]{article}
\include{structure}
\begin{document}
\maintitle{<name>}{<headline, e.g. "Senior Backend Engineer">}   % 2nd arg is a subtitle (the original used a date of birth)
\noindent\href{mailto:<email>}{<email>}\bull <phone>\bull \href{<website>}{<website display>}\\
<location>\bull \href{<linkedin>}{linkedin.com/in/...}\bull \href{<github>}{github.com/...}
\spacedhrule{0.9em}{-0.4em}
\roottitle{Summary}
\vspace{-1.3em}
\begin{multicols}{2} \noindent <profile prose, 2 paragraphs max> \end{multicols}
\spacedhrule{0.5em}{-0.4em}
\roottitle{Experience}
\headedsection{\href{<company website>}{<company>}}{\textsc{<company_location>}} {
    \headedsubsection{<title>}{<years>}{\bodytext{<description; achievements joined into 2-3 sentences or a short itemize>}}
}
\spacedhrule{-0.2em}{-0.4em}
\roottitle{Projects}
\headedsection{\href{<link>}{<project name>}}{\textsc{<technologies, 3-5 max>}} {
    \headedsubsection{<role or blank>}{<years>}{\bodytext{<description>}}
}
\spacedhrule{0.5em}{-0.4em}
\roottitle{Education}
\headedsection{<university>}{\textsc{<location>}} {
    \headedsubsection{<degree>}{<years>}{\bodytext{<details joined>}}
}
\spacedhrule{0.5em}{-0.4em}
\roottitle{Skills}
\inlineheadsection{Technical:}{<skills.programming + frameworks + tools as prose>}
\inlineheadsection{Languages:}{<skills.languages as prose>}
\end{document}
```

## Mapping from knowledge.yaml

| yaml | LaTeX |
|---|---|
| `name` | `\maintitle{name}{headline}`; headline = target job title or first line of `profile` |
| `email`, `phone`, `website`, `location`, `linkedin`, `github` | contact lines joined with `\bull` |
| `profile` | Summary in `multicols{2}` |
| `experience[]` | `\headedsection{company}{location}{ \headedsubsection{title}{years}{\bodytext{...}} }`; group several titles at one employer inside one `\headedsection` |
| `projects[]` | `\headedsection{name}{technologies}{ \headedsubsection{}{years}{\bodytext{description}} }` |
| `education[]` | `\headedsection{university}{location}{ \headedsubsection{degree}{years}{\bodytext{details}} }` |
| `skills.*` | `\inlineheadsection{Label:}{prose}` lines |
| `certifications`, `awards`, `events` | one `\roottitle{}` + `\inlineheadsection` per group, or drop on a one-page target |

## Gotchas

- `\headedsection{a}{b}{ ... }`: the THIRD argument is a brace group that wraps all its `\headedsubsection`s. A missing closing `}` is the classic compile error here.
- `\headedsubsection{title}{dates}{body}` needs 3 braces; pass `{}` for an empty body.
- `\include{structure}` (not `\input`) is what the template uses; keep it. `structure.tex` loads `hyperref`, `multicol`, `mdwlist`, `microtype`, `tgpagella`.
- One page is the point: cap experience at 4 entries and projects at 3, or drop Summary columns to single paragraph.
- `\acr{TDD}` renders small-caps acronyms; optional but consistent.
- `microtype` + `tgpagella`: if the compile log says "auto expansion is only possible with scalable fonts", the TeX Gyre fonts are missing (`tlmgr install tex-gyre`, Debian `texlive-fonts-recommended`). preflight.sh reports this.
- The multicols Summary breaks poorly under ATS text extraction; for ATS-heavy postings prefer a single paragraph.
