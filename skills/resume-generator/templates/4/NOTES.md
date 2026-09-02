# Template 4 — ModernCV (bundled `moderncv.cls` v1.2.0, 2012)

**Compiler:** pdflatex. **Best for:** continental-European applications where a photo, date of birth, and nationality are customary; A4; two pages typical. Has a built-in cover letter.

## Skeleton

```latex
\documentclass[11pt,a4paper,sans]{moderncv}   % sans|roman; 10-12pt
\moderncvstyle{casual}                         % casual|classic|oldstyle|banking
\moderncvcolor{blue}                           % blue|orange|green|red|purple|grey|black
\usepackage[scale=0.75]{geometry}
\firstname{<first name>}
\familyname{<last name>}          % this bundled version uses \familyname, NOT \lastname
\title{<headline, e.g. Machine Learning Engineer>}
\address{<street or city>}{<postcode city, country>}
\mobile{<phone>}
\email{<email>}
\homepage{<url>}{<display text>}  % two arguments in this bundled version
\extrainfo{<born YYYY-MM-DD, nationality; linkedin/github display>}
\photo[70pt][0.4pt]{photo}        % ONLY when knowledge.yaml has `photo:`; path without extension
\begin{document}
% ---- optional cover letter (only when requested) ----
\recipient{<team or hiring manager>}{<company>\\<address>}
\date{\today}
\opening{Dear <name>,}
\closing{Sincerely,}
\enclosure[Attached]{curriculum vitae}
\makelettertitle
<letter paragraphs>
\makeletterclosing
\newpage
% ---- CV ----
\makecvtitle
\section{Education}
\cventry{<years>}{<degree>}{<university>}{<location>}{<grade or blank>}{<details, one sentence>}
\section{Experience}
\cventry{<years>}{<title>}{\textsc{<company>}}{<location>}{}{<one-sentence description>
\begin{itemize} \item <achievement> \end{itemize}}
\section{Projects}
\cventry{<years>}{<name>}{<technologies>}{}{}{<description> (\href{<link>}{<short link>})}
\section{Skills}
\cvitem{Programming}{<skills.programming joined>}
\cvitem{Frameworks}{<skills.frameworks joined>}
\cvitem{Tools}{<skills.tools joined>}
\section{Languages}
\cvitemwithcomment{<language>}{<level>}{<certificate or blank>}
\section{Certifications}
\cvitem{<issued>}{<name>, <provider>}
\section{Interests}
\cvlistdoubleitem{<interest>}{<interest>}
\end{document}
```

## Mapping from knowledge.yaml

| yaml | LaTeX |
|---|---|
| `name` | split into `\firstname{}` / `\familyname{}` (last whitespace-separated token = family name unless obviously wrong) |
| `location` | `\address{}{}` (street blank if unknown: `\address{}{<location>}`) |
| `phone`, `email`, `website`/`linkedin`/`github` | `\mobile`, `\email`, `\homepage{url}{display}`; extra links go into `\extrainfo` as `\href` |
| `date_of_birth`, `nationality` | `\extrainfo{Born <date>, <nationality>}`; omit when absent |
| `photo` | copy the file into the output dir, then `\photo[70pt][0.4pt]{<basename without extension>}`; omit the line when absent |
| `profile` | `\section{Profile}` + `\cvitem{}{<prose>}` |
| `education[]` | `\cventry{years}{degree}{university}{location}{grade}{details}` |
| `experience[]` | `\cventry{years}{title}{\textsc{company}}{company_location}{}{description + itemize of achievements}` |
| `projects[]` | `\cventry{years}{name}{technologies}{}{}{description}` |
| `skills.*` | `\cvitem{Group}{list}` rows |
| `skills.languages[]` | `\cvitemwithcomment{name}{level}{certificate}` |
| `certifications`, `awards`, `publications`, `events` | `\cvitem{<year/date>}{<text>}` rows |
| `interests[]` | `\cvlistdoubleitem{a}{b}` pairs, `\cvlistitem{}` for an odd last one |

## Gotchas

- `\cventry` takes exactly 6 braces; empty ones must still be present.
- Do not use `\name{}{}` or `\lastname{}` (newer moderncv API); this bundled class predates them.
- `\photo` needs `graphicx` (loaded by the class) and a file the compiler can find; never reference the bundled `pictures/picture.jpg` sample.
- The cover-letter block in `template.tex` is sample content: drop it unless a cover letter was requested with this template, in which case fill it from `cover-letter.md` instead of generating a separate file.
- `\usepackage{lipsum}` was removed from the template; never add it back.
- All `moderncv*.sty` files and `tweaklist.sty` must sit next to `resume.tex` (Step 4 copies them).
- Escape `&` in `\cvitem` text and company names.
- For a non-English resume add `\usepackage[italian]{babel}` (or the relevant language) right after `geometry`; the class handles the headings you write.
