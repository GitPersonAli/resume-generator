# Template 1 — Classic Graduate Resume (`res.cls`)

**Compiler:** pdflatex. **Best for:** students, new grads, internships, first jobs; one page, plain and conservative. Not an academic CV (no publications machinery).

## Skeleton

```latex
\documentclass[margin, 10pt]{res}   % options: margin|overlapped (section-title layout), line|centered, 10pt-12pt
\usepackage{helvet}                  % or newcent
\usepackage[hidelinks]{hyperref}
\setlength{\textwidth}{5.1in}
\begin{document}
\moveleft.5\hoffset\centerline{\large\bf <name>}
\moveleft\hoffset\vbox{\hrule width\resumewidth height 1pt}\smallskip
\moveleft.5\hoffset\centerline{<location>}
\moveleft.5\hoffset\centerline{<email> $\cdot$ <phone> $\cdot$ \href{<url>}{<display>}}
\begin{resume}
    \section{OBJECTIVE}   ...prose...
    \section{EDUCATION}   {\sl <degree>} \\ <university>, <location>, <years> \\ <detail line>
    \section{EXPERIENCE}  {\sl <title>} \hfill <years> \\ <company>, <location>
                          \begin{itemize} \itemsep -2pt \item <achievement> \end{itemize}
    \section{PROJECTS}    same shape as EXPERIENCE ({\sl <name>} \hfill <years> \\ <technologies>)
    \section{SKILLS}      {\sl Languages:} ... \\ {\sl Tools:} ...
\end{resume}
\end{document}
```

## Mapping from knowledge.yaml

| yaml | LaTeX |
|---|---|
| `name` | `\centerline{\large\bf ...}` line |
| `location`, `email`, `phone`, `linkedin`/`github`/`website` | one `\centerline{}` each, or joined with `$\cdot$` |
| `profile` | `\section{OBJECTIVE}` prose (1-2 sentences) |
| `education[]` | `{\sl degree} \\ university, years \\ details...` |
| `experience[]` | `{\sl title} \hfill years \\ company, location` + itemize of `achievements` |
| `projects[]` | same block; put `technologies` on the second line |
| `skills.*` | `\section{SKILLS}` with `{\sl Group:} a, b, c` lines |
| `awards`, `teaching`, `events` | extra `\section{...}` blocks in the same style |

## Gotchas

- Section titles are conventionally UPPERCASE; `\\` inside a title wraps it in the margin column (`\section{COMPUTER \\ SKILLS}`).
- `res.cls` is from 1988: no `\href` support of its own (hyperref now added in the preamble), no `\textbf`-style section fonts. Use `{\sl ...}`/`{\it ...}` like the original.
- `\resumewidth`, `\hoffset` come from the class; keep the header lines exactly as in the skeleton or the rule misaligns.
- Everything after `\begin{resume}` is indented by the class; no `\vspace` hacks needed.
- No `\photo`, no date of birth: this is a US-style resume.
