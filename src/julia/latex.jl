module EuclidLatex

using ..OdinJuliaBridge

export PARSER_GRAMMAR_VERSION,
    clear_cache!,
    cache_size,
    resolve_cache_entry,
    parse_latex,
    compile_emit_program,
    replay_emit_program!,
    emit_latex_dynview!,
    latex_to_plain_text,
    compiled_program_for

const PARSER_GRAMMAR_VERSION = Int32(7)
const DEFAULT_STYLE_PROFILE = Int32(0)
const SCRIPT_SCALE = Float32(0.62)
const SCRIPT_SUP_RAISE = Float32(0.44)
const SCRIPT_SUB_DROP = Float32(0.30)
const SCRIPT_GAP = Float32(0.04)
const ACCENT_BAR_THICKNESS = Float32(0.08)
const ACCENT_BAR_OFFSET = Float32(0.10)
const RADICAL_BAR_THICKNESS = Float32(0.08)
const RADICAL_BAR_OFFSET = Float32(0.10)

const TEXT_OPERATOR_COMMANDS = Set([
    "\\arccos", "\\arcsin", "\\arctan", "\\arg", "\\cos", "\\csc", "\\cot",
    "\\coth", "\\deg", "\\det", "\\dim", "\\exp", "\\gcd", "\\hom", "\\inf",
    "\\ker", "\\lg", "\\lim", "\\liminf", "\\limsup", "\\ln", "\\log", "\\max",
    "\\min", "\\Pr", "\\sec", "\\sin", "\\sinh", "\\sup", "\\tan", "\\tanh"
])

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

struct LatexToken
    kind::Symbol
    text::String
end

struct LatexRun
    text::String
    role::Symbol
    segment::Symbol
    children::Vector{LatexRun}
end

struct EmitOp
    kind::Symbol
    text::String
    radical_index_text::String
    sup_text::String
    sub_text::String
    accent_mode::Symbol
    radical_mode::Symbol
    style_role::Symbol
end

struct ParseCacheEntry
    source::String
    grammar_version::Int32
    style_profile::Int32
    tokens::Vector{LatexToken}
    ast::Vector{LatexRun}
    normalized_ast::Vector{LatexRun}
    program::Vector{EmitOp}
end

const parse_cache = Dict{Tuple{String, Int32, Int32}, ParseCacheEntry}()

const EMPTY_CHILD_RUNS = LatexRun[]

"""Return one normal atom run payload."""
latex_atom_run(text::String, role::Symbol) = LatexRun(text, role, :atom, EMPTY_CHILD_RUNS)

"""Return one superscript script-segment run payload."""
latex_sup_run(text::String) = LatexRun(text, :math, :script_sup, EMPTY_CHILD_RUNS)

"""Return one subscript script-segment run payload."""
latex_sub_run(text::String) = LatexRun(text, :math, :script_sub, EMPTY_CHILD_RUNS)

"""Return one overline accent run payload."""
latex_overline_run(children::Vector{LatexRun}) = LatexRun("", :math, :accent_over, children)

"""Return one underline accent run payload."""
latex_underline_run(children::Vector{LatexRun}) = LatexRun("", :math, :accent_under, children)

"""Return one square-root radical run payload."""
latex_sqrt_run(children::Vector{LatexRun}, index_text::AbstractString="") =
    LatexRun(String(index_text), :math, :radical_sqrt, children)

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

    return nothing
end

"""Serialize one semantic run back into deterministic plain-text LaTeX form."""
function latex_run_serialized_text(run::LatexRun)
    child_text = ""
    if !isempty(run.children)
        child_text = join((latex_run_serialized_text(child) for child in run.children), "")
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
function normalize_runs(runs::Vector{LatexRun})
    normalized = LatexRun[]
    for run in runs
        if isempty(run.text) && isempty(run.children)
            continue
        end

        if !isempty(normalized) &&
                normalized[end].role == run.role &&
                normalized[end].segment == :atom &&
                run.segment == :atom &&
                isempty(normalized[end].children) &&
                isempty(run.children)
            prev = normalized[end]
            normalized[end] = LatexRun(prev.text * run.text, prev.role, :atom, EMPTY_CHILD_RUNS)
            continue
        end

        push!(normalized, run)
    end
    return normalized
end

"""Return true when one emit op can host script attachments."""
function op_accepts_scripts(op::EmitOp)
    return op.kind == :MathGlyphRun || op.kind == :ScriptAttach
end

"""Lift one base math op into a script-attach op and set one script field."""
function op_with_script(op::EmitOp, segment::Symbol, script_token::String)
    sup_text = op.sup_text
    sub_text = op.sub_text
    if segment == :script_sup
        sup_text = script_token
    elseif segment == :script_sub
        sub_text = script_token
    end

    return EmitOp(
        :ScriptAttach,
        op.text,
        op.radical_index_text,
        sup_text,
        sub_text,
        :none,
        :none,
        op.style_role)
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

"""Build one atom emit op from one normalized atom run."""
function atom_emit_op(run::LatexRun)
    kind = run.role == :text ? :TextRun : :MathGlyphRun
    return EmitOp(kind, run.text, "", "", "", :none, :none, run.role)
end

"""Build one structured accent/radical emit op, or nothing when segment is not structured."""
function structured_emit_op(run::LatexRun)
    if run.segment == :accent_over
        child_program = compile_emit_program(run.children)
        accent_text, accent_sup_text, accent_sub_text, accent_role =
            accent_payload_from_child_program(child_program)
        return EmitOp(
            :AccentBar,
            accent_text,
            "",
            accent_sup_text,
            accent_sub_text,
            :overline,
            :none,
            accent_role)
    end

    if run.segment == :accent_under
        child_program = compile_emit_program(run.children)
        accent_text, accent_sup_text, accent_sub_text, accent_role =
            accent_payload_from_child_program(child_program)
        return EmitOp(
            :AccentBar,
            accent_text,
            "",
            accent_sup_text,
            accent_sub_text,
            :underline,
            :none,
            accent_role)
    end

    if run.segment == :radical_sqrt
        child_program = compile_emit_program(run.children)
        radical_text, radical_sup_text, radical_sub_text, radical_role =
            accent_payload_from_child_program(child_program)
        return EmitOp(
            :RadicalBar,
            radical_text,
            run.text,
            radical_sup_text,
            radical_sub_text,
            :none,
            isempty(run.text) ? :sqrt : :nthroot,
            radical_role)
    end

    return nothing
end

"""Attach one script run to prior op when possible, otherwise emit fallback math glyph run."""
function append_script_emit_op!(program::Vector{EmitOp}, run::LatexRun)
    script_text = script_payload_text(run.text)
    if isempty(script_text)
        return
    end

    if isempty(program) || !op_accepts_scripts(program[end])
        push!(program, EmitOp(:MathGlyphRun, run.text, "", "", "", :none, :none, :math))
        return
    end

    program[end] = op_with_script(program[end], run.segment, script_text)
end

"""Compile normalized runs to replay-ready semantic emit ops."""
function compile_emit_program(runs::Vector{LatexRun})
    program = EmitOp[]
    for run in runs
        if run.segment == :atom
            push!(program, atom_emit_op(run))
            continue
        end

        structured_op = structured_emit_op(run)
        if structured_op !== nothing
            push!(program, structured_op)
            continue
        end

        append_script_emit_op!(program, run)
    end
    return program
end

"""Extract one accent payload tuple and style role from child emit ops."""
function accent_payload_from_child_program(child_program::Vector{EmitOp})
    if isempty(child_program)
        return "", "", "", :math
    end

    if length(child_program) == 1
        op = child_program[1]
        if op.kind == :ScriptAttach
            return op.text, op.sup_text, op.sub_text, op.style_role
        end
        if op.kind == :MathGlyphRun || op.kind == :TextRun
            return op.text, "", "", op.style_role
        end
    end

    text_parts = map(accent_child_segment_text, child_program)
    return join(text_parts, ""), "", "", :math
end

"""Render one child emit op to literal LaTeX/text segment for accent payload fallback."""
function accent_child_segment_text(op::EmitOp)
    if op.kind == :ScriptAttach
        return accent_with_script_suffix(op.text, op.sup_text, op.sub_text)
    end

    if op.kind == :AccentBar
        command = op.accent_mode == :overline ? "\\overline{" : "\\underline{"
        inner = accent_with_script_suffix(op.text, op.sup_text, op.sub_text)
        return command * inner * "}"
    end

    if op.kind == :RadicalBar
        inner = accent_with_script_suffix(op.text, op.sup_text, op.sub_text)
        if !isempty(op.radical_index_text)
            return "\\sqrt[" * op.radical_index_text * "]{" * inner * "}"
        end
        return "\\sqrt{" * inner * "}"
    end

    return op.text
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

"""Resolve latex input to plain Unicode/text fallback."""
function latex_to_plain_text(source::AbstractString; style_profile::Integer=DEFAULT_STYLE_PROFILE)
    entry = resolve_cache_entry(source; style_profile=style_profile)
    parts = String[]
    for op in entry.program
        if op.kind == :ScriptAttach
            push!(parts, op.text)
            if !isempty(op.sup_text)
                push!(parts, "^{" * op.sup_text * "}")
            end
            if !isempty(op.sub_text)
                push!(parts, "_{" * op.sub_text * "}")
            end
            continue
        end

        if op.kind == :AccentBar
            if op.accent_mode == :overline
                push!(parts, "\\overline{" * op.text * "}")
            else
                push!(parts, "\\underline{" * op.text * "}")
            end
            continue
        end

        if op.kind == :RadicalBar
            inner = accent_with_script_suffix(op.text, op.sup_text, op.sub_text)
            if !isempty(op.radical_index_text)
                push!(parts, "\\sqrt[" * op.radical_index_text * "]{" * inner * "}")
            else
                push!(parts, "\\sqrt{" * inner * "}")
            end
            continue
        end

        push!(parts, op.text)
    end
    return join(parts, "")
end

"""Replay a compiled semantic program to the currently open dynview block."""
function replay_emit_program!(
    state_ptr::Ptr{Cvoid},
    program::Vector{EmitOp};
    text_style::Integer=OdinJuliaBridge.BRIDGE_DYNVIEW_STYLE_OUTPUT,
    math_style::Integer=OdinJuliaBridge.BRIDGE_DYNVIEW_STYLE_ITALIC,
    mathbb_style::Integer=OdinJuliaBridge.dynview_style_with_font_flags(
        OdinJuliaBridge.BRIDGE_DYNVIEW_FONT_FLAG_MEDIUM))

    for op in program
        status = replay_emit_op!(state_ptr, op, text_style, math_style, mathbb_style)
        if status != OdinJuliaBridge.BRIDGE_STATUS_OK
            return false
        end
    end

    return true
end

"""Resolve per-op base style id, including dedicated mathbb styling."""
function math_style_for_op(op::EmitOp, math_style::Integer, mathbb_style::Integer)
    if op.style_role == :mathbb
        return mathbb_style
    end

    return math_style
end

"""Replay one compiled op through the dynview bridge and return status code."""
function replay_emit_op!(
    state_ptr::Ptr{Cvoid},
    op::EmitOp,
    text_style::Integer,
    math_style::Integer,
    mathbb_style::Integer)

    base_style = math_style_for_op(op, math_style, mathbb_style)

    if op.kind == :MathGlyphRun
        return OdinJuliaBridge.dynview_math_glyph_run(state_ptr, op.text, base_style)
    end

    if op.kind == :ScriptAttach
        return replay_script_attach_op!(state_ptr, op, base_style, math_style)
    end

    if op.kind == :AccentBar
        return replay_accent_bar_op!(state_ptr, op, base_style, math_style)
    end

    if op.kind == :RadicalBar
        return replay_radical_bar_op!(state_ptr, op, base_style, math_style)
    end

    return OdinJuliaBridge.dynview_text_run(state_ptr, op.text, text_style)
end

"""Replay one script-attach op through the dynview bridge."""
function replay_script_attach_op!(
    state_ptr::Ptr{Cvoid},
    op::EmitOp,
    base_style::Integer,
    script_style::Integer)

    return OdinJuliaBridge.dynview_script_attach(
        state_ptr,
        op.text,
        op.sup_text,
        op.sub_text,
        base_style,
        script_style,
        SCRIPT_SCALE,
        SCRIPT_SUP_RAISE,
        SCRIPT_SUB_DROP,
        SCRIPT_GAP)
end

"""Replay one accent-bar op through the dynview bridge."""
function replay_accent_bar_op!(
    state_ptr::Ptr{Cvoid},
    op::EmitOp,
    base_style::Integer,
    script_style::Integer)

    accent_mode = op.accent_mode == :overline ?
        OdinJuliaBridge.BRIDGE_DYNVIEW_ACCENT_MODE_OVERLINE :
        OdinJuliaBridge.BRIDGE_DYNVIEW_ACCENT_MODE_UNDERLINE

    return OdinJuliaBridge.dynview_accent_bar(
        state_ptr,
        op.text,
        op.sup_text,
        op.sub_text,
        base_style,
        base_style,
        accent_mode,
        script_style,
        ACCENT_BAR_THICKNESS,
        ACCENT_BAR_OFFSET,
        SCRIPT_SCALE,
        SCRIPT_SUP_RAISE,
        SCRIPT_SUB_DROP,
        SCRIPT_GAP)
end

"""Replay one radical-bar op through the dynview bridge."""
function replay_radical_bar_op!(
    state_ptr::Ptr{Cvoid},
    op::EmitOp,
    base_style::Integer,
    script_style::Integer)

    radical_mode = op.radical_mode == :nthroot ?
        OdinJuliaBridge.BRIDGE_DYNVIEW_RADICAL_MODE_NTHROOT :
        OdinJuliaBridge.BRIDGE_DYNVIEW_RADICAL_MODE_SQRT

    return OdinJuliaBridge.dynview_radical_bar(
        state_ptr,
        op.text,
        op.radical_index_text,
        op.sup_text,
        op.sub_text,
        base_style,
        base_style,
        radical_mode,
        script_style,
        RADICAL_BAR_THICKNESS,
        RADICAL_BAR_OFFSET,
        SCRIPT_SCALE,
        SCRIPT_SUP_RAISE,
        SCRIPT_SUB_DROP,
        SCRIPT_GAP)
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
        OdinJuliaBridge.BRIDGE_DYNVIEW_FONT_FLAG_MEDIUM))

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

    program = compiled_program_for(source; style_profile=style_profile)
    if !replay_emit_program!(
            state_ptr,
            program;
            text_style=text_style,
            math_style=math_style,
            mathbb_style=mathbb_style)
        return false
    end

    return OdinJuliaBridge.dynview_end_block(state_ptr) == OdinJuliaBridge.BRIDGE_STATUS_OK
end

end
