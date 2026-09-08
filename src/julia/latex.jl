"""
Provide stable Julia authoring facades for Dynview's native TeX implementation.

Dynview owns tokenization, parsing, normalization, semantic compilation, and rendering.
"""
module EuclidLatex

using ..OdinJuliaBridge

export TeXDocument,
    @tex_str,
    prime_latex!

include("latex/facade.jl")

end
