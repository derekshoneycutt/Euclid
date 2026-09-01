"""
Parse supported LaTeX into deterministic dynview programs and plain-text fallbacks.

EuclidLatex owns tokenization, recursive parsing, normalization, and compilation. Rendering
remains host-owned and is reached through the Odin-Julia bridge.
"""
module EuclidLatex

using ..OdinJuliaBridge

export PARSER_GRAMMAR_VERSION,
    parse_latex,
    compile_emit_program,
    replay_emit_program!,
    replay_emit_math_block!,
    emit_latex_dynview!,
    classify_latex_mode,
    emit_latex_view_text!,
    prime_latex!,
    latex_to_plain_text,
    compiled_program_for

include("latex/core.jl")
include("latex/lexer_parser.jl")
include("latex/compiler.jl")
include("latex/document_mode.jl")
include("latex/dynview_math.jl")

end
