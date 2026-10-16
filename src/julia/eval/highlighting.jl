"""Julia 1.13 face resolution isolated from native transport and display ownership."""
module SyntaxHighlighting

import JuliaSyntaxHighlighting
import StyledStrings

const MAX_SOURCE_BYTES = 64 * 1024
const MAX_STYLE_RUNS = 4096
const MAX_ANNOTATIONS = 16 * 1024
const MAX_FACE_DEPTH = 32
const MAX_FACE_VISITS = 256

"""Native color interpretation; ANSI indices remain display-palette references."""
@enum ColorKind::UInt8 DefaultColor AnsiColor RgbColor

"""A default color, ANSI index 0-15, or packed 24-bit RGB value."""
struct HighlightColor
    kind::ColorKind
    value::UInt32
end

"""Native font weight; unsupported Julia weights use normal prompt weight."""
@enum HighlightWeight::UInt8 NormalWeight BoldWeight DimWeight

"""Underline vocabulary retained independently of native renderer capabilities."""
@enum UnderlineKind::UInt8 begin
    NoUnderline
    StraightUnderline
    DoubleUnderline
    CurlyUnderline
    DottedUnderline
    DashedUnderline
end

"""Resolved source appearance without references to Julia face or annotation objects."""
struct HighlightStyle
    foreground::HighlightColor
    background::HighlightColor
    weight::HighlightWeight
    italic::Bool
    underline::UnderlineKind
    underline_color::HighlightColor
    strikethrough::Bool
    inverse::Bool
end

"""One nonempty source-relative, zero-based, half-open UTF-8 byte interval."""
struct HighlightRun
    start_byte::UInt32
    end_byte::UInt32
    style::HighlightStyle
end

const DEFAULT_COLOR = HighlightColor(DefaultColor, UInt32(0))
const ANSI_COLORS = (
    :black, :red, :green, :yellow, :blue, :magenta, :cyan, :white,
    :bright_black, :bright_red, :bright_green, :bright_yellow,
    :bright_blue, :bright_magenta, :bright_cyan, :bright_white)
const UNDERLINE_STYLES = (
    :straight, :double, :curly, :dotted, :dashed)

"""Reject invalid UTF-8 or oversized source before parsing or normalizing annotations."""
function validate_source(source::AbstractString)
    ncodeunits(source) <= MAX_SOURCE_BYTES ||
        throw(ArgumentError("syntax highlighting source exceeds $MAX_SOURCE_BYTES bytes"))
    isvalid(source) || throw(ArgumentError("syntax highlighting requires valid UTF-8"))
    return nothing
end

"""Check bounded face inheritance before entering Julia's recursive face merger."""
function validate_face(value, path::Tuple=(), visits::Base.RefValue{Int}=Ref(0))
    visits[] += 1
    visits[] <= MAX_FACE_VISITS && length(path) < MAX_FACE_DEPTH ||
        throw(ArgumentError("syntax highlighting face inheritance exceeds its bound"))
    if value isa Symbol
        value in path &&
            throw(ArgumentError("cyclic syntax highlighting face inheritance"))
        face = get(StyledStrings.FACES.current[], value, nothing)
        isnothing(face) || validate_face(face, (path..., value), visits)
    elseif value isa StyledStrings.Face
        for parent in value.inherit
            validate_face(parent, path, visits)
        end
    elseif value isa Vector
        for face in value
            validate_face(face, path, visits)
        end
    else
        throw(ArgumentError("unsupported syntax highlighting face value"))
    end
    return nothing
end

"""Resolve configured color aliases without terminal-dependent RGB quantization."""
function resolve_color(color, path::Tuple=())::HighlightColor
    isnothing(color) && return DEFAULT_COLOR
    value = color.value
    if value isa NamedTuple
        rgb = UInt32(value.r) << 16 | UInt32(value.g) << 8 | UInt32(value.b)
        return HighlightColor(RgbColor, rgb)
    end
    value === :default && return DEFAULT_COLOR
    value in path && throw(ArgumentError("cyclic syntax highlighting color alias"))
    length(path) < MAX_FACE_DEPTH ||
        throw(ArgumentError("syntax highlighting color aliases exceed their bound"))
    validate_face(value)
    resolved = StyledStrings.getface(value).foreground
    if resolved != color
        return resolve_color(resolved, (path..., value))
    end
    name = value in (:grey, :gray) ? :bright_black : value
    index = findfirst(==(name), ANSI_COLORS)
    return isnothing(index) ? DEFAULT_COLOR : HighlightColor(AnsiColor, UInt32(index - 1))
end

"""Normalize Julia underline color/style variants, defaulting unsupported styles to none."""
function resolve_underline(underline)
    underline === true && return (StraightUnderline, DEFAULT_COLOR)
    underline isa Union{Nothing,Bool} && return (NoUnderline, DEFAULT_COLOR)
    underline isa StyledStrings.SimpleColor &&
        return (StraightUnderline, resolve_color(underline))
    color, name = underline
    index = findfirst(==(name), UNDERLINE_STYLES)
    kind = isnothing(index) ? NoUnderline : UnderlineKind(index)
    return (kind, resolve_color(color))
end

"""Merge overlapping faces with Julia precedence and lower supported native attributes."""
function resolve_style(annotations)::HighlightStyle
    for annotation in annotations
        annotation.label === :face && validate_face(annotation.value)
    end
    face = StyledStrings.getface(annotations)
    weight = if face.weight in (:medium, :semibold, :bold, :extrabold, :black)
        BoldWeight
    elseif face.weight in (:semilight, :light, :extralight, :thin)
        DimWeight
    else
        NormalWeight
    end
    underline, underline_color = resolve_underline(face.underline)
    return HighlightStyle(
        resolve_color(face.foreground), resolve_color(face.background),
        weight, face.slant in (:italic, :oblique), underline, underline_color,
        face.strikethrough === true, face.inverse === true)
end

"""Reject excessive annotations or ranges that split UTF-8 characters before region iteration."""
function validate_annotations(source::StyledStrings.AnnotatedString)
    annotations = Base.annotations(source)
    length(annotations) <= MAX_ANNOTATIONS ||
        throw(ArgumentError("syntax highlighting annotations exceed $MAX_ANNOTATIONS"))
    stop = ncodeunits(source) + 1
    for annotation in annotations
        start_byte, end_byte = first(annotation.region), last(annotation.region) + 1
        1 <= start_byte < end_byte <= stop ||
            throw(ArgumentError("syntax highlighting annotation is outside source"))
        isvalid(source, start_byte) && (end_byte == stop || isvalid(source, end_byte)) ||
            throw(ArgumentError("syntax highlighting annotation splits UTF-8"))
    end
    return nothing
end

"""
Normalize Julia annotations into complete, merged source coverage, including plain gaps.
The caller owns the returned bounded vector. Invalid data or capacity exhaustion throws;
no truncated or success-shaped fallback is returned. Julia 1.13 internals stay in this adapter.
"""
function normalize_runs(source::StyledStrings.AnnotatedString)::Vector{HighlightRun}
    validate_source(source)
    validate_annotations(source)
    StyledStrings.load_customisations!()
    runs = HighlightRun[]
    offset = UInt32(0)
    for (text, annotations) in Base.eachregion(source)
        isempty(text) && continue
        stop = offset + UInt32(ncodeunits(text))
        style = resolve_style(annotations)
        if !isempty(runs) && last(runs).style == style
            runs[end] = HighlightRun(last(runs).start_byte, stop, style)
        else
            length(runs) < MAX_STYLE_RUNS ||
                throw(ArgumentError("syntax highlighting runs exceed $MAX_STYLE_RUNS"))
            push!(runs, HighlightRun(offset, stop, style))
        end
        offset = stop
    end
    offset == ncodeunits(source) ||
        throw(ArgumentError("syntax highlighting regions do not cover source"))
    return runs
end

"""
Highlight bounded Julia source, including incomplete/error input, using current configured faces.
Standard faces.toml/environment customization loads lazily, not during sysimage construction.
Only source-derived values are returned; evaluation, prompt state, and output are untouched.
"""
function highlight_source(source::AbstractString)::Vector{HighlightRun}
    validate_source(source)
    annotated = JuliaSyntaxHighlighting.highlight(String(source); syntax_errors=true)
    return normalize_runs(annotated)
end

end
