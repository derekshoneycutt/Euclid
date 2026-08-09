# LaTeX Support

This document describes the LaTeX subset supported by the Julia parser and
Dynview replay pipeline. The implementation supports both standalone math and
mixed document fragments containing styled prose, inline or display math, line
breaks, and Euclid inline shapes.

## Table Of Contents

1. [Recommended Usage](#recommended-usage)
1. [Modes And Classification](#modes-and-classification)
1. [Document Mode](#document-mode)
1. [Math Mode](#math-mode)
1. [Character Support](#character-support)
1. [Matrix Support](#matrix-support)
1. [Delimiter Support](#delimiter-support)
1. [Cache And Invalidation](#cache-and-invalidation)
1. [Fallback And Failure Behavior](#fallback-and-failure-behavior)
1. [Practical Authoring Tips](#practical-authoring-tips)
1. [Known Limitations](#known-limitations)
1. [Summary](#summary)

## Recommended Usage

Use `EuclidLatex.emit_latex_view_text!` for complete animation view text. It
classifies the source as math or document mode, emits the supplied fallback as
the copy payload, builds one complete Dynview stream, and always returns the
fallback string expected by `get_view_text`.

```julia
const DefinitionLatexDocument = raw"""\textbf{Definition 1.}

A point is that which has no part. The symbol $A_1$ marks a point.

\euclidpoint[color=plum1,size=1]
"""

const DefinitionFallback = "Definition 1. A point is that which has no part."

function get_view_text(state_ptr)
    EuclidLatex.emit_latex_view_text!(
        state_ptr,
        DefinitionLatexDocument,
        DefinitionFallback)
end
```

Use `replay_emit_math_block!` when a Dynview block is already open and only one
math expression needs to be inserted. It emits one recursive, non-wrapping math
block and returns `false` on bridge failure.

Use `emit_latex_dynview!` for a standalone math-only Dynview block when the
caller does not need to mix prose or shapes.

## Modes And Classification

`classify_latex_mode` selects one of two modes:

| Mode | Intended source | Main API |
| --- | --- | --- |
| Math | One standalone expression | `replay_emit_math_block!`, `emit_latex_dynview!` |
| Document | Prose mixed with styling, math, breaks, or shapes | `emit_latex_view_text!` |

A fragment enclosed entirely by `$...$`, `$$...$$`, `\(...\)`, or `\[...\]`
is classified as math. Otherwise, document markers such as `\textbf`,
`\textit`, `\emph`, `\newline`, `\\`, `\euclid...`, or embedded math
delimiters select document mode. Plain unmarked source is treated as math for
backward compatibility.

`emit_latex_view_text!` strips a complete outer math delimiter before compiling
math mode. In document mode it parses the full source into typed document runs;
partial document parsing is not accepted.

## Document Mode

Document mode supports a deliberately small LaTeX-like prose language:

- Plain Unicode text.
- `\textbf{...}` for bold text.
- `\textit{...}` and `\emph{...}` for italic text.
- `\textcolor{color}{...}` for inline prose color.
- Nested style commands; flags accumulate, so bold italic text is supported.
- Inline math with `$...$` or `\(...\)`.
- Display math with `$$...$$` or `\[...\]`.
- Forced line breaks with `\\` or `\newline`.
- Paragraph breaks from a blank source line.
- Inline Euclid shapes through `\euclidpoint`, `\euclidline`,
  `\euclidcircle`, and `\euclidbox`.

A single source newline in prose normalizes to one space. A blank line emits a
paragraph break. Display math receives surrounding line breaks unless adjacent
document runs already provide them.

### Inline Text Colors

`\textcolor{color}{...}` applies a brush color to nested document text while
preserving bold and italic font flags. Color names resolve in this order:

1. Common LaTeX names: `black`, `blue`, `brown`, `cyan`, `darkgray`, `gray`,
    `green`, `lightgray`, `lime`, `magenta`, `olive`, `orange`, `pink`,
    `purple`, `red`, `teal`, `violet`, `white`, and `yellow`.
1. Euclid's Julia palette: `julia_blue`, `julia_red`, `julia_green`, and
    `julia_purple`.
1. Color names accepted by Colors.jl, such as `steelblue`.
1. The enclosing document color when the name is unresolved; at the root this
    means the caller's normal Dynview text color.

Color wrappers may be nested with each other and with `\textbf`, `\textit`,
or `\emph`. This basic support colors prose text runs; embedded math and inline
Euclid shapes retain their own rendering color rules.

```julia
raw"Normal \textcolor{red}{red and \textbf{bold red}} normal"
raw"\textcolor{julia_blue}{Julia blue}"
raw"\textcolor{steelblue}{Colors.jl named color}"
```

### Inline Euclid Shapes

Shape commands accept an optional comma-separated bracket payload. Keys cannot
be duplicated, dimensions must be finite and positive, booleans are strictly
`true` or `false`, and colors must resolve through the bridge color vocabulary.

- `\euclidpoint`: options are `color` and `size`. The default is `size=1`,
    and points are always filled.
- `\euclidline`: options are `color`, `length`, and `thickness`. Defaults are
    `length=3` and `thickness=1`.
- `\euclidcircle`: options are `color`, `size`, `thickness`, and `filled`.
    Defaults are `size=1`, `thickness=1`, and `filled=false`.
- `\euclidbox`: options are `color`, `width`, `height`, `thickness`, and
    `filled`. Defaults are `width=2`, `height=1`, `thickness=1`, and
    `filled=false`.

The shorthand option `filled` is equivalent to `filled=true`.

Examples:

```julia
raw"\euclidpoint[color=steelblue,size=1]"
raw"\euclidline[color=steelblue,length=4,thickness=2]"
raw"\euclidcircle[color=khaki3,size=2,filled]"
raw"\euclidbox[width=3,height=2,thickness=1,filled=false]"
```

Document mode does not implement general LaTeX commands or environments.
Unknown commands, malformed delimiters, invalid shape options, or unmatched
style braces cause document parsing to fail and structured output to fall back.

## Math Mode

Math mode supports these major groups:

- Unicode substitution commands for many Greek letters, operators, relations,
  arrows, and set symbols.
- Upright text operators like `\sin`, `\cos`, `\log`, `\lim`, `\max`.
- `\text{...}` and `\mathrm{...}` for non-italic text inside math.
- Scripts: `^` and `_` including grouped forms.
- Fractions: `\frac{...}{...}`.
- Radicals: `\sqrt{...}` and `\sqrt[n]{...}`.
- Accent bars: `\overline{...}` and `\underline{...}`.
- Stretch delimiters: `\left ... \right` with mixed delimiter pairs.
- Large operators with limits: `\sum`, `\prod`, `\int`, `\lim`.
- Matrix blocks: `\begin{matrix} ... \end{matrix}` and
    `\begin{array}{...} ... \end{array}` with `&` column separators and `\\`
    row separators.
- Matrix wrapper environments composed through stretch delimiters: `bmatrix`,
    `pmatrix`, and `vmatrix`.

## Character Support

Character handling is practical and intentionally limited. Command support is
a fixed map in `src/julia/latex.jl`: `UNICODE_COMMAND_MAP` and
`MATHBB_UPPERCASE_MAP`. It is not general TeX compatibility.

- ASCII letters, digits, and punctuation are the best default for authored
    math source. Examples include `a`, `x_1`, `+`, `(`, and `)`.
- `\`, `{`, `}`, `[`, `]`, `^`, `_`, and `&` are parser-significant structural
    characters.
- Fixed command substitutions such as `\alpha`, `\leq`, and `\mathbb{R}` are
    supported only when listed below.
- `\text{...}` supports upright plain text inside math mode.
- Raw Unicode math symbols such as `α`, `≤`, and `∑` render best effort. Command
    forms are more reliable for parser and style behavior.
- Arbitrary TeX-special characters and unlisted environments are unsupported.

Practical rule: if a symbol matters, prefer its LaTeX command form over raw character entry.

### Greek Letter Command Coverage (Current Fixed Set)

- Lowercase Greek: `\alpha`, `\beta`, `\gamma`, `\delta`, `\epsilon`,
  `\varepsilon`, `\zeta`, `\eta`, `\theta`, `\vartheta`, `\iota`, `\kappa`,
  `\varkappa`, `\lambda`, `\mu`, `\nu`, `\xi`, `\pi`, `\rho`, `\varrho`,
  `\sigma`, `\varsigma`, `\tau`, `\upsilon`, `\phi`, `\varphi`, `\chi`,
    `\psi`, `\omega`, `\varpi`, and `\digamma`.
- Uppercase Greek: `\Gamma`, `\Delta`, `\Theta`, `\Lambda`, `\Xi`, `\Pi`,
  `\Sigma`, `\Upsilon`, `\Phi`, `\Psi`, `\Omega`.
- Hebrew-style symbols: `\aleph`, `\beth`, `\gimel`, `\daleth`.

### Math Symbol Command Coverage (Current Fixed Set)

- Basic operators: `\pm`, `\mp`, `\times`, `\div`, `\cdot`, `\ast`, `\star`,
    `\bullet`, `\circ`, `\diamond`, `\rtimes`, `\setminus`, and `\wr`.
- Circled and square operators: `\oplus`, `\ominus`, `\otimes`, `\oslash`,
    `\odot`, `\bigcirc`, `\sqcap`, `\sqcup`, and `\uplus`.
- Triangle operators: `\bigtriangleup`, `\bigtriangledown`, `\triangleleft`,
    `\triangleright`, `\lhd`, `\rhd`, `\unlhd`, and `\unrhd`.
- Additional operators: `\dagger`, `\ddagger`, and `\amalg`.
- Calculus and analysis: `\infty`, `\partial`, `\nabla`, `\propto`, `\oint`,
    `\iint`, `\iiint`, and `\coprod`.
- Logic and quantifiers: `\forall`, `\exists`, `\nexists`, `\neg`, `\land`,
    `\lor`, `\wedge`, `\vee`, `\therefore`, `\because`, `\top`, and `\bot`.
- Set membership: `\in`, `\notin`, `\ni`, `\owns`, and `\notni`.
- Set relations: `\subset`, `\subseteq`, `\subsetneq`, `\nsubseteq`,
    `\supset`, `\supseteq`, `\supsetneq`, `\nsupseteq`, `\sqsubset`,
    `\sqsubseteq`, `\sqsupset`, and `\sqsupseteq`.
- Set operations: `\cup`, `\cap`, `\emptyset`, `\varnothing`, and
    `\complement`.
- Ordering and equality: `\le`, `\leq`, `\ge`, `\geq`, `\ll`, `\gg`, `\ne`,
    `\neq`, `\approx`, `\equiv`, `\prec`, `\succ`, `\preceq`, and `\succeq`.
- Relatedness: `\sim`, `\simeq`, `\cong`, `\asymp`, `\doteq`, `\parallel`,
    `\nparallel`, `\mid`, `\nmid`, `\perp`, `\models`, `\vdash`, `\dashv`,
    `\bowtie`, `\smile`, and `\frown`.
- Basic arrows: `\to`, `\rightarrow`, `\leftarrow`, `\leftrightarrow`,
    `\uparrow`, `\downarrow`, `\updownarrow`, `\Rightarrow`, `\Leftarrow`,
    `\Leftrightarrow`, `\iff`, `\Uparrow`, `\Downarrow`, and `\Updownarrow`.
- Long and hooked arrows: `\longleftarrow`, `\longrightarrow`,
    `\longleftrightarrow`, `\Longleftarrow`, `\Longrightarrow`,
    `\Longleftrightarrow`, `\hookleftarrow`, `\hookrightarrow`, and `\mapsto`.
- Directional and harpoon arrows: `\nearrow`, `\searrow`, `\swarrow`,
    `\nwarrow`, `\leftharpoonup`, `\leftharpoondown`, `\rightharpoonup`,
    `\rightharpoondown`, `\rightleftharpoons`, `\leftrightharpoons`, and
    `\leadsto`.
- Dots: `\dots`, `\ldots`, `\cdots`, `\vdots`, and `\ddots`.
- Letterlike and geometric symbols: `\prime`, `\hbar`, `\ell`, `\Re`, `\Im`,
    `\wp`, `\mho`, `\angle`, `\measuredangle`, `\sphericalangle`, `\triangle`,
    `\Box`, `\square`, `\Diamond`, `\lozenge`, and `\surd`.
- Suits, music, and marks: `\clubsuit`, `\diamondsuit`, `\heartsuit`,
    `\spadesuit`, `\flat`, `\natural`, `\sharp`, `\checkmark`, and `\degree`.
- Spacing: `\;` maps to one normal space.
- Delimiter glyphs: `\lceil`, `\rceil`, `\lfloor`, `\rfloor`, `\vert`, `\|`,
    `\Vert`, `\backslash`, `\{`, `\}`.

### `\mathbb` Coverage

| Input | Support |
| --- | --- |
| `\mathbb{A}` to `\mathbb{Z}` (uppercase only) | Supported via `MATHBB_UPPERCASE_MAP` |
| `\mathbb{a}` or other non-uppercase forms | Not supported (falls back; no lowercase map) |

If a Greek letter or symbol command is not in the tables above, treat it as unsupported for now.

## Matrix Support

Matrix mode supports rectangular grids and recursive math within cells:

- Supported: `\begin{matrix}...\end{matrix}`.
- Supported: `\begin{array}{...}...\end{array}` with a validated `l/c/r`
    preamble and strict shape checks.
- Supported inside cells: other structured math primitives such as fractions,
    radicals, and scripts.
- Composition wrappers: `bmatrix`, `pmatrix`, and `vmatrix`.
- Canonical wrapper output becomes `\left[...\right]`, `\left(...\right)`, or
    `\left|...\right|` around a `matrix` environment.

Rows must be rectangular. Malformed matrix shape falls back safely rather than
crashing the frame path.

## Delimiter Support

`\left ... \right` is fully structural and can wrap nested constructs like fractions, radicals, and matrices.

Examples:

- `\left( \frac{a}{b} \right)`
- `\left[ a + b \right)`
- `\left(\begin{matrix}a&b\\c&d\end{matrix}\right)`

## Cache and Invalidation

The parser uses a cache keyed by:

- source string,
- parser grammar version,
- style profile.

Available cache APIs:

- `clear_cache!()`
- `cache_size()`
- `cache_max_entries()`
- `prune_cache!(limit)`
- `invalidate_cache_for_source!(source)`
- `invalidate_cache_for_style!(style_profile)`
- `invalidate_cache_for_grammar!(grammar_version)`

In normal animation usage, calling `replay_emit_math_block!` is sufficient and cache behavior is automatic.

The current cache applies to math parsing and compiled math programs. Document
runs are parsed per `emit_latex_view_text!` call; embedded math expressions then
reuse the math cache.

## Fallback And Failure Behavior

Fallback text is part of the API contract, not an exceptional afterthought.
`emit_latex_view_text!` writes the supplied fallback as the Dynview copy payload
and returns that same string whether structured emission succeeds or fails.

Document mode fails closed: unsupported commands, malformed style groups,
unclosed math delimiters, empty math fragments, and invalid Euclid shape options
abort structured emission. Math mode uses parser recovery for unsupported or
malformed constructs where possible. In either case, the host keeps rendering
readable fallback text rather than exposing a partial stream.

Bridge status failures also stop emission. Authors should never make the
structured stream the only source of user-visible meaning.

## Practical Authoring Tips

- Prefer one semantic LaTeX expression over manually spaced pseudo-layout text.
- Keep fallback text readable on its own.
- Use `emit_latex_view_text!` for complete view documents instead of manually
    opening and closing a Dynview block.
- Use raw Julia strings for document source when practical so LaTeX backslashes
    remain readable.
- Keep LaTeX strings stable across frames when possible to maximize cache reuse.
- Use `\text{...}` for words or labels that should not be italicized.
- Use `\textbf`, `\textit`, and `\emph` only in document mode; use `\text` or
    `\mathrm` for upright text inside math.
- Use grouped scripts (`x^{n+1}`, `a_{ij}`) for clarity.

## Known Limitations

- This is not a TeX engine. Macros, packages, declarations, sections, lists,
    tables, equation environments, alignment environments, and general
    `\begin{...}` document environments are unsupported.
- Document styling is limited to nested bold and italic spans. There is no
    document-level font size, color, heading, or alignment syntax.
- Math delimiters in document mode use direct closer search; nested delimiter
    escaping is not general TeX-compatible parsing.
- Matrix support is limited to rectangular `matrix`, validated `array`, and the
    `bmatrix`, `pmatrix`, and `vmatrix` wrappers.
- `\mathbb` supports uppercase Latin letters only.
- Raw Unicode math is best effort; command forms provide more reliable semantic
    styling.
- Parser recovery prioritizes rendering continuity rather than TeX-grade error
    diagnostics.

## Summary

For complete animation view text, use `emit_latex_view_text!` with a readable
fallback. Use `replay_emit_math_block!` for math inserted into an already open
Dynview block. Together, document mode and math mode cover styled prose,
inline/display math, Euclid shapes, scripts, fractions, radicals, large
operators, stretch delimiters, and matrix blocks through one bounded snapshot
and replay pipeline.
