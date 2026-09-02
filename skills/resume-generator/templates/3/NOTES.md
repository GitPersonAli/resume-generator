# Template 3 — Freeman Academic CV (`FreemanCV.cls`)

**Compiler:** xelatex (bundled fonts in `Fonts/`, case-sensitive directory name). **Best for:** research, PhD, postdoc, faculty, and other CVs with a publications list; two-column layout, two pages typical.

## Skeleton

```latex
\documentclass[10pt]{FreemanCV}
\columnratio{0.55, 0.45}
\begin{document}
\begin{paracol}{2}
% ---------- LEFT column ----------
\parbox[][0.11\textheight][c]{\linewidth}{\centering {\sffamily\Huge <name>} \medskip {\cursivefont\Huge\textcolor{headings}{Curriculum Vitae}} \vfill}
\section{Research}                 % or "Doctoral Research": thesis title + abstract prose
\section{Work Experience}
\jobentry{<years>}{<FT/PT or blank>}{<company>}{<title>}{<description or achievements joined into prose>}
\section{Projects}                 % optional: reuse \jobentry{<years>}{}{<project name>}{<technologies>}{<description>}
\section{References}               % or \textit{References available on request}
\begin{supertabular}{r l}
    \tableentry{}{\textbf{<ref name>}}{spaceafter}
    \tableentry{Position}{<position>}{}
    \tableentry{Email}{\href{mailto:<email>}{<email>}}{}
\end{supertabular}
\switchcolumn
% ---------- RIGHT column ----------
\parbox[top][0.11\textheight][c]{\linewidth}{\colorbox{shade}{
    \begin{supertabular}{@{\hspace{3pt}} p{0.05\linewidth} | p{0.775\linewidth}}
        \raisebox{-1pt}{\faHome} & <location> \\
        \raisebox{-1pt}{\faPhone} & <phone> \\
        \raisebox{-1pt}{\small\faEnvelope} & \href{mailto:<email>}{<email>} \\
        \raisebox{-1pt}{\small\faDesktop} & \href{<website>}{<website display>} \\
        \raisebox{-1pt}{\faGithub} & \href{<github>}{<github display>} \\
        \raisebox{-1pt}{\faLinkedinSquare} & \href{<linkedin>}{<linkedin display>} \\
    \end{supertabular}} \vfill}
\section{Education}
\begin{supertabular}{r l}
    \qualificationentry{<years>}{<degree>}{<honors or blank>}{<department or blank>}{<university>}
\end{supertabular}
\section{Awards}            % \tableentry{<year>}{\textbf{<award>}}{spaceafter}
\section{Computer Skills}   % \tableentry{<group>}{<comma list>}{spaceafter}
\section{Skills}            % \subsection{<soft skill>} + one sentence
\section{Publications}
<full citation with \textbf{<your name>}> \medskip
\subsection{Publications by DOI}
\begin{supertabular}{r l}
    \doipublication{<year>}{<doi>}{firstauthor}{spaceafter}
\end{supertabular}
\end{paracol}
\end{document}
```

## Mapping from knowledge.yaml

| yaml | LaTeX |
|---|---|
| `name` | left-column name box |
| `location`, `phone`, `email`, `website`, `github`, `linkedin` | rows of the shaded contact box (drop rows you don't have; keep the `\\`) |
| `education[].thesis` or `research_interests` | `\section{Research}` prose |
| `experience[]` | `\jobentry{years}{work_mode or blank}{company}{title}{achievements joined as prose}` |
| `projects[]` | `\jobentry{years}{}{name}{technologies}{description}` |
| `education[]` | `\qualificationentry{years}{degree}{honors}{department}{university}` |
| `awards[]`, `certifications[]`, `events[]` | `\tableentry` rows |
| `skills.programming/frameworks/tools` | `\tableentry{<group>}{<list>}{spaceafter}` under Computer Skills |
| `skills.languages` | `\tableentry{<language>}{<level>}{}` under a Languages section |
| `publications[]` | citation paragraphs and/or `\doipublication` rows |
| `references[]` | References table |

## Gotchas

- `\jobentry` and `\qualificationentry` take exactly 5 braces; `\tableentry` 3; `\doipublication` 4. Pass `{}` for unused ones.
- `supertabular{r l}` columns do not wrap: keep each `\tableentry` content under ~40 characters and split long items across rows (second row with an empty heading).
- The contact box height (`0.11\textheight`) must match the name box on the left; more than 6 contact rows overflows it.
- Icons come from the bundled FontAwesome font: `\faHome`, `\faPhone`, `\faEnvelope`, `\faDesktop`, `\faGithub`, `\faLinkedinSquare` (see `Fonts/fontawesome.pdf` for more).
- Column balancing is manual: if the left column runs long, move Awards/Skills to the left or shorten descriptions.
- `hyperref` is loaded by the class; do not load it again. Uses `\href` directly.
- `&` inside `\tableentry` content must be `\&` (the table itself uses `&`).
- Two-column layouts extract poorly through ATS text parsers; warn the user when the posting looks ATS-driven.
