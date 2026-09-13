# Main Julia script body
# This just loads all the system helpers and animation files, and registers in init for Odin

using UUIDs

if !isdefined(Main, :EUCLID_SYSIMAGE_CORE_LOADED)
    using LaTeXStrings

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
end

if !isdefined(Main, :EuclidRuntimeHost)
    include("./runtime_host.jl")
end

if !isdefined(Main, :EUCLID_RUNTIME_API_LOADED)
    include("./runtime_api.jl")
end
