# LaTeX Support

This document describes the LaTeX features currently supported by the Julia parser and dynview math replay pipeline, and the recommended way to use them in animation view text.

## Recommended Usage Pattern

Use `EuclidLatex.replay_emit_math_block!` for broad inline math rendering in dynview.

1. Keep a plain fallback string in `get_view_text`.
2. Open a dynview block with `dynview_reset_stream` and `dynview_begin_block`.
3. Emit ordinary text runs as needed.
4. Emit LaTeX math with `replay_emit_math_block!`.
5. Close with `dynview_end_block`.
6. On any status failure, return fallback text.

Minimal pattern:

```julia
fallback = "Some plain fallback text"

if OdinJuliaBridge.dynview_reset_stream(state_ptr) != OdinJuliaBridge.BRIDGE_STATUS_OK ||
   OdinJuliaBridge.dynview_begin_block(
       state_ptr,
       OdinJuliaBridge.BRIDGE_DYNVIEW_BLOCK_OUTPUT,
       Int32(1)) != OdinJuliaBridge.BRIDGE_STATUS_OK
    return fallback
end

if !EuclidLatex.replay_emit_math_block!(
        state_ptr,
        "\\sum_{i=1}^{n} a_i + \\frac{x^2}{y} + \\left(\\sqrt{z}\\right)")
    return fallback
end

if OdinJuliaBridge.dynview_end_block(state_ptr) != OdinJuliaBridge.BRIDGE_STATUS_OK
    return fallback
end

return fallback
```

## Supported LaTeX

The current implementation supports these major groups:

- Unicode substitution commands for many Greek letters, operators, relations, arrows, and set symbols.
- Upright text operators like `\sin`, `\cos`, `\log`, `\lim`, `\max`.
- `\text{...}` for non-italic text inside math.
- Scripts: `^` and `_` including grouped forms.
- Fractions: `\frac{...}{...}`.
- Radicals: `\sqrt{...}` and `\sqrt[n]{...}`.
- Accent bars: `\overline{...}` and `\underline{...}`.
- Stretch delimiters: `\left ... \right` with mixed delimiter pairs.
- Large operators with limits: `\sum`, `\prod`, `\int`, `\lim`.
- Matrix blocks: `\begin{matrix} ... \end{matrix}` with `&` column separators and `\\` row separators.

## Character Support

Character handling is currently practical and intentionally limited. Command support is a fixed map in `src/julia/latex.jl` (`UNICODE_COMMAND_MAP` and `MATHBB_UPPERCASE_MAP`), not general TeX compatibility.

| Input Type | Support Level | Examples | Notes |
| --- | --- | --- | --- |
| ASCII letters/digits/punctuation | Supported | `a`, `x_1`, `+`, `(`, `)` | Best default for authored math source. |
| Structural control characters | Supported | `\`, `{`, `}`, `[`, `]`, `^`, `_`, `&` | These are parser-significant for commands, grouping, scripts, and matrices. |
| LaTeX command substitutions | Supported (fixed list only) | `\alpha`, `\leq`, `\mathbb{R}` | Only mapped commands are supported; unknown commands are not auto-implemented. |
| `\text{...}` plain text content | Supported | `\text{Area}`, `\text{TEMP TEST}` | Use for upright words inside math mode. |
| Raw Unicode math symbols typed directly | Limited / best-effort | `α`, `≤`, `∑` | May render as plain glyphs, but command forms are more reliable for parser/style behavior. |
| Arbitrary TeX-special characters/environments | Not generally supported | `#`, `%`, `\begin{array}` | Outside current command/environment coverage unless explicitly listed in this document. |

Practical rule: if a symbol matters, prefer its LaTeX command form over raw character entry.

### Greek Letter Command Coverage (Current Fixed Set)

| Category | Supported Commands |
| --- | --- |
| Lowercase Greek | `\alpha`, `\beta`, `\gamma`, `\delta`, `\epsilon`, `\varepsilon`, `\zeta`, `\eta`, `\theta`, `\vartheta`, `\iota`, `\kappa`, `\varkappa`, `\lambda`, `\mu`, `\nu`, `\xi`, `\pi`, `\rho`, `\varrho`, `\sigma`, `\varsigma`, `\tau`, `\upsilon`, `\phi`, `\varphi`, `\chi`, `\psi`, `\omega` |
| Uppercase Greek | `\Gamma`, `\Delta`, `\Theta`, `\Lambda`, `\Xi`, `\Pi`, `\Sigma`, `\Upsilon`, `\Phi`, `\Psi`, `\Omega` |
| Hebrew-style symbols | `\aleph`, `\beth`, `\gimel`, `\daleth` |

### Math Symbol Command Coverage (Current Fixed Set)

| Category | Supported Commands |
| --- | --- |
| Arithmetic/operators | `\pm`, `\times`, `\div`, `\cdot` |
| Calculus/analysis | `\infty`, `\partial`, `\nabla`, `\propto` |
| Logic/quantifiers | `\forall`, `\exists`, `\neg`, `\land`, `\lor` |
| Set relations/ops | `\in`, `\notin`, `\subset`, `\subseteq`, `\supset`, `\supseteq`, `\cup`, `\cap` |
| Relations | `\leq`, `\geq`, `\neq`, `\approx`, `\equiv` |
| Arrows | `\to`, `\leftarrow`, `\Rightarrow`, `\Leftarrow`, `\iff` |
| Delimiter glyph commands | `\lceil`, `\rceil`, `\lfloor`, `\rfloor`, `\vert`, `\|`, `\Vert`, `\backslash`, `\{`, `\}` |

### `\mathbb` Coverage

| Input | Support |
| --- | --- |
| `\mathbb{A}` to `\mathbb{Z}` (uppercase only) | Supported via `MATHBB_UPPERCASE_MAP` |
| `\mathbb{a}` or other non-uppercase forms | Not supported (falls back; no lowercase map) |

If a Greek letter or symbol command is not in the tables above, treat it as unsupported for now.

## Matrix Notes

Matrix support is currently MVP-level:

- Supported: `\begin{matrix}...\end{matrix}`.
- Supported inside cells: other structured math primitives (fractions, radicals, scripts, etc.).
- Not yet included in MVP: `pmatrix`, `bmatrix`, `vmatrix` shortcuts as dedicated parser forms.

Rows must be rectangular. If matrix shape is malformed, parser recovery falls back safely rather than crashing the frame path.

## Delimiter Notes

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

## Practical Authoring Tips

- Prefer one semantic LaTeX expression over manually spaced pseudo-layout text.
- Keep fallback text readable on its own.
- Keep LaTeX strings stable across frames when possible to maximize cache reuse.
- Use `\text{...}` for words or labels that should not be italicized.
- Use grouped scripts (`x^{n+1}`, `a_{ij}`) for clarity.

## Known Limitations

- No full TeX environment coverage beyond current command set.
- Matrix wrapper environments like `pmatrix`/`bmatrix` are not yet first-class parser commands.
- Recovery is designed to preserve rendering continuity, not to provide full TeX-grade diagnostics yet.

## Summary

For animation view text, `replay_emit_math_block!` is the right default for broad LaTeX support. It already covers scripts, fractions, radicals, large operators, stretch delimiters, and matrix blocks in one consistent replay path.
