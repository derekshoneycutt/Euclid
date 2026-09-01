include(joinpath(@__DIR__, "sysimage_core.jl"))

const LatexSamples = (
    raw"$x_1^2 \in \mathbb{R}$",
    raw"$\frac{x^2}{\sqrt{y}}$",
    raw"$\left(\sum_{i=1}^{n} a_i\right)$",
    raw"$\begin{bmatrix}a & b \\ c & d\end{bmatrix}$")

for source in LatexSamples
    EuclidLatex.latex_to_plain_text(source)
end

EuclidLatex.parse_latex_document(
    raw"\textbf{Euclid} document $x_1^2$ \newline \euclidline[color=steelblue]{4}{2}")

Scratchpad.classify_parse("sum(1:3)")
Scratchpad.classify_parse("begin\n    value = 1")
Scratchpad.longest_completion_prefix(["EuclidGeometry", "EuclidAnimations"])

let session = Scratchpad.create_session(Ptr{Cvoid}(0), -1)
    Scratchpad.ScratchpadRuntime.current_session = session
    Scratchpad.queue_input(Ptr{Cvoid}(0), "sum(1:3)")
    Scratchpad.complete_backslash(Ptr{Cvoid}(0), "\\alpha")
    Scratchpad.complete_input(Ptr{Cvoid}(0), "EuclidRep", 9)
    Scratchpad.loop(Ptr{Cvoid}(0), 0f0)
    Scratchpad.ScratchpadRuntime.current_session = nothing
end