# Template 2 — Modern Professional (`resume.cls`, default)

**Compiler:** pdflatex. **Best for:** industry roles (SWE, ML, data, product, ops); one to two pages; US letter by default (`a4paper` option available).

## Skeleton

```latex
\documentclass[11pt]{resume}         % add a4paper for A4
\usepackage{ebgaramond}
\usepackage[hidelinks]{hyperref}
\name{<name>}
\address{<location>}                                   % up to 3 \address lines; each \\ inside becomes a diamond separator
\address{<email> \\ <phone>}
\address{\href{<linkedin>}{linkedin.com/in/...} \\ \href{<github>}{github.com/...}}
\begin{document}
\begin{rSection}{Summary}
    <profile prose>
\end{rSection}
\begin{rSection}{Experience}
    \begin{rSubsection}{<company>}{<years>}{<title>}{<company_location>}
        \item <achievement>
    \end{rSubsection}
\end{rSection}
\begin{rSection}{Projects}
    \begin{rSubsection}{<project name>}{<years or blank>}{<technologies, comma-joined>}{\href{<link>}{<short link>}}
        \item <description or achievement>
    \end{rSubsection}
\end{rSection}
\begin{rSection}{Education}
    \textbf{<university>} \hfill \textit{<years>} \\
    <degree> \\
    <details joined with \\>
\end{rSection}
\begin{rSection}{Technical Strengths}
    \begin{tabular}{@{} >{\bfseries}l @{\hspace{6ex}} l @{}}
        Languages & <skills.programming joined> \\
        Frameworks & <skills.frameworks joined> \\
        Tools & <skills.tools joined>
    \end{tabular}
\end{rSection}
\end{document}
```

## Mapping from knowledge.yaml

| yaml | LaTeX |
|---|---|
| `name` | `\name{}` |
| `location`, `email`, `phone`, links | `\address{}` lines (max 3) |
| `profile` | `rSection{Summary}` prose |
| `experience[]` | `rSubsection{company}{years}{title}{company_location}` + `\item` per achievement |
| `projects[]` | `rSubsection{name}{years}{technologies}{link}` + `\item` lines |
| `education[]` | `\textbf{university} \hfill \textit{years} \\ degree \\ details` |
| `skills.*` | rows of the Technical Strengths tabular (label & values) |
| `certifications`, `awards`, `teaching`, `events` | additional `rSection` blocks; keep to one line each |

## Gotchas

- `rSubsection` takes exactly 4 braces; leave one empty (`{}`) rather than omitting it.
- `\address` is a stack: the first call sets address one, the second address two, the third address three. A fourth call is ignored.
- The `\\` inside `\address{}` is rewritten to `\addressSep` (a diamond), so it never line-breaks. Keep each `\address` short.
- `&` in the skills tabular is a column separator; escape `&` in company names (`\&`) everywhere else.
- `>{\bfseries}l` needs the `array` package, which `resume.cls` already loads.
- Section order is free; the class does not renumber anything. Reorder for relevance.
