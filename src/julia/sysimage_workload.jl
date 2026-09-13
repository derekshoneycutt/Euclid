include(joinpath(@__DIR__, "sysimage_core.jl"))

"""Exercise stable startup paths without entering the native bridge."""
function exercise_sysimage_workload()
    generation = create_euclid_runtime_generation()
    descriptors = Base.invokelatest(
        getfield, generation.animation_catalog, :AnimationDescriptors)
    AnimationCatalog.validate_catalog(descriptors)
    EuclidLatex.presented_text(LaTeXString(raw"\alpha + \beta"))
    EuclidGeometry.circle_line_intersections_xy(
        Float32[-2, 0, 0], Float32[2, 0, 0],
        Float32[0, 0, 0], 1.0f0)
    EuclidReplEvaluation.complete_input(
        "prin", 4; show_candidates=false, context_module=Main)
    host = create_euclid_runtime_host(Ptr{Cvoid}(1))
    shutdown_euclid_reactor!(host) || error("sysimage workload shutdown failed")
    return nothing
end

exercise_sysimage_workload()