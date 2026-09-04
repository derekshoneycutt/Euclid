"""Compile normalized runs to the recursive payload representation."""
function compile_emit_program(runs::Vector{LatexRun})
    return math_payload_ops_for_runs(runs)
end

"""Parse and normalize one LaTeX source without retaining mutable module state."""
function compile_latex_runs(source::AbstractString)
    _, ast = parse_latex(source)
    normalized_ast = normalize_runs(ast)
    return normalized_ast, compile_emit_program(normalized_ast)
end

"""Return compiled emit program for one latex input string."""
function compiled_program_for(
    source::AbstractString; style_profile::Integer=DEFAULT_STYLE_PROFILE)
    _ = style_profile
    _, program = compile_latex_runs(source)
    return program
end

"""Render one recursive payload op to canonical LaTeX-ish source."""
function latex_source_for_payload(op::MathPayloadOp)
    if op.kind == MATH_OP_SCRIPT_ATTACH_RECURSIVE
        parent = latex_source_for_program(op.children)
        return grouped_parent_with_script_suffix(parent, op.sup_text, op.sub_text)
    end

    return latex_source_for_recursive_payload(op)
end

"""Render one recursive program back to canonical LaTeX-ish source."""
function latex_source_for_program(program::Vector{MathPayloadOp})
    return join((latex_source_for_payload(op) for op in program), "")
end

"""Render one recursive payload op to plain-text fallback form."""
function plain_text_for_recursive_payload(op::MathPayloadOp)
    if op.kind == MATH_OP_LARGE_OP_RECURSIVE
        return large_operator_with_limits(op.text, op.sup_text, op.sub_text)
    end

    if op.kind == MATH_OP_FRACTION_RECURSIVE
        numerator = plain_text_for_program(op.children)
        denominator = plain_text_for_program(op.secondary_children)
        return fraction_text(numerator, denominator)
    end

    if op.kind == MATH_OP_STRETCH_DELIMITER_RECURSIVE
        return stretch_delimiter_text(op.radical_index_text,
            plain_text_for_program(op.children), op.sup_text)
    end

    if op.kind == MATH_OP_MATRIX_RECURSIVE
        return matrix_payload_fallback_text(op, plain_text_for_payload)
    end

    if op.kind == MATH_OP_STYLE_OVERRIDE_RECURSIVE
        return plain_text_for_program(op.children)
    end

    if op.kind == MATH_OP_STACK_RECURSIVE
        return "(" * plain_text_for_program(op.children) * ";" *
            plain_text_for_program(op.secondary_children) * ")"
    end

    if op.kind == MATH_OP_ACCENT_BAR_RECURSIVE
        commands = Dict(
            :overline => "\\overline", :underline => "\\underline",
            :hat => "\\hat", :tilde => "\\tilde", :vec => "\\vec",
            :dot => "\\dot", :ddot => "\\ddot", :bar => "\\bar",
            :check => "\\check", :breve => "\\breve", :acute => "\\acute",
            :grave => "\\grave", :ring => "\\mathring",
            :overbrace => "\\overbrace", :underbrace => "\\underbrace")
        command = get(commands, op.accent_mode, "\\overline") * "{"
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

"""Render one recursive payload op to plain-text fallback form."""
function plain_text_for_payload(op::MathPayloadOp)
    if op.kind == MATH_OP_SCRIPT_ATTACH_RECURSIVE
        parent = plain_text_for_program(op.children)
        return grouped_parent_with_script_suffix(parent, op.sup_text, op.sub_text)
    end
    return plain_text_for_recursive_payload(op)
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
function latex_to_plain_text(
    source::AbstractString; style_profile::Integer=DEFAULT_STYLE_PROFILE)
    return plain_text_for_program(
        compiled_program_for(source; style_profile=style_profile))
end
