"""Return the best initial mode estimate for one `text/latex` fragment."""
function classify_latex_mode(source::AbstractString)
    text = String(strip(source))
    if whole_math_source(text) !== nothing
        return LATEX_MODE_MATH
    end

    document_markers = (
        "\\textbf{", "\\textit{", "\\emph{", "\\textcolor{", "\\newline",
        "\\euclid", "\\\\", "\$", "\\(", "\\[")
    return any(marker -> occursin(marker, text), document_markers) ?
        LATEX_MODE_DOCUMENT : LATEX_MODE_MATH
end

"""Remove one complete outer math delimiter pair, or return `nothing`."""
function whole_math_source(source::String)
    isempty(source) && return nothing
    parser = LatexDocumentParser(source, firstindex(source))
    math_source, _, ok = consume_document_math!(parser)
    return ok && parser.index > lastindex(source) ? math_source : nothing
end

"""Append text while merging adjacent document runs with the same style and color."""
function push_document_text!(
    runs::Vector{LatexDocumentRun},
    text::String,
    font_flags::Int32,
    color::Union{Nothing,OdinJuliaBridge.BridgeColor})

    if isempty(text)
        return nothing
    end
    if !isempty(runs) && runs[end].kind == :text &&
            runs[end].font_flags == font_flags && runs[end].color == color
        runs[end] = LatexDocumentRun(
            :text, runs[end].text * text, font_flags, nothing, color)
        return nothing
    end
    push!(runs, LatexDocumentRun(:text, text, font_flags, nothing, color))
    return nothing
end

"""Append one document line break, suppressing runs beyond a blank line."""
function push_document_line_break!(runs::Vector{LatexDocumentRun})
    if length(runs) >= 2 && runs[end].kind == :line_break &&
        runs[end - 1].kind == :line_break
        return nothing
    end
    push!(runs, LatexDocumentRun(:line_break, "", DOCUMENT_STYLE_REGULAR))
    return nothing
end

"""Return a recognized styled-document command and its accumulated flag."""
function document_style_command(parser::LatexDocumentParser, font_flags::Int32)
    tail = SubString(parser.source, parser.index)
    if startswith(tail, "\\textbf{")
        return "\\textbf{", font_flags | DOCUMENT_STYLE_BOLD
    end
    if startswith(tail, "\\textit{")
        return "\\textit{", font_flags | DOCUMENT_STYLE_ITALIC
    end
    if startswith(tail, "\\emph{")
        return "\\emph{", font_flags | DOCUMENT_STYLE_ITALIC
    end
    return "", font_flags
end

"""Resolve a document text color by LaTeX, Julia palette, then Colors.jl vocabulary."""
function resolve_document_text_color(
    name::AbstractString,
    inherited::Union{Nothing,OdinJuliaBridge.BridgeColor})

    normalized = lowercase(String(strip(name)))
    haskey(DOCUMENT_LATEX_COLORS, normalized) && return DOCUMENT_LATEX_COLORS[normalized]
    try
        return OdinJuliaBridge.bridge_color(normalized)
    catch
        return inherited
    end
end

"""Consume one required braced textcolor name at the parser cursor."""
function consume_document_color_name!(parser::LatexDocumentParser)
    parser.index > lastindex(parser.source) && return "", false
    parser.source[parser.index] == '{' || return "", false
    start = nextind(parser.source, parser.index)
    close_index = findnext('}', parser.source, start)
    close_index === nothing && return "", false
    name = start == close_index ?
        "" : parser.source[start:prevind(parser.source, close_index)]
    parser.index = nextind(parser.source, close_index)
    return String(name), !isempty(strip(name))
end

"""Return delimiters and document run kind for math at the parser cursor."""
function document_math_delimiters(parser::LatexDocumentParser)
    tail = SubString(parser.source, parser.index)
    startswith(tail, "\$\$") && return "\$\$", "\$\$", :math_display
    startswith(tail, "\$") && return "\$", "\$", :math_inline
    startswith(tail, "\\(") && return "\\(", "\\)", :math_inline
    startswith(tail, "\\[") && return "\\[", "\\]", :math_display
    return "", "", :none
end

"""Return true when the document parser is at a supported math opener."""
function document_math_starts_at_cursor(parser::LatexDocumentParser)
    opener, _, _ = document_math_delimiters(parser)
    return !isempty(opener)
end

"""Read a delimited math fragment and its document run kind at the parser cursor."""
function consume_document_math!(parser::LatexDocumentParser)
    opener, closer, run_kind = document_math_delimiters(parser)
    if isempty(opener)
        return "", :none, false
    end

    content_start = parser.index + ncodeunits(opener)
    close_index = findnext(closer, parser.source, content_start)
    if close_index === nothing
        return "", :none, false
    end
    content_end = prevind(parser.source, first(close_index))
    parser.index = nextind(parser.source, last(close_index))
    content = content_start > content_end ? "" : parser.source[content_start:content_end]
    return content, run_kind, true
end

"""Consume document whitespace beginning with a source newline."""
function consume_document_newlines!(
    parser::LatexDocumentParser,
    runs::Vector{LatexDocumentRun},
    font_flags::Int32,
    color::Union{Nothing,OdinJuliaBridge.BridgeColor})

    newline_count = 0
    while parser.index <= lastindex(parser.source) && isspace(parser.source[parser.index])
        if parser.source[parser.index] == '\n'
            newline_count += 1
        end
        parser.index = nextind(parser.source, parser.index)
    end

    if newline_count >= 2
        push_document_line_break!(runs)
        push_document_line_break!(runs)
    else
        push_document_text!(runs, " ", font_flags, color)
    end
    return nothing
end

"""Consume plain document text up to the next syntax character."""
function consume_document_text!(
    parser::LatexDocumentParser,
    runs::Vector{LatexDocumentRun},
    font_flags::Int32,
    color::Union{Nothing,OdinJuliaBridge.BridgeColor})

    start = parser.index
    while parser.index <= lastindex(parser.source)
        c = parser.source[parser.index]
        if c == '\\' || c == '\$' || c == '}' || c == '\n'
            break
        end
        parser.index = nextind(parser.source, parser.index)
    end
    push_document_text!(runs,
        normalize_text_whitespace(
            parser.source[start:prevind(parser.source, parser.index)]),
        font_flags, color)
    return nothing
end

"""Consume one recognized styled command and append its flattened child runs."""
function consume_document_style!(
    parser::LatexDocumentParser,
    runs::Vector{LatexDocumentRun},
    command::String,
    child_flags::Int32,
    color::Union{Nothing,OdinJuliaBridge.BridgeColor})

    parser.index += ncodeunits(command)
    children, ok = parse_document_sequence!(parser, child_flags, color, true)
    ok || return false
    append!(runs, children)
    return true
end

"""Consume a textcolor command while inheriting unresolved names from context."""
function consume_document_textcolor!(
    parser::LatexDocumentParser,
    runs::Vector{LatexDocumentRun},
    font_flags::Int32,
    inherited::Union{Nothing,OdinJuliaBridge.BridgeColor})

    parser.index += ncodeunits("\\textcolor")
    color_name, ok = consume_document_color_name!(parser)
    ok || return false
    parser.index <= lastindex(parser.source) && parser.source[parser.index] == '{' ||
        return false
    parser.index = nextind(parser.source, parser.index)
    color = resolve_document_text_color(color_name, inherited)
    children, children_ok = parse_document_sequence!(parser, font_flags, color, true)
    children_ok || return false
    append!(runs, children)
    return true
end

"""Return true when a complete command name begins at the parser cursor."""
function document_command_matches(parser::LatexDocumentParser, command::String)
    startswith(SubString(parser.source, parser.index), command) || return false
    next_index = parser.index + ncodeunits(command)
    return next_index > lastindex(parser.source) || !isletter(parser.source[next_index])
end

"""Return the recognized Euclid inline-shape command at the parser cursor."""
function document_shape_command(parser::LatexDocumentParser)
    document_command_matches(parser, "\\euclidpoint") && return "\\euclidpoint", :point
    document_command_matches(parser, "\\euclidline") && return "\\euclidline", :line
    document_command_matches(parser, "\\euclidcircle") && return "\\euclidcircle", :circle
    document_command_matches(parser, "\\euclidbox") && return "\\euclidbox", :box
    document_command_matches(parser, "\\euclidangle") && return "\\euclidangle", :angle
    document_command_matches(parser, "\\euclidsemicircle") && return "\\euclidsemicircle", :semicircle
    document_command_matches(parser, "\\euclidperpendicular") && return "\\euclidperpendicular", :perpendicular
    document_command_matches(parser, "\\euclidtriangle") && return "\\euclidtriangle", :triangle
    document_command_matches(parser, "\\euclidpentagon") && return "\\euclidpentagon", :pentagon
    return "", :none
end

"""Parse one finite positive shape dimension."""
function parse_document_shape_dimension(text::AbstractString)
    value = tryparse(Float32, strip(text))
    return value !== nothing && isfinite(value) && value > 0f0 ? value : nothing
end

"""Parse one strict shape boolean value."""
function parse_document_shape_bool(text::AbstractString)
    value = lowercase(strip(text))
    value == "true" && return true
    value == "false" && return false
    return nothing
end

"""Parse one optional shape color through the bridge color vocabulary."""
function parse_document_shape_color(text::AbstractString)
    color_name = String(strip(text))
    isempty(color_name) && return nothing
    try
        return OdinJuliaBridge.bridge_color(color_name)
    catch
        return nothing
    end
end

"""Read one optional bracketed shape-option payload."""
function consume_document_shape_options!(parser::LatexDocumentParser)
    if parser.index > lastindex(parser.source) || parser.source[parser.index] != '['
        return "", true
    end
    close_index = findnext(']', parser.source, nextind(parser.source, parser.index))
    close_index === nothing && return "", false
    start = nextind(parser.source, parser.index)
    options = start == close_index ?
        "" : parser.source[start:prevind(parser.source, close_index)]
    parser.index = nextind(parser.source, close_index)
    return options, true
end

"""Parse comma-separated shape options while rejecting empty and duplicate keys."""
function parse_document_shape_options(text::String)
    options = Dict{String,String}()
    isempty(strip(text)) && return options
    for raw_option in split(text, ',')
        option = strip(raw_option)
        isempty(option) && return nothing
        if option == "filled"
            haskey(options, "filled") && return nothing
            options["filled"] = "true"
            continue
        end
        parts = split(option, '='; limit=2)
        length(parts) == 2 || return nothing
        key = String(strip(parts[1]))
        value = String(strip(parts[2]))
        (isempty(key) || isempty(value) || haskey(options, key)) && return nothing
        options[key] = value
    end
    return options
end

"""Return the allowed option names for one Euclid shape kind."""
function document_shape_allowed_options(kind::Symbol)
    kind == :point && return Set(["color", "size"])
    kind == :line && return Set(["color", "length", "thickness"])
    kind == :circle && return Set(["color", "size", "thickness", "filled"])
    kind == :box && return Set(["color", "width", "height", "thickness", "filled", "edge1_color", "edge2_color", "edge3_color", "edge4_color"])
    kind == :angle && return Set(["color", "radius", "start", "end", "thickness", "filled", "fill_color", "arc_color"])
    kind == :semicircle && return Set(["color", "radius", "thickness", "filled", "fill_color", "arc_color"])
    kind == :perpendicular && return Set(["color", "length", "width", "height", "thickness", "line1_color", "line2_color"])
    kind == :triangle && return Set(["color", "width", "height", "thickness", "filled", "fill_color", "edge1_color", "edge2_color", "edge3_color"])
    kind == :pentagon && return Set(["color", "width", "height", "thickness", "filled", "fill_color", "edge1_color", "edge2_color", "edge3_color", "edge4_color", "edge5_color"])
    return Set{String}()
end

"""Resolve one optional shape color and report whether it is valid."""
function document_shape_option_color(options::Dict{String,String})
    haskey(options, "color") || return nothing, true
    color = parse_document_shape_color(options["color"])
    return color, color !== nothing
end

"""Resolve one optional shape color key with a fallback default."""
function document_shape_option_color_or(
    options::Dict{String,String}, key::String,
    default::Union{Nothing,OdinJuliaBridge.BridgeColor})

    haskey(options, key) || return default, true
    color = parse_document_shape_color(options[key])
    return color, color !== nothing
end

"""Resolve one optional positive shape dimension."""
function document_shape_option_dimension(
    options::Dict{String,String}, key::String, default::Float32)

    haskey(options, key) || return default
    return parse_document_shape_dimension(options[key])
end

"""Resolve one optional shape boolean."""
function document_shape_option_bool(
    options::Dict{String,String}, key::String, default::Bool)

    haskey(options, key) || return default
    return parse_document_shape_bool(options[key])
end

"""Return the width option name and default for one shape kind."""
function document_shape_width_rule(kind::Symbol)
    kind == :line && return "length", 3f0
    kind == :box && return "width", 2f0
    kind == :angle && return "radius", 1f0
    kind == :perpendicular && return "length", 2f0
    kind == :triangle && return "width", 1f0
    kind == :pentagon && return "width", 1f0
    return "size", 1f0
end

"""Build one validated Euclid angle-marker payload from parsed options."""
function document_shape_payload_angle(options::Dict{String,String})
    all(key -> key in document_shape_allowed_options(:angle), keys(options)) ||
        return nothing
    color, color_ok = document_shape_option_color(options)
    color_ok || return nothing
    radius = document_shape_option_dimension(options, "radius", 1f0)
    start_angle = document_shape_option_dimension(options, "start", 0f0)
    end_angle = document_shape_option_dimension(options, "end", 90f0)
    thickness = document_shape_option_dimension(options, "thickness", 1f0)
    filled = document_shape_option_bool(options, "filled", false)
    (radius === nothing || start_angle === nothing || end_angle === nothing ||
        thickness === nothing || filled === nothing) && return nothing
    fill_color, fill_ok = document_shape_option_color_or(options, "fill_color", color)
    fill_ok || return nothing
    arc_color, arc_ok = document_shape_option_color_or(options, "arc_color", color)
    arc_ok || return nothing
    return LatexDocumentShape(:angle, color, radius, 0f0, thickness, filled,
        start_angle, end_angle, fill_color, arc_color,
        nothing, nothing, nothing, nothing, nothing)
end

"""Build one validated Euclid semicircle payload from parsed options."""
function document_shape_payload_semicircle(options::Dict{String,String})
    all(key -> key in document_shape_allowed_options(:semicircle), keys(options)) ||
        return nothing
    color, color_ok = document_shape_option_color(options)
    color_ok || return nothing
    radius = document_shape_option_dimension(options, "radius", 1f0)
    thickness = document_shape_option_dimension(options, "thickness", 1f0)
    filled = document_shape_option_bool(options, "filled", false)
    (radius === nothing || thickness === nothing || filled === nothing) && return nothing
    fill_color, fill_ok = document_shape_option_color_or(options, "fill_color", color)
    fill_ok || return nothing
    arc_color, arc_ok = document_shape_option_color_or(options, "arc_color", color)
    arc_ok || return nothing

    # Fixed top-half arc from 0 to 180 degrees.
    return LatexDocumentShape(:angle, color, radius, 0f0, thickness, filled, 0f0, 180f0,
        fill_color, arc_color, nothing, nothing, nothing, nothing, nothing)
end

"""Build one validated Euclid perpendicular payload from parsed options."""
function document_shape_payload_perpendicular(options::Dict{String,String})
    all(key -> key in document_shape_allowed_options(:perpendicular), keys(options)) ||
        return nothing
    color, color_ok = document_shape_option_color(options)
    color_ok || return nothing
    width = document_shape_option_dimension(options, "width", 2f0)
    length = document_shape_option_dimension(options, "length", width)
    height = document_shape_option_dimension(options, "height", 1f0)
    thickness = document_shape_option_dimension(options, "thickness", 1f0)
    (length === nothing || height === nothing || thickness === nothing) && return nothing
    line1_color, line1_ok = document_shape_option_color_or(options, "line1_color", color)
    line1_ok || return nothing
    line2_color, line2_ok = document_shape_option_color_or(options, "line2_color", color)
    line2_ok || return nothing
    return LatexDocumentShape(:perpendicular, color, length, height, thickness,
        false, 0f0, 0f0, nothing, nothing, line1_color, line2_color,
        nothing, nothing, nothing)
end

"""Build one validated Euclid triangle payload from parsed options."""
function document_shape_triangle_dimensions(options::Dict{String,String})
    width = document_shape_option_dimension(options, "width", 1f0)
    height = document_shape_option_dimension(options, "height", width)
    thickness = document_shape_option_dimension(options, "thickness", 1f0)
    filled = document_shape_option_bool(options, "filled", false)
    (width === nothing || height === nothing || thickness === nothing ||
        filled === nothing) &&
        return nothing
    return width, height, thickness, filled
end

"""Resolve the four triangle colors from parsed options."""
function document_shape_triangle_colors(options::Dict{String,String}, default_color)
    fill_color, fill_ok =
        document_shape_option_color_or(options, "fill_color", default_color)
    fill_ok || return nothing
    edge1_color, edge1_ok =
        document_shape_option_color_or(options, "edge1_color", default_color)
    edge1_ok || return nothing
    edge2_color, edge2_ok =
        document_shape_option_color_or(options, "edge2_color", default_color)
    edge2_ok || return nothing
    edge3_color, edge3_ok =
        document_shape_option_color_or(options, "edge3_color", default_color)
    edge3_ok || return nothing
    return fill_color, edge1_color, edge2_color, edge3_color
end

"""Build one validated Euclid triangle payload from parsed options."""
function document_shape_payload_triangle(options::Dict{String,String})
    all(key -> key in document_shape_allowed_options(:triangle), keys(options)) ||
     return nothing
    color, color_ok = document_shape_option_color(options)
    color_ok || return nothing
    dims = document_shape_triangle_dimensions(options)
    dims === nothing && return nothing
    width, height, thickness, filled = dims
    colors = document_shape_triangle_colors(options, color)
    colors === nothing && return nothing
    fill_color, edge1_color, edge2_color, edge3_color = colors
    return LatexDocumentShape(:triangle, color, width, height, thickness, filled,
        0f0, 0f0, fill_color, nothing, edge1_color, edge2_color, edge3_color,
        nothing, nothing)
end

"""Resolve box width/height/thickness/filled values."""
function document_shape_box_dimensions(options::Dict{String,String})
    width = document_shape_option_dimension(options, "width", 2f0)
    height = document_shape_option_dimension(options, "height", 1f0)
    thickness = document_shape_option_dimension(options, "thickness", 1f0)
    filled = document_shape_option_bool(options, "filled", false)
    (width === nothing || height === nothing ||
        thickness === nothing || filled === nothing) &&
        return nothing
    return width, height, thickness, filled
end

"""Resolve four edge colors with per-key fallback to default color."""
function document_shape_box_edge_colors(options::Dict{String,String}, default_color)
    edge1_color, edge1_ok = document_shape_option_color_or(options, "edge1_color", default_color)
    edge1_ok || return nothing
    edge2_color, edge2_ok = document_shape_option_color_or(options, "edge2_color", default_color)
    edge2_ok || return nothing
    edge3_color, edge3_ok = document_shape_option_color_or(options, "edge3_color", default_color)
    edge3_ok || return nothing
    edge4_color, edge4_ok = document_shape_option_color_or(options, "edge4_color", default_color)
    edge4_ok || return nothing
    return edge1_color, edge2_color, edge3_color, edge4_color
end

"""Build one validated Euclid box payload from parsed options."""
function document_shape_payload_box(options::Dict{String,String})
    all(key -> key in document_shape_allowed_options(:box), keys(options)) ||
        return nothing
    color, color_ok = document_shape_option_color(options)
    color_ok || return nothing
    dims = document_shape_box_dimensions(options)
    dims === nothing && return nothing
    width, height, thickness, filled = dims

    edge_colors = document_shape_box_edge_colors(options, color)
    edge_colors === nothing && return nothing
    edge1_color, edge2_color, edge3_color, edge4_color = edge_colors

    return LatexDocumentShape(:box, color, width, height, thickness, filled, 0f0, 0f0,
        nothing, nothing, edge1_color, edge2_color, edge3_color, edge4_color, nothing)
end

"""Resolve pentagon width/height/thickness/filled values."""
function document_shape_pentagon_dimensions(options::Dict{String,String})
    width = document_shape_option_dimension(options, "width", 1f0)
    height = document_shape_option_dimension(options, "height", width)
    thickness = document_shape_option_dimension(options, "thickness", 1f0)
    filled = document_shape_option_bool(options, "filled", false)
    (width === nothing || height === nothing ||
        thickness === nothing || filled === nothing) &&
        return nothing
    return width, height, thickness, filled
end

"""Resolve pentagon fill and edge colors with per-key fallback."""
function document_shape_pentagon_colors(options::Dict{String,String}, default_color)
    fill_color, fill_ok =
        document_shape_option_color_or(options, "fill_color", default_color)
    fill_ok || return nothing
    edge1_color, edge1_ok =
        document_shape_option_color_or(options, "edge1_color", default_color)
    edge1_ok || return nothing
    edge2_color, edge2_ok =
        document_shape_option_color_or(options, "edge2_color", default_color)
    edge2_ok || return nothing
    edge3_color, edge3_ok =
        document_shape_option_color_or(options, "edge3_color", default_color)
    edge3_ok || return nothing
    edge4_color, edge4_ok =
        document_shape_option_color_or(options, "edge4_color", default_color)
    edge4_ok || return nothing
    edge5_color, edge5_ok =
        document_shape_option_color_or(options, "edge5_color", default_color)
    edge5_ok || return nothing
    return fill_color, edge1_color, edge2_color, edge3_color, edge4_color, edge5_color
end

"""Build one validated Euclid pentagon payload from parsed options."""
function document_shape_payload_pentagon(options::Dict{String,String})
    all(key -> key in document_shape_allowed_options(:pentagon), keys(options)) ||
        return nothing
    color, color_ok = document_shape_option_color(options)
    color_ok || return nothing
    dims = document_shape_pentagon_dimensions(options)
    dims === nothing && return nothing
    width, height, thickness, filled = dims

    colors = document_shape_pentagon_colors(options, color)
    colors === nothing && return nothing
    fill_color, edge1_color, edge2_color, edge3_color, edge4_color, edge5_color = colors

    return LatexDocumentShape(:pentagon, color, width, height, thickness, filled,
        0f0, 0f0, fill_color, nothing, edge1_color, edge2_color, edge3_color,
        edge4_color, edge5_color)
end

"""Build one validated Euclid shape payload from parsed options for basic shapes."""
function document_shape_payload_basic(kind::Symbol, options::Dict{String,String})
    all(key -> key in document_shape_allowed_options(kind), keys(options)) ||
        return nothing
    color, color_ok = document_shape_option_color(options)
    color_ok || return nothing
    width_key, default_width = document_shape_width_rule(kind)
    width = document_shape_option_dimension(options, width_key, default_width)
    height = document_shape_option_dimension(options, "height", 1f0)
    thickness = document_shape_option_dimension(options, "thickness", 1f0)
    filled = document_shape_option_bool(options, "filled", false)
    (width === nothing || height === nothing ||
        thickness === nothing || filled === nothing) &&
        return nothing
    return LatexDocumentShape(kind, color, width, height, thickness,
        kind == :point || filled,
        0f0, 0f0, nothing, nothing, nothing, nothing, nothing, nothing, nothing)
end

"""Build one validated Euclid shape payload from parsed options."""
function document_shape_payload(kind::Symbol, options::Dict{String,String})
    kind == :angle && return document_shape_payload_angle(options)
    kind == :semicircle && return document_shape_payload_semicircle(options)
    kind == :perpendicular && return document_shape_payload_perpendicular(options)
    kind == :triangle && return document_shape_payload_triangle(options)
    kind == :box && return document_shape_payload_box(options)
    kind == :pentagon && return document_shape_payload_pentagon(options)
    return document_shape_payload_basic(kind, options)
end

"""Consume one Euclid inline-shape command into a structured document run."""
function consume_document_shape!(
    parser::LatexDocumentParser,
    runs::Vector{LatexDocumentRun},
    command::String,
    kind::Symbol,
    font_flags::Int32,
    color::Union{Nothing,OdinJuliaBridge.BridgeColor})

    parser.index += ncodeunits(command)
    option_text, ok = consume_document_shape_options!(parser)
    ok || return false
    options = parse_document_shape_options(option_text)
    options === nothing && return false
    shape = document_shape_payload(kind, options)
    shape === nothing && return false
    push!(runs, LatexDocumentRun(:shape, "", font_flags, shape, color))
    return true
end

"""Return the first source index after contiguous horizontal whitespace."""
function index_after_horizontal_whitespace(source::String, start::Int)
    index = start
    while index <= lastindex(source) && (source[index] == ' ' || source[index] == '\t')
        index = nextind(source, index)
    end
    return index
end

"""Consume source whitespace attached to one forced line-break command."""
function consume_forced_break_whitespace!(parser::LatexDocumentParser)
    parser.index = index_after_horizontal_whitespace(parser.source, parser.index)
    if parser.index <= lastindex(parser.source) && parser.source[parser.index] == '\n'
        next_index = nextind(parser.source, parser.index)
        next_index = index_after_horizontal_whitespace(parser.source, next_index)
        if next_index > lastindex(parser.source) || parser.source[next_index] != '\n'
            parser.index = next_index
        end
    end
    return nothing
end

"""Consume one forced line-break command and its attached source whitespace."""
function consume_document_forced_break!(
    parser::LatexDocumentParser,
    runs::Vector{LatexDocumentRun},
    command::String)

    parser.index += ncodeunits(command)
    consume_forced_break_whitespace!(parser)
    push_document_line_break!(runs)
    return true
end

"""Consume one inline or display math fragment into a document run."""
function consume_document_math_run!(
    parser::LatexDocumentParser,
    runs::Vector{LatexDocumentRun},
    color::Union{Nothing,OdinJuliaBridge.BridgeColor})

    math_source, run_kind, ok = consume_document_math!(parser)
    if !ok || isempty(strip(math_source))
        return false
    end
    push!(runs, LatexDocumentRun(
        run_kind, String(strip(math_source)), DOCUMENT_STYLE_REGULAR, nothing, color))
    return true
end

"""Consume document prose, newlines, or one forced line-break command."""
function consume_document_prose_or_break!(
    parser::LatexDocumentParser,
    runs::Vector{LatexDocumentRun},
    font_flags::Int32,
    color::Union{Nothing,OdinJuliaBridge.BridgeColor})

    c = parser.source[parser.index]
    c == '\n' &&
        (consume_document_newlines!(parser, runs, font_flags, color); return true)
    tail = SubString(parser.source, parser.index)
    startswith(tail, "\\\\") && return consume_document_forced_break!(parser, runs, "\\\\")
    startswith(tail, "\\newline") &&
        return consume_document_forced_break!(parser, runs, "\\newline")
    c == '\\' && return false
    consume_document_text!(parser, runs, font_flags, color)
    return true
end

"""Parse and append one document run at the current cursor."""
function consume_document_run!(
    parser::LatexDocumentParser,
    runs::Vector{LatexDocumentRun},
    font_flags::Int32,
    color::Union{Nothing,OdinJuliaBridge.BridgeColor})

    startswith(SubString(parser.source, parser.index), "\\textcolor{") &&
        return consume_document_textcolor!(parser, runs, font_flags, color)
    command, child_flags = document_style_command(parser, font_flags)
    !isempty(command) && return consume_document_style!(
        parser, runs, command, child_flags, color)
    shape_command, shape_kind = document_shape_command(parser)
    !isempty(shape_command) && return consume_document_shape!(
        parser, runs, shape_command, shape_kind, font_flags, color)
    document_math_starts_at_cursor(parser) &&
        return consume_document_math_run!(parser, runs, color)
    return consume_document_prose_or_break!(parser, runs, font_flags, color)
end

"""Parse document runs recursively until source end or one closing brace."""
function parse_document_sequence!(
    parser::LatexDocumentParser,
    font_flags::Int32,
    color::Union{Nothing,OdinJuliaBridge.BridgeColor},
    stop_on_rbrace::Bool)

    runs = LatexDocumentRun[]
    while parser.index <= lastindex(parser.source)
        if parser.source[parser.index] == '}'
            parser.index = nextind(parser.source, parser.index)
            return runs, stop_on_rbrace
        end
        consume_document_run!(parser, runs, font_flags, color) ||
            return LatexDocumentRun[], false
    end
    return runs, !stop_on_rbrace
end

"""Parse the supported document-mode LaTeX subset, returning `nothing` on failure."""
function parse_latex_document(source::AbstractString)
    text = String(source)
    if isempty(text)
        return LatexDocumentRun[]
    end
    parser = LatexDocumentParser(text, firstindex(text))
    runs, ok = parse_document_sequence!(parser, DOCUMENT_STYLE_REGULAR, nothing, false)
    return ok ? runs : nothing
end

"""Return the bridge style id for one flat document text run."""
function document_run_style_id(run::LatexDocumentRun, text_style::Integer)
    if run.font_flags == DOCUMENT_STYLE_REGULAR
        return Int32(text_style)
    end
    return OdinJuliaBridge.dynview_style_with_font_flags(run.font_flags)
end

"""Replay one display-math run with surrounding breaks when not already present."""
function replay_document_display_math!(
    state_ptr::Ptr{Cvoid},
    runs::Vector{LatexDocumentRun},
    i::Int,
    text_style::Integer)
    if i == firstindex(runs) || runs[prevind(runs, i)].kind != :line_break
        OdinJuliaBridge.dynview_line_break(state_ptr) ==
            OdinJuliaBridge.BRIDGE_STATUS_OK ||
            return false
    end
    replay_emit_math_block!(state_ptr, runs[i].text; text_style=text_style) ||
         return false
    if i == lastindex(runs) || runs[nextind(runs, i)].kind != :line_break
        OdinJuliaBridge.dynview_line_break(state_ptr) ==
            OdinJuliaBridge.BRIDGE_STATUS_OK ||
            return false
    end
    return true
end

"""Replay one angle-marker shape through the pie-section bridge primitive."""
function replay_document_angle_shape!(
    state_ptr::Ptr{Cvoid}, shape::LatexDocumentShape, style_id::Int32)

    fill_color = something(shape.fill_color,
        something(shape.color, OdinJuliaBridge.bridge_color("white")))
    arc_color = something(shape.arc_color,
        something(shape.color, OdinJuliaBridge.bridge_color("white")))
    status = OdinJuliaBridge.dynview_inline_pie_section(
        state_ptr,
        shape.width,
        shape.start_angle,
        shape.end_angle,
        style_id,
        shape.filled,
        fill_color,
        arc_color,
        shape.thickness)
    return status == OdinJuliaBridge.BRIDGE_STATUS_OK
end

"""Replay one perpendicular shape through the dedicated bridge primitive."""
function replay_document_perpendicular_shape!(
    state_ptr::Ptr{Cvoid}, shape::LatexDocumentShape, style_id::Int32)

    top_color = something(
        shape.edge_color_1, something(shape.color, OdinJuliaBridge.bridge_color("white")))
    stem_color = something(
        shape.edge_color_2, something(shape.color, OdinJuliaBridge.bridge_color("white")))
    status = OdinJuliaBridge.dynview_inline_perpendicular(
        state_ptr,
        shape.width,
        shape.height,
        shape.thickness,
        style_id,
        top_color,
        stem_color)
    return status == OdinJuliaBridge.BRIDGE_STATUS_OK
end

"""Replay one triangle shape through the dedicated bridge primitive."""
function replay_document_triangle_shape!(
    state_ptr::Ptr{Cvoid}, shape::LatexDocumentShape, style_id::Int32)

    fill_color = something(
        shape.fill_color, something(shape.color, OdinJuliaBridge.bridge_color("white")))
    edge1_color = something(
        shape.edge_color_1, something(shape.color, OdinJuliaBridge.bridge_color("white")))
    edge2_color = something(
        shape.edge_color_2, something(shape.color, OdinJuliaBridge.bridge_color("white")))
    edge3_color = something(
        shape.edge_color_3, something(shape.color, OdinJuliaBridge.bridge_color("white")))
    status = OdinJuliaBridge.dynview_inline_triangle(
        state_ptr,
        shape.width,
        shape.height,
        shape.thickness,
        style_id,
        shape.filled,
        fill_color,
        edge1_color,
        edge2_color,
        edge3_color)
    return status == OdinJuliaBridge.BRIDGE_STATUS_OK
end

"""Replay one pentagon shape through the dedicated bridge primitive."""
function replay_document_pentagon_shape!(
    state_ptr::Ptr{Cvoid}, shape::LatexDocumentShape, style_id::Int32)

    fill_color = something(
        shape.fill_color, something(shape.color, OdinJuliaBridge.bridge_color("white")))
    edge1_color = something(
        shape.edge_color_1, something(shape.color, OdinJuliaBridge.bridge_color("white")))
    edge2_color = something(
        shape.edge_color_2, something(shape.color, OdinJuliaBridge.bridge_color("white")))
    edge3_color = something(
        shape.edge_color_3, something(shape.color, OdinJuliaBridge.bridge_color("white")))
    edge4_color = something(
        shape.edge_color_4, something(shape.color, OdinJuliaBridge.bridge_color("white")))
    edge5_color = something(
        shape.edge_color_5, something(shape.color, OdinJuliaBridge.bridge_color("white")))
    status = OdinJuliaBridge.dynview_inline_pentagon(
        state_ptr,
        shape.width,
        shape.height,
        shape.thickness,
        style_id,
        shape.filled,
        fill_color,
        edge1_color,
        edge2_color,
        edge3_color,
        edge4_color,
        edge5_color)
    return status == OdinJuliaBridge.BRIDGE_STATUS_OK
end

"""Replay one line or outline shape through the matching bridge primitive."""
function replay_document_outline_shape!(
    state_ptr::Ptr{Cvoid}, shape::LatexDocumentShape, style_id::Int32)

    if shape.kind == :line
        status = shape.color === nothing ?
            OdinJuliaBridge.dynview_inline_line(
                state_ptr, shape.width, shape.thickness, style_id) :
            OdinJuliaBridge.dynview_inline_line_brush(
                state_ptr, shape.width, shape.thickness, style_id, shape.color)
        return status == OdinJuliaBridge.BRIDGE_STATUS_OK
    end
    if shape.kind == :circle
        status = shape.color === nothing ?
            OdinJuliaBridge.dynview_inline_circle(
                state_ptr, shape.width, shape.thickness, style_id) :
            OdinJuliaBridge.dynview_inline_circle_brush(
                state_ptr, shape.width, shape.thickness, style_id, shape.color)
        return status == OdinJuliaBridge.BRIDGE_STATUS_OK
    end
    if shape.edge_color_1 !== nothing || shape.edge_color_2 !== nothing ||
            shape.edge_color_3 !== nothing || shape.edge_color_4 !== nothing
        default_color = something(shape.color, OdinJuliaBridge.bridge_color("white"))
        edge1_color = something(shape.edge_color_1, default_color)
        edge2_color = something(shape.edge_color_2, default_color)
        edge3_color = something(shape.edge_color_3, default_color)
        edge4_color = something(shape.edge_color_4, default_color)
        status = OdinJuliaBridge.dynview_inline_box_edges(
            state_ptr,
            shape.width,
            shape.height,
            shape.thickness,
            style_id,
            edge1_color,
            edge2_color,
            edge3_color,
            edge4_color)
        return status == OdinJuliaBridge.BRIDGE_STATUS_OK
    end

    status = shape.color === nothing ?
        OdinJuliaBridge.dynview_inline_box(
            state_ptr, shape.width, shape.height, shape.thickness, style_id) :
        OdinJuliaBridge.dynview_inline_box_brush(
            state_ptr, shape.width, shape.height, shape.thickness, style_id, shape.color)
    return status == OdinJuliaBridge.BRIDGE_STATUS_OK
end

"""Replay one filled point, circle, or box shape."""
function replay_document_filled_shape!(
    state_ptr::Ptr{Cvoid}, shape::LatexDocumentShape, style_id::Int32)

    color = something(shape.color, OdinJuliaBridge.bridge_color("white"))
    if shape.kind == :point || shape.kind == :circle
        status = OdinJuliaBridge.dynview_inline_filled_circle(
            state_ptr, shape.width, style_id, color, 0)
        return status == OdinJuliaBridge.BRIDGE_STATUS_OK
    end
    status = OdinJuliaBridge.dynview_inline_filled_box(
        state_ptr, shape.width, shape.height, style_id, color, 0)
    return status == OdinJuliaBridge.BRIDGE_STATUS_OK
end

"""Replay one structured Euclid inline shape."""
function replay_document_shape!(
    state_ptr::Ptr{Cvoid}, run::LatexDocumentRun, text_style::Integer)

    run.shape === nothing && return false
    style_id = document_run_style_id(run, text_style)
    run.shape.kind == :angle &&
        return replay_document_angle_shape!(state_ptr, run.shape, style_id)
    run.shape.kind == :perpendicular &&
        return replay_document_perpendicular_shape!(state_ptr, run.shape, style_id)
    run.shape.kind == :triangle &&
        return replay_document_triangle_shape!(state_ptr, run.shape, style_id)
    run.shape.kind == :pentagon &&
        return replay_document_pentagon_shape!(state_ptr, run.shape, style_id)
    return run.shape.filled ?
        replay_document_filled_shape!(state_ptr, run.shape, style_id) :
        replay_document_outline_shape!(state_ptr, run.shape, style_id)
end

"""Replay one parsed document run into the currently open dynview block."""
function replay_document_run!(
    state_ptr::Ptr{Cvoid}, runs::Vector{LatexDocumentRun}, i::Int, text_style::Integer)
    run = runs[i]
    if run.kind == :text
        style_id = document_run_style_id(run, text_style)
        status = run.color === nothing ?
            OdinJuliaBridge.dynview_text_run(state_ptr, run.text, style_id) :
            OdinJuliaBridge.dynview_text_run_brush(
                state_ptr, run.text, style_id, run.color)
        return status == OdinJuliaBridge.BRIDGE_STATUS_OK
    end
    if run.kind == :line_break
        return OdinJuliaBridge.dynview_line_break(state_ptr) ==
            OdinJuliaBridge.BRIDGE_STATUS_OK
    end
    if run.kind == :math_inline
        return replay_emit_math_block!(state_ptr, run.text; text_style=text_style)
    end
    if run.kind == :shape
        return replay_document_shape!(state_ptr, run, text_style)
    end
    return run.kind == :math_display &&
        replay_document_display_math!(state_ptr, runs, i, text_style)
end

"""Replay parsed document runs into the currently open dynview block."""
function replay_emit_document!(
    state_ptr::Ptr{Cvoid}, runs::Vector{LatexDocumentRun}, text_style::Integer)
    for i in eachindex(runs)
        replay_document_run!(state_ptr, runs, i, text_style) || return false
    end
    return true
end

"""Attempt whole-fragment LaTeX dynview emission and always return the supplied fallback."""
function emit_latex_view_text!(
    state_ptr::Ptr{Cvoid},
    source::AbstractString,
    fallback::AbstractString;
    block_kind::Integer=OdinJuliaBridge.BRIDGE_DYNVIEW_BLOCK_OUTPUT,
    block_id::Integer=1,
    text_style::Integer=OdinJuliaBridge.BRIDGE_DYNVIEW_STYLE_OUTPUT)

    fallback_text = String(fallback)
    mode = classify_latex_mode(source)
    stripped_source = String(strip(source))
    math_source = mode == LATEX_MODE_MATH ?
        something(whole_math_source(stripped_source), stripped_source) : ""
    document_runs = mode == LATEX_MODE_DOCUMENT ?
        parse_latex_document(source) : LatexDocumentRun[]
    if mode == LATEX_MODE_DOCUMENT && document_runs === nothing
        return fallback_text
    end

    OdinJuliaBridge.dynview_reset_stream(state_ptr) == OdinJuliaBridge.BRIDGE_STATUS_OK ||
        return fallback_text
    OdinJuliaBridge.dynview_begin_block(state_ptr, block_kind, block_id) ==
        OdinJuliaBridge.BRIDGE_STATUS_OK || return fallback_text
    OdinJuliaBridge.dynview_copyable_text_run(state_ptr, fallback_text) ==
        OdinJuliaBridge.BRIDGE_STATUS_OK || return fallback_text
    rendered = mode == LATEX_MODE_MATH ?
        replay_emit_math_block!(state_ptr, math_source; text_style=text_style) :
        replay_emit_document!(state_ptr, document_runs, text_style)
    rendered || return fallback_text
    OdinJuliaBridge.dynview_end_block(state_ptr)
    return fallback_text
end

"""Prime document parsing, math compilation, and dynview bridge emission before first display."""
function prime_latex!(state_ptr::Ptr{Cvoid})
    emit_latex_view_text!(state_ptr, LATEX_PRIME_DOCUMENT, LATEX_PRIME_FALLBACK)
    status = OdinJuliaBridge.dynview_reset_stream(state_ptr)
    return status == OdinJuliaBridge.BRIDGE_STATUS_OK
end
