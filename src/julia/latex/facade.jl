"""An unwrapped TeX document whose source is preserved exactly."""
struct TeXDocument
    source::String
end

"""Construct an unwrapped TeX document from any string-like source."""
TeXDocument(source::AbstractString) = TeXDocument(String(source))

"""Write exact document source for Julia's canonical LaTeX MIME."""
function Base.show(io::IO, ::MIME"text/latex", document::TeXDocument)
    print(io, document.source)
end

"""Create a raw, non-interpolating `TeXDocument` literal."""
macro tex_str(source)
    return :(TeXDocument($source))
end

const LATEX_PRIME_DOCUMENT = raw"""\textbf{Euclid} \textit{document} $x_1^2 \in \mathbb{R}$

\euclidpoint[color=steelblue,size=1] \euclidline[color=steelblue,length=3,thickness=2]

$$\frac{a+b}{\sqrt{c}}$$"""

"""Prime canonical TeX serialization without publishing transient content."""
function prime_latex!(state_ptr::Ptr{Cvoid})
    _ = state_ptr
    document = TeXDocument(LATEX_PRIME_DOCUMENT)
    presentation = OdinJuliaBridge.presented_text(document)
    return presentation.mime == OdinJuliaBridge.TextLatex &&
        presentation.bytes == LATEX_PRIME_DOCUMENT
end