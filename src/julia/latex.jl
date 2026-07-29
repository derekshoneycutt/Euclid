module EuclidLatex

using ..OdinJuliaBridge

export PARSER_GRAMMAR_VERSION,
    clear_cache!,
    cache_size,
    resolve_cache_entry,
    parse_latex,
    compile_emit_program,
    replay_emit_program!,
    replay_emit_math_block!,
    emit_latex_dynview!,
    latex_to_plain_text,
    compiled_program_for

const PARSER_GRAMMAR_VERSION = Int32(10)
const DEFAULT_STYLE_PROFILE = Int32(0)
const SCRIPT_SCALE = Float32(0.62)
const SCRIPT_SUP_RAISE = Float32(0.44)
const SCRIPT_SUB_DROP = Float32(0.30)
const SCRIPT_GAP = Float32(0.04)
const ACCENT_BAR_THICKNESS = Float32(0.08)
const ACCENT_BAR_OFFSET = Float32(0.10)
const RADICAL_BAR_THICKNESS = Float32(0.08)
const RADICAL_BAR_OFFSET = Float32(0.10)
const MATH_OP_TEXT_RUN = Int32(1)
const MATH_OP_MATH_GLYPH_RUN = Int32(2)
const MATH_OP_SCRIPT_ATTACH = Int32(3)
const MATH_OP_ACCENT_BAR = Int32(4)
const MATH_OP_RADICAL_BAR = Int32(5)
const MATH_OP_ACCENT_BAR_RECURSIVE = Int32(6)
const MATH_OP_RADICAL_BAR_RECURSIVE = Int32(7)
const MATH_OP_SCRIPT_ATTACH_RECURSIVE = Int32(8)
const MATH_OP_LARGE_OP_RECURSIVE = Int32(9)
const MATH_OP_FRACTION_RECURSIVE = Int32(10)

const LARGE_OP_KIND_NONE = Int32(0)
const LARGE_OP_KIND_SUM = Int32(1)
const LARGE_OP_KIND_PROD = Int32(2)
const LARGE_OP_KIND_INT = Int32(3)
const LARGE_OP_KIND_LIM = Int32(4)

const TEXT_OPERATOR_COMMANDS = Set([
    "\\arccos", "\\arcsin", "\\arctan", "\\arg", "\\cos", "\\csc", "\\cot",
    "\\coth", "\\deg", "\\det", "\\dim", "\\exp", "\\gcd", "\\hom", "\\inf",
    "\\ker", "\\lg", "\\liminf", "\\limsup", "\\ln", "\\log", "\\max",
    "\\min", "\\Pr", "\\sec", "\\sin", "\\sinh", "\\sup", "\\tan", "\\tanh"
])

const LARGE_OPERATOR_COMMAND_MAP = Dict(
    "\\sum" => ("∑", LARGE_OP_KIND_SUM),
    "\\prod" => ("∏", LARGE_OP_KIND_PROD),
    "\\int" => ("∫", LARGE_OP_KIND_INT),
    "\\lim" => ("lim", LARGE_OP_KIND_LIM))

const UNICODE_COMMAND_MAP = Dict(
    "\\alpha" => "α",
    "\\beta" => "β",
    "\\gamma" => "γ",
    "\\delta" => "δ",
    "\\epsilon" => "ϵ",
    "\\varepsilon" => "ε",
    "\\zeta" => "ζ",
    "\\eta" => "η",
    "\\theta" => "θ",
    "\\vartheta" => "ϑ",
    "\\iota" => "ι",
    "\\kappa" => "κ",
    "\\varkappa" => "ϰ",
    "\\lambda" => "λ",
    "\\mu" => "μ",
    "\\nu" => "ν",
    "\\xi" => "ξ",
    "\\pi" => "π",
    "\\rho" => "ρ",
    "\\varrho" => "ϱ",
    "\\sigma" => "σ",
    "\\varsigma" => "ς",
    "\\tau" => "τ",
    "\\upsilon" => "υ",
    "\\phi" => "φ",
    "\\varphi" => "ϕ",
    "\\chi" => "χ",
    "\\psi" => "ψ",
    "\\omega" => "ω",
    "\\Gamma" => "Γ",
    "\\Delta" => "Δ",
    "\\Theta" => "Θ",
    "\\Lambda" => "Λ",
    "\\Xi" => "Ξ",
    "\\Pi" => "Π",
    "\\Sigma" => "Σ",
    "\\Upsilon" => "Υ",
    "\\Phi" => "Φ",
    "\\Psi" => "Ψ",
    "\\Omega" => "Ω",
    "\\aleph" => "ℵ",
    "\\beth" => "ℶ",
    "\\gimel" => "ℷ",
    "\\daleth" => "ℸ",
    "\\pm" => "±",
    "\\times" => "×",
    "\\div" => "÷",
    "\\cdot" => "·",
    "\\infty" => "∞",
    "\\partial" => "∂",
    "\\nabla" => "∇",
    "\\forall" => "∀",
    "\\exists" => "∃",
    "\\neg" => "¬",
    "\\land" => "∧",
    "\\lor" => "∨",
    "\\in" => "∈",
    "\\notin" => "∉",
    "\\subset" => "⊂",
    "\\subseteq" => "⊆",
    "\\supset" => "⊃",
    "\\supseteq" => "⊇",
    "\\cup" => "∪",
    "\\cap" => "∩",
    "\\to" => "→",
    "\\leftarrow" => "←",
    "\\Rightarrow" => "⇒",
    "\\Leftarrow" => "⇐",
    "\\iff" => "⇔",
    "\\leq" => "≤",
    "\\geq" => "≥",
    "\\neq" => "≠",
    "\\approx" => "≈",
    "\\equiv" => "≡",
    "\\propto" => "∝",
    "\\lceil" => "⌈",
    "\\rceil" => "⌉",
    "\\lfloor" => "⌊",
    "\\rfloor" => "⌋",
    "\\vert" => "|",
    "\\|" => "‖",
    "\\Vert" => "‖",
    "\\backslash" => "∖",
    "\\{" => "{",
    "\\}" => "}")

const MATHBB_UPPERCASE_MAP = Dict(
    "A" => "𝔸",
    "B" => "𝔹",
    "C" => "ℂ",
    "D" => "𝔻",
    "E" => "𝔼",
    "F" => "𝔽",
    "G" => "𝔾",
    "H" => "ℍ",
    "I" => "𝕀",
    "J" => "𝕁",
    "K" => "𝕂",
    "L" => "𝕃",
    "M" => "𝕄",
    "N" => "ℕ",
    "O" => "𝕆",
    "P" => "ℙ",
    "Q" => "ℚ",
    "R" => "ℝ",
    "S" => "𝕊",
    "T" => "𝕋",
    "U" => "𝕌",
    "V" => "𝕍",
    "W" => "𝕎",
    "X" => "𝕏",
    "Y" => "𝕐",
    "Z" => "ℤ")

const MATHBB_GLYPH_TO_SOURCE_MAP = Dict(value => key for (key, value) in MATHBB_UPPERCASE_MAP)

struct LatexToken
    kind::Symbol
    text::String
end

struct LatexRun
    text::String
    role::Symbol
    segment::Symbol
    children::Vector{LatexRun}
    secondary_children::Vector{LatexRun}
end

struct MathPayloadOp
    kind::Int32
    text::String
    radical_index_text::String
    sup_text::String
    sub_text::String
    accent_mode::Symbol
    radical_mode::Symbol
    large_op_kind::Int32
    style_role::Symbol
    children::Vector{MathPayloadOp}
    secondary_children::Vector{MathPayloadOp}
end

struct ParseCacheEntry
    source::String
    grammar_version::Int32
    style_profile::Int32
    tokens::Vector{LatexToken}
    ast::Vector{LatexRun}
    normalized_ast::Vector{LatexRun}
    program::Vector{MathPayloadOp}
end

const parse_cache = Dict{Tuple{String, Int32, Int32}, ParseCacheEntry}()

const EMPTY_CHILD_RUNS = LatexRun[]

"""Return one normal atom run payload."""
latex_atom_run(text::String, role::Symbol) = LatexRun(text, role, :atom, EMPTY_CHILD_RUNS, EMPTY_CHILD_RUNS)

"""Return one superscript script-segment run payload."""
latex_sup_run(text::String) = LatexRun(text, :math, :script_sup, EMPTY_CHILD_RUNS, EMPTY_CHILD_RUNS)

"""Return one subscript script-segment run payload."""
latex_sub_run(text::String) = LatexRun(text, :math, :script_sub, EMPTY_CHILD_RUNS, EMPTY_CHILD_RUNS)

"""Return one overline accent run payload."""
latex_overline_run(children::Vector{LatexRun}) = LatexRun("", :math, :accent_over, children, EMPTY_CHILD_RUNS)

"""Return one underline accent run payload."""
latex_underline_run(children::Vector{LatexRun}) = LatexRun("", :math, :accent_under, children, EMPTY_CHILD_RUNS)

"""Return one square-root radical run payload."""
latex_sqrt_run(children::Vector{LatexRun}, index_text::AbstractString="") =
    LatexRun(String(index_text), :math, :radical_sqrt, children, EMPTY_CHILD_RUNS)

"""Return one fraction run payload with numerator and denominator child runs."""
latex_fraction_run(numerator_children::Vector{LatexRun}, denominator_children::Vector{LatexRun}) =
    LatexRun("", :math, :fraction, numerator_children, denominator_children)

"""Clear all cached parse/compile entries."""
function clear_cache!()
    empty!(parse_cache)
    return nothing
end

"""Return current cache entry count."""
cache_size() = length(parse_cache)

"""Tokenize source into command/group/script/plain-text tokens."""
function tokenize_latex(source::String)
    tokens = LatexToken[]
    i = firstindex(source)
    while i <= lastindex(source)
        c = source[i]
        if c == '{'
            push!(tokens, LatexToken(:lbrace, "{"))
            i = nextind(source, i)
            continue
        end
        if c == '}'
            push!(tokens, LatexToken(:rbrace, "}"))
            i = nextind(source, i)
            continue
        end
        if c == '^'
            push!(tokens, LatexToken(:sup, "^"))
            i = nextind(source, i)
            continue
        end
        if c == '_'
            push!(tokens, LatexToken(:sub, "_"))
            i = nextind(source, i)
            continue
        end
        if c == '['
            push!(tokens, LatexToken(:lbracket, "["))
            i = nextind(source, i)
            continue
        end
        if c == ']'
            push!(tokens, LatexToken(:rbracket, "]"))
            i = nextind(source, i)
            continue
        end
        if c == '\\'
            token, next_i = read_command_token(source, i)
            push!(tokens, token)
            i = next_i
            continue
        end

        token, next_i = read_text_token(source, i)
        push!(tokens, token)
        i = next_i
    end

    return tokens
end

"""Read one LaTeX command token beginning at a backslash byte index."""
function read_command_token(source::String, slash_i::Int)
    i = nextind(source, slash_i)
    if i > lastindex(source)
        return LatexToken(:text, "\\"), i
    end

    c = source[i]
    if isletter(c)
        start_i = slash_i
        j = i
        while j <= lastindex(source) && isletter(source[j])
            j = nextind(source, j)
        end
        return LatexToken(:command, source[start_i:prevind(source, j)]), j
    end

    token = source[slash_i:i]
    return LatexToken(:command, token), nextind(source, i)
end

"""Read one plain-text token until the next control/syntax character."""
function read_text_token(source::String, start_i::Int)
    j = start_i
    while j <= lastindex(source)
        c = source[j]
        if c == '\\' || c == '{' || c == '}' || c == '^' || c == '_' || c == '[' || c == ']'
            break
        end
        j = nextind(source, j)
    end

    if j == start_i
        return LatexToken(:text, ""), j
    end

    return LatexToken(:text, source[start_i:prevind(source, j)]), j
end

"""Parse latex into semantic text/math runs for phase-1 emission."""
function parse_latex(source::AbstractString)
    tokens = tokenize_latex(String(source))
    idx = Ref(1)
    runs = parse_sequence(tokens, idx, false)
    return tokens, runs
end

"""Parse a token sequence, optionally stopping at a closing brace token."""
function parse_sequence(tokens::Vector{LatexToken}, idx::Base.RefValue{Int}, stop_on_rbrace::Bool)
    runs = LatexRun[]
    while idx[] <= length(tokens)
        token = tokens[idx[]]
        if token.kind == :rbrace && stop_on_rbrace
            idx[] += 1
            break
        end

        if token.kind == :lbrace
            idx[] += 1
            append!(runs, parse_sequence(tokens, idx, true))
            continue
        end

        append!(runs, parse_atom(tokens, idx))
        consume_scripts!(runs, tokens, idx)
    end

    return runs
end

"""Parse one atom token into a semantic run list."""
function parse_atom(tokens::Vector{LatexToken}, idx::Base.RefValue{Int})
    token = tokens[idx[]]
    idx[] += 1

    if token.kind == :text
        return [latex_atom_run(token.text, :math)]
    end

    if token.kind != :command
        return [latex_atom_run(token.text, :math)]
    end

    return parse_command_atom(token.text, tokens, idx)
end

"""Parse one command token into a semantic run list."""
function parse_command_atom(
    command::String,
    tokens::Vector{LatexToken},
    idx::Base.RefValue{Int})

    text_runs = parse_special_text_command(command, tokens, idx)
    if !isnothing(text_runs)
        return text_runs
    end

    unicode_runs = parse_unicode_command(command)
    if !isnothing(unicode_runs)
        return unicode_runs
    end

    mathbb_runs = parse_mathbb_atom(command, tokens, idx)
    if !isnothing(mathbb_runs)
        return mathbb_runs
    end

    large_operator_runs = parse_large_operator_atom(command)
    if !isnothing(large_operator_runs)
        return large_operator_runs
    end

    operator_runs = parse_text_operator_atom(command)
    if !isnothing(operator_runs)
        return operator_runs
    end

    structured_runs = parse_structured_math_command(command, tokens, idx)
    if !isnothing(structured_runs)
        return structured_runs
    end

    return [latex_atom_run(command, :math)]
end

"""Parse display-style large operators that accept stacked upper/lower limits."""
function parse_large_operator_atom(command::String)
    value = get(LARGE_OPERATOR_COMMAND_MAP, command, nothing)
    if isnothing(value)
        return nothing
    end

    glyph, large_op_kind = value
    role = large_op_kind == LARGE_OP_KIND_SUM ? :largeop_sum :
        (large_op_kind == LARGE_OP_KIND_PROD ? :largeop_prod :
            (large_op_kind == LARGE_OP_KIND_INT ? :largeop_int : :largeop_lim))
    return [latex_atom_run(glyph, role)]
end

"""Parse special command forms that produce plain text runs."""
function parse_special_text_command(
    command::String,
    tokens::Vector{LatexToken},
    idx::Base.RefValue{Int})

    if command == "\\text"
        return [latex_atom_run(parse_required_group_as_text(tokens, idx), :text)]
    end

    return nothing
end

"""Parse direct Unicode command substitutions."""
function parse_unicode_command(command::String)
    if haskey(UNICODE_COMMAND_MAP, command)
        return [latex_atom_run(UNICODE_COMMAND_MAP[command], :math)]
    end

    return nothing
end

"""Parse `\\mathbb{...}` commands into Unicode set glyphs when mapped."""
function parse_mathbb_atom(
    command::String,
    tokens::Vector{LatexToken},
    idx::Base.RefValue{Int})

    if command != "\\mathbb"
        return nothing
    end

    unicode, parsed = parse_mathbb_command(tokens, idx)
    if parsed
        return [latex_atom_run(unicode, :mathbb)]
    end

    return [latex_atom_run("\\mathbb", :math)]
end

"""Parse upright text-operator commands."""
function parse_text_operator_atom(command::String)
    if command in TEXT_OPERATOR_COMMANDS
        return [latex_atom_run(command_to_text_operator(command), :text)]
    end

    return nothing
end

"""Parse structured math commands that produce child-run nodes."""
function parse_structured_math_command(
    command::String,
    tokens::Vector{LatexToken},
    idx::Base.RefValue{Int})

    if command == "\\overline"
        return [latex_overline_run(parse_required_group_runs(tokens, idx))]
    end

    if command == "\\underline"
        return [latex_underline_run(parse_required_group_runs(tokens, idx))]
    end

    if command == "\\sqrt"
        return [parse_sqrt_run(tokens, idx)]
    end

    if command == "\\frac"
        numerator_children = parse_required_group_runs(tokens, idx)
        denominator_children = parse_required_group_runs(tokens, idx)
        return [latex_fraction_run(numerator_children, denominator_children)]
    end

    return nothing
end

"""Serialize one semantic run back into deterministic plain-text LaTeX form."""
function latex_run_serialized_text(run::LatexRun)
    child_text = ""
    if !isempty(run.children)
        child_text = join((latex_run_serialized_text(child) for child in run.children), "")
    end
    secondary_child_text = ""
    if !isempty(run.secondary_children)
        secondary_child_text = join((latex_run_serialized_text(child) for child in run.secondary_children), "")
    end

    if run.segment == :accent_over
        return "\\overline{" * child_text * "}"
    end
    if run.segment == :accent_under
        return "\\underline{" * child_text * "}"
    end
    if run.segment == :radical_sqrt
        if !isempty(run.text)
            return "\\sqrt[" * run.text * "]{" * child_text * "}"
        end
        return "\\sqrt{" * child_text * "}"
    end
    if run.segment == :fraction
        return "\\frac{" * child_text * "}{" * secondary_child_text * "}"
    end
    return run.text
end

"""Parse one sqrt run with optional single-rune bracket index."""
function parse_sqrt_run(tokens::Vector{LatexToken}, idx::Base.RefValue{Int})
    index_text = parse_optional_single_rune_index(tokens, idx)
    radical_children = parse_required_group_runs(tokens, idx)
    return latex_sqrt_run(radical_children, index_text)
end

"""Parse optional `[n]` index text and accept only one rune in this phase."""
function parse_optional_single_rune_index(tokens::Vector{LatexToken}, idx::Base.RefValue{Int})
    if idx[] > length(tokens) || tokens[idx[]].kind != :lbracket
        return ""
    end

    idx[] += 1
    parts = String[]
    while idx[] <= length(tokens)
        token = tokens[idx[]]
        if token.kind == :rbracket
            idx[] += 1
            break
        end

        if token.kind == :command
            if haskey(UNICODE_COMMAND_MAP, token.text)
                push!(parts, UNICODE_COMMAND_MAP[token.text])
            else
                push!(parts, token.text)
            end
        else
            push!(parts, token.text)
        end

        idx[] += 1
    end

    candidate = String(strip(join(parts, "")))
    return length(candidate) == 1 ? candidate : ""
end

"""Parse one required `{...}` group and return semantic child runs."""
function parse_required_group_runs(tokens::Vector{LatexToken}, idx::Base.RefValue{Int})
    if idx[] > length(tokens) || tokens[idx[]].kind != :lbrace
        return LatexRun[]
    end

    idx[] += 1
    return parse_sequence(tokens, idx, true)
end

"""Parse one required `{...}` group and return its flattened text."""
function parse_required_group_as_text(tokens::Vector{LatexToken}, idx::Base.RefValue{Int})
    runs = parse_required_group_runs(tokens, idx)
    return join((latex_run_serialized_text(run) for run in runs), "")
end

"""Parse `\\mathbb{...}` content and map A-Z to Unicode double-struck glyphs."""
function parse_mathbb_command(tokens::Vector{LatexToken}, idx::Base.RefValue{Int})
    if idx[] > length(tokens) || tokens[idx[]].kind != :lbrace
        return "", false
    end

    content = parse_required_group_as_text(tokens, idx)
    if haskey(MATHBB_UPPERCASE_MAP, content)
        return MATHBB_UPPERCASE_MAP[content], true
    end

    return "", false
end

"""Convert one LaTeX operator command name to its upright text form."""
function command_to_text_operator(command::String)
    if startswith(command, "\\")
        return command[2:end]
    end
    return command
end

"""Consume trailing super/subscript tokens and append mapped script runs."""
function consume_scripts!(runs::Vector{LatexRun}, tokens::Vector{LatexToken}, idx::Base.RefValue{Int})
    while idx[] <= length(tokens)
        marker = tokens[idx[]].kind
        if marker != :sup && marker != :sub
            break
        end

        idx[] += 1
        script_text, was_grouped = parse_script_text(tokens, idx)
        if isempty(script_text)
            continue
        end

        script_token = format_script_token(marker, script_text, was_grouped)
        if marker == :sup
            push!(runs, latex_sup_run(script_token))
            continue
        end

        push!(runs, latex_sub_run(script_token))
    end
end

"""Parse one script payload, either grouped (`{...}`) or single-atom."""
function parse_script_text(tokens::Vector{LatexToken}, idx::Base.RefValue{Int})
    if idx[] > length(tokens)
        return "", false
    end

    if tokens[idx[]].kind == :lbrace
        idx[] += 1
        runs = parse_sequence(tokens, idx, true)
        return join((run.text for run in runs), ""), true
    end

    if tokens[idx[]].kind == :text
        return consume_single_script_text_token!(tokens, idx), false
    end

    runs = parse_atom(tokens, idx)
    return join((run.text for run in runs), ""), false
end

"""Consume exactly one character from a plain-text token for unbraced scripts."""
function consume_single_script_text_token!(tokens::Vector{LatexToken}, idx::Base.RefValue{Int})
    token = tokens[idx[]]
    if isempty(token.text)
        idx[] += 1
        return ""
    end

    first_char_index = firstindex(token.text)
    next_char_index = nextind(token.text, first_char_index)
    first_char = string(token.text[first_char_index])

    if next_char_index <= lastindex(token.text)
        tokens[idx[]] = LatexToken(:text, token.text[next_char_index:end])
    else
        idx[] += 1
    end

    return first_char
end

"""Format script suffix text without Unicode conversion for phase-1 behavior."""
function format_script_token(marker::Symbol, script_text::String, was_grouped::Bool)
    prefix = marker == :sup ? "^" : "_"
    if was_grouped || length(script_text) != 1
        return prefix * "{" * script_text * "}"
    end

    return prefix * script_text
end

"""Merge adjacent runs with identical semantic role."""
run_has_no_content(run::LatexRun) = isempty(run.text) && isempty(run.children) && isempty(run.secondary_children)

"""Return true when two atom runs can be merged into one normalized atom run."""
function can_merge_adjacent_atom_runs(prev::LatexRun, run::LatexRun)
    return prev.role == run.role &&
           prev.segment == :atom &&
           run.segment == :atom &&
           isempty(prev.children) &&
           isempty(prev.secondary_children) &&
           isempty(run.children) &&
           isempty(run.secondary_children)
end

function normalize_runs(runs::Vector{LatexRun})
    normalized = LatexRun[]
    for run in runs
        if run_has_no_content(run)
            continue
        end

        if !isempty(normalized) && can_merge_adjacent_atom_runs(normalized[end], run)
            prev = normalized[end]
            normalized[end] = LatexRun(prev.text * run.text, prev.role, :atom, EMPTY_CHILD_RUNS, EMPTY_CHILD_RUNS)
            continue
        end

        push!(normalized, run)
    end
    return normalized
end

"""Extract script payload text from canonical script token form."""
function script_payload_text(script_token::String)
    if isempty(script_token)
        return ""
    end

    if startswith(script_token, "^{") && endswith(script_token, "}")
        return script_token[3:end-1]
    end
    if startswith(script_token, "_{") && endswith(script_token, "}")
        return script_token[3:end-1]
    end
    if startswith(script_token, "^") || startswith(script_token, "_")
        return script_token[2:end]
    end
    return script_token
end

"""Append optional canonical script suffixes to a base segment string."""
function accent_with_script_suffix(base::String, sup::String, sub::String)
    segment = base
    if !isempty(sup)
        segment *= "^{" * sup * "}"
    end
    if !isempty(sub)
        segment *= "_{" * sub * "}"
    end
    return segment
end

"""Append scripts to a grouped parent payload for recursive script wrappers."""
function grouped_parent_with_script_suffix(parent::String, sup::String, sub::String)
    return accent_with_script_suffix("{" * parent * "}", sup, sub)
end

"""Build canonical fraction text from numerator/denominator strings."""
fraction_text(numerator::String, denominator::String) = "{" * numerator * "}/{" * denominator * "}"

"""Append display-style lower/upper limits in canonical LaTeX order for large operators."""
function large_operator_with_limits(base::String, sup::String, sub::String)
    segment = base
    if !isempty(sub)
        segment *= "_{" * sub * "}"
    end
    if !isempty(sup)
        segment *= "^{" * sup * "}"
    end
    return segment
end

"""Map large-operator kind code to canonical LaTeX command text."""
function large_operator_command_text(kind::Int32)
    if kind == LARGE_OP_KIND_SUM
        return "\\sum"
    end
    if kind == LARGE_OP_KIND_PROD
        return "\\prod"
    end
    if kind == LARGE_OP_KIND_INT
        return "\\int"
    end
    if kind == LARGE_OP_KIND_LIM
        return "\\lim"
    end
    return ""
end

"""Compile normalized runs to the recursive payload representation."""
function compile_emit_program(runs::Vector{LatexRun})
    return math_payload_ops_for_runs(runs)
end

"""Compile and cache one latex string for the given grammar/style key."""
function resolve_cache_entry(source::AbstractString; style_profile::Integer=DEFAULT_STYLE_PROFILE)
    key = (String(source), PARSER_GRAMMAR_VERSION, Int32(style_profile))
    existing = get(parse_cache, key, nothing)
    if existing !== nothing
        return existing
    end

    tokens, ast = parse_latex(source)
    normalized_ast = normalize_runs(ast)
    program = compile_emit_program(normalized_ast)

    entry = ParseCacheEntry(
        key[1],
        key[2],
        key[3],
        tokens,
        ast,
        normalized_ast,
        program)
    parse_cache[key] = entry
    return entry
end

"""Return compiled emit program for one latex input string."""
function compiled_program_for(source::AbstractString; style_profile::Integer=DEFAULT_STYLE_PROFILE)
    entry = resolve_cache_entry(source; style_profile=style_profile)
    return entry.program
end

"""Render one recursive payload op to canonical LaTeX-ish source."""
function latex_source_for_payload(op::MathPayloadOp)
    if op.kind == MATH_OP_SCRIPT_ATTACH
        return accent_with_script_suffix(latex_source_atom_text(op), op.sup_text, op.sub_text)
    end

    if op.kind == MATH_OP_SCRIPT_ATTACH_RECURSIVE
        parent = latex_source_for_program(op.children)
        return grouped_parent_with_script_suffix(parent, op.sup_text, op.sub_text)
    end

    if op.kind == MATH_OP_LARGE_OP_RECURSIVE
        command = large_operator_command_text(op.large_op_kind)
        if isempty(command)
            command = op.text
        end
        return large_operator_with_limits(command, op.sup_text, op.sub_text)
    end

    if op.kind == MATH_OP_FRACTION_RECURSIVE
        numerator = latex_source_for_program(op.children)
        denominator = latex_source_for_program(op.secondary_children)
        return "\\frac{" * numerator * "}{" * denominator * "}"
    end

    if op.kind == MATH_OP_ACCENT_BAR_RECURSIVE
        command = op.accent_mode == :overline ? "\\overline{" : "\\underline{" 
        return command * latex_source_for_program(op.children) * "}"
    end

    if op.kind == MATH_OP_RADICAL_BAR_RECURSIVE
        inner = latex_source_for_program(op.children)
        if !isempty(op.radical_index_text)
            return "\\sqrt[" * op.radical_index_text * "]{" * inner * "}"
        end
        return "\\sqrt{" * inner * "}"
    end

    return latex_source_atom_text(op)
end

"""Render one recursive program back to canonical LaTeX-ish source."""
function latex_source_for_program(program::Vector{MathPayloadOp})
    return join((latex_source_for_payload(op) for op in program), "")
end

"""Render one recursive payload op to plain-text fallback form."""
function plain_text_for_payload(op::MathPayloadOp)
    if op.kind == MATH_OP_SCRIPT_ATTACH
        return accent_with_script_suffix(op.text, op.sup_text, op.sub_text)
    end

    if op.kind == MATH_OP_SCRIPT_ATTACH_RECURSIVE
        parent = plain_text_for_program(op.children)
        return grouped_parent_with_script_suffix(parent, op.sup_text, op.sub_text)
    end

    if op.kind == MATH_OP_LARGE_OP_RECURSIVE
        return large_operator_with_limits(op.text, op.sup_text, op.sub_text)
    end

    if op.kind == MATH_OP_FRACTION_RECURSIVE
        numerator = plain_text_for_program(op.children)
        denominator = plain_text_for_program(op.secondary_children)
        return fraction_text(numerator, denominator)
    end

    if op.kind == MATH_OP_ACCENT_BAR_RECURSIVE
        command = op.accent_mode == :overline ? "\\overline{" : "\\underline{" 
        return command * plain_text_for_program(op.children) * "}"
    end

    if op.kind == MATH_OP_RADICAL_BAR_RECURSIVE
        inner = plain_text_for_program(op.children)
        if !isempty(op.radical_index_text)
            return "\\sqrt[" * op.radical_index_text * "]{" * inner * "}"
        end
        return "\\sqrt{" * inner * "}"
    end

    return op.text
end

"""Return the canonical source text for one payload atom, preserving mathbb styling when known."""
function latex_source_atom_text(op::MathPayloadOp)
    if op.style_role == :mathbb && haskey(MATHBB_GLYPH_TO_SOURCE_MAP, op.text)
        return "\\mathbb{" * MATHBB_GLYPH_TO_SOURCE_MAP[op.text] * "}"
    end
    return op.text
end

"""Render one recursive program to a plain-text fallback payload."""
function plain_text_for_program(program::Vector{MathPayloadOp})
    return join((plain_text_for_payload(op) for op in program), "")
end

"""Resolve latex input to plain Unicode/text fallback."""
function latex_to_plain_text(source::AbstractString; style_profile::Integer=DEFAULT_STYLE_PROFILE)
    entry = resolve_cache_entry(source; style_profile=style_profile)
    return plain_text_for_program(entry.program)
end

"""Replay a compiled recursive program to the currently open dynview block."""
function replay_emit_program!(
    state_ptr::Ptr{Cvoid},
    program::Vector{MathPayloadOp};
    text_style::Integer=OdinJuliaBridge.BRIDGE_DYNVIEW_STYLE_OUTPUT,
    math_style::Integer=OdinJuliaBridge.BRIDGE_DYNVIEW_STYLE_ITALIC,
    mathbb_style::Integer=OdinJuliaBridge.dynview_style_with_font_flags(
        OdinJuliaBridge.BRIDGE_DYNVIEW_FONT_FLAG_REGULAR))

    source = latex_source_for_program(program)
    return replay_emit_math_block!(
        state_ptr,
        source;
        text_style=text_style,
        math_style=math_style,
        mathbb_style=mathbb_style)
end

"""Resolve bridge style id from payload role and kind."""
function math_payload_style_id(kind::Int32, role::Symbol, text_style::Integer, math_style::Integer, mathbb_style::Integer)
    if kind == MATH_OP_TEXT_RUN
        return Int32(text_style)
    end
    if kind == MATH_OP_LARGE_OP_RECURSIVE
        return OdinJuliaBridge.BRIDGE_DYNVIEW_STYLE_MEDIUM
    end
    if role == :mathbb
        return Int32(mathbb_style)
    end
    return Int32(math_style)
end

"""Return true when one recursive payload op can host script attachments."""
function payload_op_accepts_scripts(op::MathPayloadOp)
    return op.kind == MATH_OP_MATH_GLYPH_RUN ||
        op.kind == MATH_OP_SCRIPT_ATTACH ||
        op.kind == MATH_OP_SCRIPT_ATTACH_RECURSIVE ||
        op.kind == MATH_OP_LARGE_OP_RECURSIVE ||
    op.kind == MATH_OP_FRACTION_RECURSIVE ||
        op.kind == MATH_OP_ACCENT_BAR_RECURSIVE ||
        op.kind == MATH_OP_RADICAL_BAR_RECURSIVE
end

"""Lift one payload op into a script-attach payload and set one script field."""
function payload_op_with_script(op::MathPayloadOp, segment::Symbol, script_token::String)
    sup_text = op.sup_text
    sub_text = op.sub_text
    if segment == :script_sup
        sup_text = script_payload_text(script_token)
    elseif segment == :script_sub
        sub_text = script_payload_text(script_token)
    end

    if op.kind == MATH_OP_MATH_GLYPH_RUN || op.kind == MATH_OP_SCRIPT_ATTACH
        return MathPayloadOp(
            MATH_OP_SCRIPT_ATTACH,
            op.text,
            op.radical_index_text,
            sup_text,
            sub_text,
            op.accent_mode,
            op.radical_mode,
            op.large_op_kind,
            op.style_role,
            op.children,
            op.secondary_children)
    end

    if op.kind == MATH_OP_SCRIPT_ATTACH_RECURSIVE
        return MathPayloadOp(
            MATH_OP_SCRIPT_ATTACH_RECURSIVE,
            op.text,
            op.radical_index_text,
            sup_text,
            sub_text,
            op.accent_mode,
            op.radical_mode,
            op.large_op_kind,
            op.style_role,
            op.children,
            op.secondary_children)
    end

    if op.kind == MATH_OP_LARGE_OP_RECURSIVE
        return MathPayloadOp(
            MATH_OP_LARGE_OP_RECURSIVE,
            op.text,
            op.radical_index_text,
            sup_text,
            sub_text,
            op.accent_mode,
            op.radical_mode,
            op.large_op_kind,
            op.style_role,
            op.children,
            op.secondary_children)
    end

    parent_text = plain_text_for_payload(op)
    return MathPayloadOp(
        MATH_OP_SCRIPT_ATTACH_RECURSIVE,
        parent_text,
        "",
        sup_text,
        sub_text,
        :none,
        :none,
        LARGE_OP_KIND_NONE,
        :math,
        [op],
        MathPayloadOp[])
end

"""Return one plain-text fallback string for a run vector."""
function plain_text_for_runs(runs::Vector{LatexRun})
    return plain_text_for_program(compile_emit_program(normalize_runs(runs)))
end

"""Return one atom payload op from one normalized atom run."""
function atom_payload_op(run::LatexRun)
    large_op_kind =
        run.role == :largeop_sum ? LARGE_OP_KIND_SUM :
        (run.role == :largeop_prod ? LARGE_OP_KIND_PROD :
            (run.role == :largeop_int ? LARGE_OP_KIND_INT :
                (run.role == :largeop_lim ? LARGE_OP_KIND_LIM : LARGE_OP_KIND_NONE)))
    if large_op_kind != LARGE_OP_KIND_NONE
        return MathPayloadOp(
            MATH_OP_LARGE_OP_RECURSIVE,
            run.text,
            "",
            "",
            "",
            :none,
            :none,
            large_op_kind,
            :math,
            MathPayloadOp[],
            MathPayloadOp[])
    end

    kind = run.role == :text ? MATH_OP_TEXT_RUN : MATH_OP_MATH_GLYPH_RUN
    return MathPayloadOp(
        kind,
        run.text,
        "",
        "",
        "",
        :none,
        :none,
        LARGE_OP_KIND_NONE,
        run.role,
        MathPayloadOp[],
        MathPayloadOp[])
end

"""Return one recursive accent payload op from one structured run."""
function accent_payload_op(run::LatexRun)
    child_payloads = math_payload_ops_for_runs(run.children)
    accent_mode = run.segment == :accent_over ? :overline : :underline
    return MathPayloadOp(
        MATH_OP_ACCENT_BAR_RECURSIVE,
        plain_text_for_runs(run.children),
        "",
        "",
        "",
        accent_mode,
        :none,
        LARGE_OP_KIND_NONE,
        :math,
        child_payloads,
        MathPayloadOp[])
end

"""Return one recursive radical payload op from one structured run."""
function radical_payload_op(run::LatexRun)
    child_payloads = math_payload_ops_for_runs(run.children)
    radical_mode = isempty(run.text) ? :sqrt : :nthroot
    return MathPayloadOp(
        MATH_OP_RADICAL_BAR_RECURSIVE,
        plain_text_for_runs(run.children),
        run.text,
        "",
        "",
        :none,
        radical_mode,
        LARGE_OP_KIND_NONE,
        :math,
        child_payloads,
        MathPayloadOp[])
end

"""Return one recursive fraction payload op from one structured run."""
function fraction_payload_op(run::LatexRun)
    numerator_payloads = math_payload_ops_for_runs(run.children)
    denominator_payloads = math_payload_ops_for_runs(run.secondary_children)
    return MathPayloadOp(
        MATH_OP_FRACTION_RECURSIVE,
        fraction_text(plain_text_for_runs(run.children), plain_text_for_runs(run.secondary_children)),
        "",
        "",
        "",
        :none,
        :none,
        LARGE_OP_KIND_NONE,
        :math,
        numerator_payloads,
        denominator_payloads)
end

"""Append one script payload op when no compatible prior payload exists."""
function push_script_fallback_payload!(payloads::Vector{MathPayloadOp}, run::LatexRun)
    push!(payloads, MathPayloadOp(
        MATH_OP_MATH_GLYPH_RUN,
        script_payload_text(run.text),
        "",
        "",
        "",
        :none,
        :none,
        LARGE_OP_KIND_NONE,
        :math,
        MathPayloadOp[],
        MathPayloadOp[]))
    return nothing
end

"""Return recursive payload op for a non-script structured run, or nothing if none applies."""
function payload_for_non_script_segment(run::LatexRun)
    if run.segment == :atom
        return atom_payload_op(run)
    end
    if run.segment == :accent_over || run.segment == :accent_under
        return accent_payload_op(run)
    end
    if run.segment == :radical_sqrt
        return radical_payload_op(run)
    end
    if run.segment == :fraction
        return fraction_payload_op(run)
    end
    return nothing
end

"""Return true when this segment is one of the script marker segments."""
is_script_segment(segment::Symbol) = segment == :script_sup || segment == :script_sub

"""Append one script run to prior payload when possible, otherwise append fallback payload."""
function consume_script_payload!(payloads::Vector{MathPayloadOp}, run::LatexRun)
    if !isempty(payloads) && payload_op_accepts_scripts(payloads[end])
        payloads[end] = payload_op_with_script(payloads[end], run.segment, run.text)
    else
        push_script_fallback_payload!(payloads, run)
    end
    return nothing
end

"""Build recursive payload ops from normalized runs without flattening structured children."""
function math_payload_ops_for_runs(runs::Vector{LatexRun})
    payloads = MathPayloadOp[]
    for run in normalize_runs(runs)
        payload = payload_for_non_script_segment(run)
        if payload !== nothing
            push!(payloads, payload)
            continue
        end

        if is_script_segment(run.segment)
            consume_script_payload!(payloads, run)
        end
    end
    return payloads
end

"""Build one bridge math op payload from one recursive payload op."""
function bridge_math_payload_op(
    io::IOBuffer,
    op::MathPayloadOp,
    child_direct_count::Int32,
    secondary_child_direct_count::Int32,
    text_style::Integer,
    math_style::Integer,
    mathbb_style::Integer)

    text_offset, text_len = append_math_block_blob!(io, op.text)
    index_offset, index_len = append_math_block_blob!(io, op.radical_index_text)
    sup_offset, sup_len = append_math_block_blob!(io, op.sup_text)
    sub_offset, sub_len = append_math_block_blob!(io, op.sub_text)
    base_style = math_payload_style_id(op.kind, op.style_role, text_style, math_style, mathbb_style)
    accent_mode, radical_mode, large_op_kind = math_block_mode_codes(op)

    return OdinJuliaBridge.BridgeDynviewMathOp(
        op.kind,
        base_style,
        child_direct_count,
        secondary_child_direct_count,
        Int32(math_style),
        base_style,
        accent_mode,
        radical_mode,
        large_op_kind,
        text_offset,
        text_len,
        index_offset,
        index_len,
        sup_offset,
        sup_len,
        sub_offset,
        sub_len,
        SCRIPT_SCALE,
        SCRIPT_SUP_RAISE,
        SCRIPT_SUB_DROP,
        SCRIPT_GAP,
        ACCENT_BAR_THICKNESS,
        ACCENT_BAR_OFFSET,
    )
end

"""Flatten recursive payload ops into preorder bridge ops and return direct child count."""
function bridge_math_payload_preorder(
    payloads::Vector{MathPayloadOp},
    io::IOBuffer,
    text_style::Integer,
    math_style::Integer,
    mathbb_style::Integer)

    ops = OdinJuliaBridge.BridgeDynviewMathOp[]
    for payload in payloads
        child_direct_count, child_ops = bridge_math_payload_preorder(
            payload.children,
            io,
            text_style,
            math_style,
            mathbb_style)
        secondary_child_direct_count = 0
        secondary_child_ops = OdinJuliaBridge.BridgeDynviewMathOp[]
        if payload.kind == MATH_OP_FRACTION_RECURSIVE
            secondary_child_direct_count, secondary_child_ops = bridge_math_payload_preorder(
                payload.secondary_children,
                io,
                text_style,
                math_style,
                mathbb_style)
        end
        push!(ops, bridge_math_payload_op(
            io,
            payload,
            Int32(child_direct_count),
            Int32(secondary_child_direct_count),
            text_style,
            math_style,
            mathbb_style))
        append!(ops, child_ops)
        append!(ops, secondary_child_ops)
    end
    return length(payloads), ops
end

"""Append one string to a shared math-block blob and return byte offset/length."""
function append_math_block_blob!(io::IOBuffer, text::AbstractString)
    data = codeunits(String(text))
    offset = Int32(io.size)
    write(io, data)
    return offset, Int32(length(data))
end

"""Return bridge accent/radical mode codes for one payload op."""
function math_block_mode_codes(op::MathPayloadOp)
    accent_mode = op.accent_mode == :overline ? 
        OdinJuliaBridge.BRIDGE_DYNVIEW_ACCENT_MODE_OVERLINE :
        (op.accent_mode == :underline ?
            OdinJuliaBridge.BRIDGE_DYNVIEW_ACCENT_MODE_UNDERLINE : Int32(0))
    radical_mode = op.radical_mode == :nthroot ?
        OdinJuliaBridge.BRIDGE_DYNVIEW_RADICAL_MODE_NTHROOT :
        (op.radical_mode == :sqrt ?
            OdinJuliaBridge.BRIDGE_DYNVIEW_RADICAL_MODE_SQRT : Int32(0))

    large_op_kind =
        op.large_op_kind == LARGE_OP_KIND_SUM ? OdinJuliaBridge.BRIDGE_DYNVIEW_LARGE_OP_KIND_SUM :
        (op.large_op_kind == LARGE_OP_KIND_PROD ? OdinJuliaBridge.BRIDGE_DYNVIEW_LARGE_OP_KIND_PROD :
            (op.large_op_kind == LARGE_OP_KIND_INT ? OdinJuliaBridge.BRIDGE_DYNVIEW_LARGE_OP_KIND_INT :
                (op.large_op_kind == LARGE_OP_KIND_LIM ? OdinJuliaBridge.BRIDGE_DYNVIEW_LARGE_OP_KIND_LIM : Int32(0))))
    return Int32(accent_mode), Int32(radical_mode), Int32(large_op_kind)
end

"""Encode one recursive payload program as recursive bridge ops plus shared text blob."""
function bridge_math_block_payload(
    program::Vector{MathPayloadOp};
    text_style::Integer,
    math_style::Integer,
    mathbb_style::Integer)

    blob = IOBuffer()
    top_level_count, ops = bridge_math_payload_preorder(
        program,
        blob,
        text_style,
        math_style,
        mathbb_style)
    return plain_text_for_program(program), String(take!(blob)), ops, top_level_count
end

"""Encode one normalized LaTeX run tree as recursive bridge ops plus shared text blob."""
function bridge_math_block_payload(
    runs::Vector{LatexRun};
    text_style::Integer,
    math_style::Integer,
    mathbb_style::Integer)

    payloads = math_payload_ops_for_runs(runs)
    blob = IOBuffer()
    top_level_count, ops = bridge_math_payload_preorder(
        payloads,
        blob,
        text_style,
        math_style,
        mathbb_style)
    return plain_text_for_runs(runs), String(take!(blob)), ops, top_level_count
end

"""Replay a compiled recursive program as one atomic non-wrapping math block."""
function replay_emit_math_block!(
    state_ptr::Ptr{Cvoid},
    program::Vector{MathPayloadOp};
    text_style::Integer=OdinJuliaBridge.BRIDGE_DYNVIEW_STYLE_OUTPUT,
    math_style::Integer=OdinJuliaBridge.BRIDGE_DYNVIEW_STYLE_ITALIC,
    mathbb_style::Integer=OdinJuliaBridge.dynview_style_with_font_flags(
        OdinJuliaBridge.BRIDGE_DYNVIEW_FONT_FLAG_REGULAR))

    plain_text, text_blob, ops, top_level_count = bridge_math_block_payload(
        program;
        text_style=text_style,
        math_style=math_style,
        mathbb_style=mathbb_style)
    status = OdinJuliaBridge.dynview_math_block_from_ops(
        state_ptr,
        plain_text,
        math_style,
        ops,
        top_level_count,
        text_blob)
    return status == OdinJuliaBridge.BRIDGE_STATUS_OK
end

"""Replay one LaTeX source string as one recursive non-wrapping math block."""
function replay_emit_math_block!(
    state_ptr::Ptr{Cvoid},
    source::AbstractString;
    style_profile::Integer=DEFAULT_STYLE_PROFILE,
    text_style::Integer=OdinJuliaBridge.BRIDGE_DYNVIEW_STYLE_OUTPUT,
    math_style::Integer=OdinJuliaBridge.BRIDGE_DYNVIEW_STYLE_ITALIC,
    mathbb_style::Integer=OdinJuliaBridge.dynview_style_with_font_flags(
        OdinJuliaBridge.BRIDGE_DYNVIEW_FONT_FLAG_REGULAR))

    entry = resolve_cache_entry(source; style_profile=style_profile)
    plain_text, text_blob, ops, top_level_count = bridge_math_block_payload(
        entry.normalized_ast;
        text_style=text_style,
        math_style=math_style,
        mathbb_style=mathbb_style)
    status = OdinJuliaBridge.dynview_math_block_from_ops(
        state_ptr,
        plain_text,
        math_style,
        ops,
        top_level_count,
        text_blob)
    return status == OdinJuliaBridge.BRIDGE_STATUS_OK
end


"""Emit one latex string as a standalone dynview block with fallback copy payload."""
function emit_latex_dynview!(
    state_ptr::Ptr{Cvoid},
    source::AbstractString;
    block_kind::Integer=OdinJuliaBridge.BRIDGE_DYNVIEW_BLOCK_OUTPUT,
    block_id::Integer=1,
    style_profile::Integer=DEFAULT_STYLE_PROFILE,
    copy_plain_text::Bool=true,
    text_style::Integer=OdinJuliaBridge.BRIDGE_DYNVIEW_STYLE_OUTPUT,
    math_style::Integer=OdinJuliaBridge.BRIDGE_DYNVIEW_STYLE_ITALIC,
    mathbb_style::Integer=OdinJuliaBridge.dynview_style_with_font_flags(
        OdinJuliaBridge.BRIDGE_DYNVIEW_FONT_FLAG_REGULAR))

    if OdinJuliaBridge.dynview_reset_stream(state_ptr) != OdinJuliaBridge.BRIDGE_STATUS_OK
        return false
    end

    if OdinJuliaBridge.dynview_begin_block(state_ptr, block_kind, block_id) !=
            OdinJuliaBridge.BRIDGE_STATUS_OK
        return false
    end

    if copy_plain_text
        plain = latex_to_plain_text(source; style_profile=style_profile)
        status = OdinJuliaBridge.dynview_copyable_text_run(state_ptr, plain)
        if status != OdinJuliaBridge.BRIDGE_STATUS_OK
            return false
        end
    end

    if !replay_emit_math_block!(
            state_ptr,
            source;
            style_profile=style_profile,
            text_style=text_style,
            math_style=math_style,
            mathbb_style=mathbb_style)
        return false
    end

    return OdinJuliaBridge.dynview_end_block(state_ptr) == OdinJuliaBridge.BRIDGE_STATUS_OK
end

end
