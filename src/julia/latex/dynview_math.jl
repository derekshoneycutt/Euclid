"""Accent, radical, and large-operator mode codes for one math block payload op."""
struct MathBlockModeCodes
    accent_mode::Int32
    radical_mode::Int32
    large_op_kind::Int32
    operator_growth::Int32
    operator_limits::Int32
end

struct BridgeMathBlockPayload
    plain_text::String
    text_blob::String
    ops::Vector{OdinJuliaBridge.BridgeDynviewMathOp}
    table_descriptors::Vector{OdinJuliaBridge.BridgeDynviewMathTableDescriptor}
    top_level_count::Int
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
function math_payload_style_id(kind::Int32, role::Symbol,
    text_style::Integer, math_style::Integer, mathbb_style::Integer)
    if kind == MATH_OP_TEXT_RUN
        return Int32(text_style)
    end
    if kind == MATH_OP_LARGE_OP_RECURSIVE
        return OdinJuliaBridge.BRIDGE_DYNVIEW_STYLE_MEDIUM
    end
    if role == :mathbb
        return Int32(mathbb_style)
    end
    if role == :math_upright
        return OdinJuliaBridge.dynview_style_with_font_flags(
            OdinJuliaBridge.BRIDGE_DYNVIEW_FONT_FLAG_REGULAR)
    end
    return Int32(math_style)
end

"""Return true when one recursive payload op can host script attachments."""
function payload_op_accepts_scripts(op::MathPayloadOp)
    return op.kind == MATH_OP_MATH_GLYPH_RUN ||
        op.kind == MATH_OP_SCRIPT_ATTACH_RECURSIVE ||
        op.kind == MATH_OP_LARGE_OP_RECURSIVE ||
        op.kind == MATH_OP_FRACTION_RECURSIVE ||
        op.kind == MATH_OP_STRETCH_DELIMITER_RECURSIVE ||
        op.kind == MATH_OP_MATRIX_RECURSIVE ||
        op.kind == MATH_OP_ACCENT_BAR_RECURSIVE ||
        op.kind == MATH_OP_RADICAL_BAR_RECURSIVE
end

"""Lift one payload op into a script-attach payload and set one script field."""
function payload_op_with_script(op::MathPayloadOp, run::LatexRun)
    sup_text = op.sup_text
    sub_text = op.sub_text
    superscript = op.secondary_children
    subscript = op.tertiary_children
    if run.segment == :script_sup
        sup_text = script_payload_text(run.text)
        superscript = math_payload_ops_for_runs(run.children)
    elseif run.segment == :script_sub
        sub_text = script_payload_text(run.text)
        subscript = math_payload_ops_for_runs(run.children)
    end

    if op.kind == MATH_OP_SCRIPT_ATTACH_RECURSIVE ||
            op.kind == MATH_OP_LARGE_OP_RECURSIVE
        return payload_op_rescripted(op, sup_text, sub_text, superscript, subscript)
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
        op.style_role,
        op.atom_class,
        op.glue_kind,
        [op],
        superscript,
        subscript)
end

"""Rebuild one payload op with updated recursive script branches."""
function payload_op_rescripted(op::MathPayloadOp, sup_text::String, sub_text::String,
    superscript::Vector{MathPayloadOp}, subscript::Vector{MathPayloadOp})
    return MathPayloadOp(
        op.kind,
        op.text,
        op.radical_index_text,
        sup_text,
        sub_text,
        op.accent_mode,
        op.radical_mode,
        op.large_op_kind,
        op.operator_growth,
        op.operator_limits,
        op.style_role,
        op.atom_class,
        op.glue_kind,
        op.children,
        superscript,
        subscript)
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
                (run.role == :largeop_lim ? LARGE_OP_KIND_LIM :
                    (run.role == :largeop_nary ? LARGE_OP_KIND_NARY :
                        LARGE_OP_KIND_NONE))))
    if large_op_kind != LARGE_OP_KIND_NONE
        return large_operator_payload_op(run.text, large_op_kind)
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
        run.atom_class,
        run.glue_kind,
        MathPayloadOp[],
        MathPayloadOp[],
        MathPayloadOp[])
end

"""Return semantic display-growth and limit policies for one operator body."""
function large_operator_policies(large_op_kind::Int32)
    if large_op_kind == LARGE_OP_KIND_INT
        return OPERATOR_GROWTH_DISPLAY, OPERATOR_LIMITS_SIDE
    end
    if large_op_kind == LARGE_OP_KIND_LIM
        return OPERATOR_GROWTH_NONE, OPERATOR_LIMITS_STACKED
    end
    return OPERATOR_GROWTH_DISPLAY, OPERATOR_LIMITS_STACKED
end

"""Return one recursive large-operator payload with independent semantic policies."""
function large_operator_payload_op(text::String, large_op_kind::Int32)
    growth, limits = large_operator_policies(large_op_kind)
    return MathPayloadOp(MATH_OP_LARGE_OP_RECURSIVE, text, "", "", "", :none,
        :none, large_op_kind, growth, limits, :math, MATH_ATOM_OP, MATH_GLUE_NONE,
        MathPayloadOp[], MathPayloadOp[], MathPayloadOp[])
end

"""Return one recursive accent payload op from one structured run."""
function accent_payload_op(run::LatexRun)
    child_payloads = math_payload_ops_for_runs(run.children)
    accent_modes = Dict(
        :accent_over => :overline, :accent_under => :underline,
        :accent_hat => :hat, :accent_tilde => :tilde, :accent_vec => :vec,
        :accent_dot => :dot, :accent_ddot => :ddot, :accent_bar => :bar)
    accent_mode = get(accent_modes, run.segment, :overline)
    return MathPayloadOp(
        MATH_OP_ACCENT_BAR_RECURSIVE,
        String(plain_text_for_runs(run.children)),
        "",
        "",
        "",
        accent_mode,
        :none,
        LARGE_OP_KIND_NONE,
        :math,
        MATH_ATOM_ORD,
        MATH_GLUE_NONE,
        child_payloads,
        MathPayloadOp[],
        MathPayloadOp[])
end

"""Return the bridge code for one semantic accent mode."""
function bridge_accent_mode(mode::Symbol)
    modes = Dict(
        :overline => OdinJuliaBridge.BRIDGE_DYNVIEW_ACCENT_MODE_OVERLINE,
        :underline => OdinJuliaBridge.BRIDGE_DYNVIEW_ACCENT_MODE_UNDERLINE,
        :hat => OdinJuliaBridge.BRIDGE_DYNVIEW_ACCENT_MODE_HAT,
        :tilde => OdinJuliaBridge.BRIDGE_DYNVIEW_ACCENT_MODE_TILDE,
        :vec => OdinJuliaBridge.BRIDGE_DYNVIEW_ACCENT_MODE_VEC,
        :dot => OdinJuliaBridge.BRIDGE_DYNVIEW_ACCENT_MODE_DOT,
        :ddot => OdinJuliaBridge.BRIDGE_DYNVIEW_ACCENT_MODE_DDOT,
        :bar => OdinJuliaBridge.BRIDGE_DYNVIEW_ACCENT_MODE_BAR)
    return get(modes, mode, Int32(0))
end

"""Return one recursive radical payload op from one structured run."""
function radical_payload_op(run::LatexRun)
    child_payloads = math_payload_ops_for_runs(run.children)
    degree_payloads = math_payload_ops_for_runs(run.secondary_children)
    radical_mode = isempty(run.text) ? :sqrt : :nthroot
    return MathPayloadOp(
        MATH_OP_RADICAL_BAR_RECURSIVE,
        String(plain_text_for_runs(run.children)),
        run.text,
        "",
        "",
        :none,
        radical_mode,
        LARGE_OP_KIND_NONE,
        :math,
        MATH_ATOM_ORD,
        MATH_GLUE_NONE,
        child_payloads,
        degree_payloads,
        MathPayloadOp[])
end

"""Return one recursive fraction payload op from one structured run."""
function fraction_payload_op(run::LatexRun)
    numerator_payloads = math_payload_ops_for_runs(run.children)
    denominator_payloads = math_payload_ops_for_runs(run.secondary_children)
    return MathPayloadOp(MATH_OP_FRACTION_RECURSIVE,
        String(fraction_text(plain_text_for_runs(run.children),
            plain_text_for_runs(run.secondary_children))),
        "", "", "", :none, :none, LARGE_OP_KIND_NONE, :math,
        MATH_ATOM_INNER, MATH_GLUE_NONE,
        numerator_payloads, denominator_payloads, MathPayloadOp[])
end

"""Return one recursive stretch-delimiter payload op from one structured run."""
function stretch_delimiter_payload_op(run::LatexRun)
    child_payloads = math_payload_ops_for_runs(run.children)
    left = run.text
    right = stretch_right_delimiter(run)
    return MathPayloadOp(
        MATH_OP_STRETCH_DELIMITER_RECURSIVE,
        String(stretch_delimiter_text(
            left, plain_text_for_runs(run.children), right)),
        left, right, "", :none, :none, LARGE_OP_KIND_NONE, :math,
        MATH_ATOM_INNER, MATH_GLUE_NONE,
        child_payloads, MathPayloadOp[], MathPayloadOp[])
end

"""Return one matrix-cell payload op with cell children wrapped into one root payload."""
function matrix_cell_payload_op(cell_run::LatexRun)
    cell_payloads = math_payload_ops_for_runs(cell_run.children)
    if isempty(cell_payloads)
        return MathPayloadOp(MATH_OP_MATH_GLYPH_RUN,
            " ", "", "", "", :none, :none, LARGE_OP_KIND_NONE, :math,
            MATH_ATOM_ORD, MATH_GLUE_NONE,
            MathPayloadOp[], MathPayloadOp[], MathPayloadOp[])
    end

    if length(cell_payloads) == 1
        return cell_payloads[1]
    end

    return MathPayloadOp(MATH_OP_SCRIPT_ATTACH_RECURSIVE,
        String(plain_text_for_program(cell_payloads)), "", "", "", :none, :none,
        LARGE_OP_KIND_NONE, :math, MATH_ATOM_INNER, MATH_GLUE_NONE,
        cell_payloads, MathPayloadOp[], MathPayloadOp[])
end

"""Return one recursive matrix payload op from one structured run."""
function matrix_payload_op(run::LatexRun)
    dims = parse_matrix_dims_text(run.text)
    rows = dims.rows
    cols = dims.cols
    if !dims.ok || rows <= 0 || cols <= 0
        rows = 1
        cols = max(1, length(run.children))
    end

    cells = MathPayloadOp[]
    for cell_run in run.children
        push!(cells, matrix_cell_payload_op(cell_run))
    end

    array_alignment = ""
    if run.segment == :array && !isempty(run.secondary_children)
        array_alignment = run.secondary_children[1].text
    end

    return MathPayloadOp(
        MATH_OP_MATRIX_RECURSIVE,
        String(latex_run_serialized_text(run)),
        string(rows),
        string(cols),
        array_alignment,
        :none,
        :none,
        LARGE_OP_KIND_NONE,
        :math,
        MATH_ATOM_INNER,
        MATH_GLUE_NONE,
        cells,
        MathPayloadOp[],
        MathPayloadOp[])
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
        MATH_ATOM_ORD,
        MATH_GLUE_NONE,
        MathPayloadOp[],
        MathPayloadOp[],
        MathPayloadOp[]))
    return nothing
end

"""Return recursive payload op for a non-script structured run, or nothing if none applies."""
function payload_for_non_script_segment(run::LatexRun)
    if run.segment == :atom || run.segment == :glue
        return atom_payload_op(run)
    end
    if run.segment in (
        :accent_over, :accent_under, :accent_hat, :accent_tilde,
        :accent_vec, :accent_dot, :accent_ddot, :accent_bar)
        return accent_payload_op(run)
    end
    if run.segment == :radical_sqrt
        return radical_payload_op(run)
    end
    if run.segment == :fraction
        return fraction_payload_op(run)
    end
    if run.segment == :stretch_delimiter
        return stretch_delimiter_payload_op(run)
    end
    if run.segment == :matrix || run.segment == :array
        return matrix_payload_op(run)
    end
    return nothing
end

"""Return true when this segment is one of the script marker segments."""
is_script_segment(segment::Symbol) = segment == :script_sup || segment == :script_sub

"""Append one script run to prior payload when possible, otherwise append fallback payload."""
function consume_script_payload!(payloads::Vector{MathPayloadOp}, run::LatexRun)
    if !isempty(payloads) && payload_op_accepts_scripts(payloads[end])
        payloads[end] = payload_op_with_script(payloads[end], run)
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

struct MathPayloadBlobSpans
    text_offset::Int32
    text_len::Int32
    index_offset::Int32
    index_len::Int32
    sup_offset::Int32
    sup_len::Int32
    sub_offset::Int32
    sub_len::Int32
end

struct BridgeMathOpContext
    child_direct_count::Int32
    secondary_child_direct_count::Int32
    tertiary_child_direct_count::Int32
    table_descriptor_index::Int32
    text_style::Int32
    math_style::Int32
    mathbb_style::Int32
end

"""Append all text spans for one math payload op in bridge field order."""
function append_math_payload_spans!(io::IOBuffer, op::MathPayloadOp)
    text_offset, text_len = append_math_block_blob!(io, op.text)
    index_offset, index_len = append_math_block_blob!(io, op.radical_index_text)
    sup_offset, sup_len = append_math_block_blob!(io, op.sup_text)
    sub_offset, sub_len = append_math_block_blob!(io, op.sub_text)
    return MathPayloadBlobSpans(text_offset, text_len, index_offset, index_len,
        sup_offset, sup_len, sub_offset, sub_len)
end

"""Build one bridge math op payload from one recursive payload op."""
function bridge_math_payload_op(
    io::IOBuffer,
    op::MathPayloadOp,
    ctx::BridgeMathOpContext)

    spans = append_math_payload_spans!(io, op)
    base_style = math_payload_style_id(op.kind,
        op.style_role, ctx.text_style, ctx.math_style, ctx.mathbb_style)
    mode_codes = math_block_mode_codes(op)

    return OdinJuliaBridge.BridgeDynviewMathOp(
        op.kind,
        op.atom_class,
        op.glue_kind,
        base_style,
        ctx.child_direct_count,
        ctx.secondary_child_direct_count,
        ctx.tertiary_child_direct_count,
        ctx.math_style,
        base_style,
        mode_codes.accent_mode,
        mode_codes.radical_mode,
        mode_codes.large_op_kind,
        mode_codes.operator_growth,
        mode_codes.operator_limits,
        ctx.table_descriptor_index,
        spans.text_offset,
        spans.text_len,
        spans.index_offset,
        spans.index_len,
        spans.sup_offset,
        spans.sup_len,
        spans.sub_offset,
        spans.sub_len,
        SCRIPT_SCALE,
        SCRIPT_SUP_RAISE,
        SCRIPT_SUB_DROP,
        SCRIPT_GAP,
        ACCENT_BAR_THICKNESS,
        ACCENT_BAR_OFFSET)
end

"""Return one bridge table descriptor for a recursive matrix payload."""
function bridge_math_table_descriptor(op::MathPayloadOp)
    rows, rows_ok = parse_positive_int(op.radical_index_text)
    columns, columns_ok = parse_positive_int(op.sup_text)
    rows_ok && columns_ok || error("matrix payload has invalid dimensions")
    alignments = ntuple(16) do index
        index > ncodeunits(op.sub_text) && return Int32(1)
        alignment = codeunit(op.sub_text, index)
        alignment == UInt8('l') && return Int32(0)
        alignment == UInt8('r') && return Int32(2)
        return Int32(1)
    end
    return OdinJuliaBridge.BridgeDynviewMathTableDescriptor(
        Int32(rows), Int32(columns), Int32(1), alignments)
end

"""Append one table descriptor and return its block-local index, or -1 for non-tables."""
function append_math_table_descriptor!(
    descriptors::Vector{OdinJuliaBridge.BridgeDynviewMathTableDescriptor},
    payload::MathPayloadOp)

    payload.kind != MATH_OP_MATRIX_RECURSIVE && return Int32(-1)
    push!(descriptors, bridge_math_table_descriptor(payload))
    return Int32(length(descriptors) - 1)
end

"""Flatten recursive payload ops while collecting block-local table descriptors."""
function bridge_math_payload_preorder!(
    payloads::Vector{MathPayloadOp},
    io::IOBuffer,
    descriptors::Vector{OdinJuliaBridge.BridgeDynviewMathTableDescriptor},
    text_style::Integer,
    math_style::Integer,
    mathbb_style::Integer)

    ops = OdinJuliaBridge.BridgeDynviewMathOp[]
    for payload in payloads
        descriptor_index = append_math_table_descriptor!(descriptors, payload)
        child_direct_count, child_ops = bridge_math_payload_preorder!(
            payload.children,
            io,
            descriptors,
            text_style,
            math_style,
            mathbb_style)
        secondary_child_direct_count, secondary_child_ops =
            bridge_math_payload_preorder!(payload.secondary_children, io, descriptors,
                text_style, math_style, mathbb_style)
        tertiary_child_direct_count, tertiary_child_ops =
            bridge_math_payload_preorder!(payload.tertiary_children, io, descriptors,
                text_style, math_style, mathbb_style)
        push!(ops, bridge_math_payload_op(io, payload, BridgeMathOpContext(
            Int32(child_direct_count), Int32(secondary_child_direct_count),
            Int32(tertiary_child_direct_count), descriptor_index,
            Int32(text_style), Int32(math_style), Int32(mathbb_style))))
        append!(ops, child_ops)
        append!(ops, secondary_child_ops)
        append!(ops, tertiary_child_ops)
    end
    return length(payloads), ops
end

"""Flatten recursive payload ops into preorder bridge ops and return direct child count."""
function bridge_math_payload_preorder(
    payloads::Vector{MathPayloadOp}, io::IOBuffer, text_style::Integer,
    math_style::Integer, mathbb_style::Integer)

    descriptors = OdinJuliaBridge.BridgeDynviewMathTableDescriptor[]
    return bridge_math_payload_preorder!(
        payloads, io, descriptors, text_style, math_style, mathbb_style)
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
    if op.kind == MATH_OP_STRETCH_DELIMITER_RECURSIVE
        return MathBlockModeCodes(
            bridge_delimiter_kind(op.radical_index_text),
            bridge_delimiter_kind(op.sup_text),
            Int32(0), OPERATOR_GROWTH_NONE, OPERATOR_LIMITS_NONE)
    end

    accent_mode = bridge_accent_mode(op.accent_mode)
    radical_mode = op.radical_mode == :nthroot ?
        OdinJuliaBridge.BRIDGE_DYNVIEW_RADICAL_MODE_NTHROOT :
        (op.radical_mode == :sqrt ?
            OdinJuliaBridge.BRIDGE_DYNVIEW_RADICAL_MODE_SQRT : Int32(0))

    large_op_kind =
        op.large_op_kind == LARGE_OP_KIND_SUM ?
            OdinJuliaBridge.BRIDGE_DYNVIEW_LARGE_OP_KIND_SUM :
            (op.large_op_kind == LARGE_OP_KIND_PROD ?
                OdinJuliaBridge.BRIDGE_DYNVIEW_LARGE_OP_KIND_PROD :
                (op.large_op_kind == LARGE_OP_KIND_INT ?
                    OdinJuliaBridge.BRIDGE_DYNVIEW_LARGE_OP_KIND_INT :
                    (op.large_op_kind == LARGE_OP_KIND_LIM ?
                        OdinJuliaBridge.BRIDGE_DYNVIEW_LARGE_OP_KIND_LIM :
                        (op.large_op_kind == LARGE_OP_KIND_NARY ?
                            OdinJuliaBridge.BRIDGE_DYNVIEW_LARGE_OP_KIND_NARY :
                            Int32(0)))))
    return MathBlockModeCodes(
        Int32(accent_mode), Int32(radical_mode), Int32(large_op_kind),
        op.operator_growth, op.operator_limits)
end

"""Encode one recursive payload program as recursive bridge ops plus shared text blob."""
function bridge_math_block_payload(
    program::Vector{MathPayloadOp};
    text_style::Integer,
    math_style::Integer,
    mathbb_style::Integer)

    blob = IOBuffer()
    table_descriptors = OdinJuliaBridge.BridgeDynviewMathTableDescriptor[]
    top_level_count, ops = bridge_math_payload_preorder!(
        program,
        blob,
        table_descriptors,
        text_style,
        math_style,
        mathbb_style)
    return BridgeMathBlockPayload(
        plain_text_for_program(program),
        String(take!(blob)),
        ops,
        table_descriptors,
        top_level_count)
end

"""Encode one normalized LaTeX run tree as recursive bridge ops plus shared text blob."""
function bridge_math_block_payload(
    runs::Vector{LatexRun};
    text_style::Integer,
    math_style::Integer,
    mathbb_style::Integer)

    payloads = math_payload_ops_for_runs(runs)
    blob = IOBuffer()
    table_descriptors = OdinJuliaBridge.BridgeDynviewMathTableDescriptor[]
    top_level_count, ops = bridge_math_payload_preorder!(
        payloads,
        blob,
        table_descriptors,
        text_style,
        math_style,
        mathbb_style)
    return BridgeMathBlockPayload(
        plain_text_for_runs(runs),
        String(take!(blob)),
        ops,
        table_descriptors,
        top_level_count)
end

"""Replay a compiled recursive program as one atomic non-wrapping math block."""
function replay_emit_math_block!(
    state_ptr::Ptr{Cvoid},
    program::Vector{MathPayloadOp};
    text_style::Integer=OdinJuliaBridge.BRIDGE_DYNVIEW_STYLE_OUTPUT,
    math_style::Integer=OdinJuliaBridge.BRIDGE_DYNVIEW_STYLE_ITALIC,
    mathbb_style::Integer=OdinJuliaBridge.dynview_style_with_font_flags(
        OdinJuliaBridge.BRIDGE_DYNVIEW_FONT_FLAG_REGULAR))

    payload = bridge_math_block_payload(
        program;
        text_style=text_style,
        math_style=math_style,
        mathbb_style=mathbb_style)
    status = OdinJuliaBridge.dynview_math_block_from_ops(
        state_ptr,
        payload.plain_text,
        math_style,
        payload.ops,
        payload.top_level_count,
        payload.table_descriptors,
        payload.text_blob)
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

    _ = style_profile
    normalized_ast, _ = compile_latex_runs(source)
    payload = bridge_math_block_payload(
        normalized_ast;
        text_style=text_style,
        math_style=math_style,
        mathbb_style=mathbb_style)
    status = OdinJuliaBridge.dynview_math_block_from_ops(
        state_ptr,
        payload.plain_text,
        math_style,
        payload.ops,
        payload.top_level_count,
        payload.table_descriptors,
        payload.text_blob)
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

    return OdinJuliaBridge.dynview_end_block(state_ptr) ==
        OdinJuliaBridge.BRIDGE_STATUS_OK
end
