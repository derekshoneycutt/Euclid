using LaTeXStrings
using Latexify

include("./odin-julia-bridge.jl")
include("./latex.jl")
include("./geometry.jl")
include("./animations.jl")
include("./animation_catalog.jl")
include("./runtime.jl")
include("./terminal.jl")
include("./ticks.jl")
include("./euclidrepl.jl")
include("./terminal_container.jl")
include("./eval.jl")
include("./interpolation.jl")
include("./policy.jl")
include("./host.jl")
include("./runtime_host.jl")
include("./runtime_api.jl")

const EUCLID_SYSIMAGE_CORE_LOADED = true