# Template 5 — Wilson CV (`structure.tex`, UK-style)

**Compiler:** xelatex (bundled Erewhon fonts in `fonts/`, case-sensitive directory name; `%!TEX program = xelatex` marker in the template). **Best for:** UK/Commonwealth-style professional CVs with personal details and referees; multi-section, two pages typical; finance, consulting, senior engineering.

## Skeleton

```latex
%!TEX program = xelatex
\documentclass[10pt]{article}
\input{structure.tex}
\begin{document}
\title{<name> -- Résumé}
\parbox{0.5\textwidth}{\begin{tabbing}
    \hspace{3cm} \= \hspace{4cm} \= \kill
    {\bf Address} \> <location> \\
    {\bf Date of Birth} \> <date_of_birth> \\      % omit line if not in yaml
    {\bf Nationality} \> <nationality>               % omit line if not in yaml
\end{tabbing}}
\hfill
\parbox{0.5\textwidth}{\begin{tabbing}
    \hspace{3cm} \= \hspace{4cm} \= \kill
    {\bf Mobile} \> <phone> \\
    {\bf Email} \> \href{mailto:<email>}{<email>} \\
    {\bf Web} \> \href{<website>}{<website display>}
\end{tabbing}}
\section{Personal Profile}
<profile prose>
\section{Education}
\tabbedblock{
    \bf{<years>} \> <degree> - \href{<university url or blank>}{<university>} \\[5pt]
    \> <detail line> \\
}
\section{Employment History}
\job{<start>}{<end>}{<company>, <company_location>}{<company website or blank>}{<title>}{
    <one-sentence description>\\
    \begin{itemize-noindent} \item{<achievement>} \end{itemize-noindent}
    \rule{0mm}{5mm}\textbf{Technologies:} <comma list>.}
\section{Projects}          % reuse \job{<start>}{<end>}{<name>}{<link or blank>}{<technologies>}{<description>}
\section{Skills}
\skillgroup{<group>}{\textit{<item>} - <note>\\ \textit{<item>}}
\section{Interests}
\interestsgroup{\interest{<interest>} \interest{<interest>}}
\section{Referees}
\parbox{0.5\textwidth}{\begin{tabbing}
    \hspace{2.75cm} \= \hspace{4cm} \= \kill
    {\bf Name} \> <ref name> \\ {\bf Company} \> <org> \\ {\bf Position} \> <position> \\ {\bf Contact} \> \href{mailto:<email>}{<email>}
\end{tabbing}}
\end{document}
```

## Mapping from knowledge.yaml

| yaml | LaTeX |
|---|---|
| `name` | `\title{<name> -- Résumé}` (or `-- Curriculum Vitae`) |
| `location`, `date_of_birth`, `nationality` | left header block (drop rows that are absent) |
| `phone`, `email`, `website`/`linkedin`/`github` | right header block |
| `profile` | Personal Profile prose |
| `education[]` | `\tabbedblock{ \bf{years} \> degree - university \\[5pt] \> details }` |
| `experience[]` | `\job{start}{end}{company, location}{website}{title}{description + itemize-noindent of achievements}` |
| `projects[]` | `\job{years}{}{name}{link}{technologies}{description}` |
| `skills.*` | one `\skillgroup{Group}{...}` per group |
| `interests[]` | `\interestsgroup{\interest{...}}` |
| `references[]` | Referees blocks (two side-by-side `\parbox{0.5\textwidth}`); otherwise `Referees available on request.` |
| `certifications`, `awards`, `publications`, `events` | extra `\section{}` with `\tabbedblock` rows |

## Gotchas

- `\job` takes exactly 6 braces: `{start}{end}{employer}{url}{title}{body}`. Arg 4 is always wrapped in `\href{#4}{#3}`; pass `{}` when there is no URL.
- Inside `tabbing`, `\>` jumps to the next tab stop and `\+` indents following lines; `\\[5pt]` adds space. Do not put `itemize` directly inside `tabbing`; the `\job` body is already in a `minipage`, so `itemize-noindent` is safe there.
- Escape `%` (`80\%`) and `#` (`C\#`) in grades and tech names.
- A4 paper with `\pageref{LastPage}` footer ("1 of 2"): compile twice (build.sh does).
- Fonts load from `./fonts/` with `Path = ./fonts/`; the directory must sit next to `resume.tex`.
- `hyperref` is loaded by `structure.tex` without `hidelinks`; some viewers draw boxes around links. Acceptable; do not load hyperref again.
- Date of birth and nationality are expected by this style but are optional in the yaml; omit the rows rather than inventing values.
