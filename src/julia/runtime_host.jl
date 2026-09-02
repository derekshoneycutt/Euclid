"""One independently owned generation of reloadable Euclid content."""
struct EuclidRuntimeGeneration
    content::Module
    animation_catalog::Module
    null_animation::Module
    harness_scenarios::Module
end

"""Julia runtime state owned and rooted by the native Julia worker."""
mutable struct EuclidRuntimeHost
    state_ptr::Ptr{Cvoid}
    active_generation::Union{Nothing,EuclidRuntimeGeneration}
    scratchpad::Scratchpad.ScratchpadRuntimeState
end

"""Create the Julia runtime host whose lifetime is owned by the native worker."""
function create_euclid_runtime_host(state_ptr::Ptr{Cvoid})::EuclidRuntimeHost
    state_ptr == C_NULL && throw(ArgumentError("state_ptr must not be null"))
    scratchpad = Scratchpad.create_runtime_state()
    Scratchpad.create_animation_callback!(scratchpad, state_ptr)
    return EuclidRuntimeHost(state_ptr, create_euclid_runtime_generation(), scratchpad)
end

"""Return whether a native-owned host reference has the expected runtime type."""
function is_euclid_runtime_host(host)::Bool
    return host isa EuclidRuntimeHost
end

"""Create one fresh module that owns all reloadable content for a generation."""
function create_euclid_runtime_generation(
    source_root::AbstractString=@__DIR__)::EuclidRuntimeGeneration

    root = abspath(String(source_root))
    content = Module(gensym(:EuclidRuntimeContent), false, false)
    Core.eval(content, :(const OdinJuliaBridge = $OdinJuliaBridge))
    Core.eval(content, :(const EuclidAnimations = $EuclidAnimations))
    Core.eval(content, :(const EuclidGeometry = $EuclidGeometry))
    Core.eval(content, :(const EuclidLatex = $EuclidLatex))
    Base.include(content, joinpath(root, "animation_catalog.jl"))
    Base.include(content, joinpath(root, "nullanimation.jl"))
    Base.include(content, joinpath(root, "harness_scenarios.jl"))
    return EuclidRuntimeGeneration(
        content,
        Base.invokelatest(getfield, content, :AnimationCatalog),
        Base.invokelatest(getfield, content, :NullAnimation),
        Base.invokelatest(getfield, content, :EuclidHarnessScenarios))
end

"""Load one animation into the content module owned by a generation."""
function load_generation_animation(
    generation::EuclidRuntimeGeneration, id)::Any

    loader = getfield(generation.animation_catalog, :ensure_animation_loaded)
    return Base.invokelatest(loader, generation.content, id)
end

"""Return the committed generation owned by a valid runtime host."""
function active_euclid_runtime_generation(
    host::EuclidRuntimeHost)::EuclidRuntimeGeneration

    generation = host.active_generation
    generation === nothing && error("Euclid runtime host has no active generation")
    return generation
end

"""Commit one validated generation as the host's sole active content owner."""
function commit_euclid_runtime_generation(
    host::EuclidRuntimeHost,
    generation::EuclidRuntimeGeneration)::Bool

    host.active_generation = generation
    return true
end