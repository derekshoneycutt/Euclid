include(joinpath(@__DIR__, "sysimage_core.jl"))

"""Exercise stable startup paths without entering the native bridge."""
function exercise_sysimage_workload()
    terminal_id = UUID("c4cf618f-86ca-55ba-ac0e-14f31f09940d")
    descriptors = AnimationCatalog.AnimationDescriptor[
        AnimationCatalog.AnimationDescriptor(
            terminal_id, nothing, "Terminal", 0,
            AnimationCatalog.TerminalNode, nothing),
    ]
    AnimationCatalog.validate_catalog(descriptors)
    EuclidLatex.presented_text(LaTeXString(raw"\alpha + \beta"))
    EuclidGeometry.circle_line_intersections_xy(
        Float32[-2, 0, 0], Float32[2, 0, 0],
        Float32[0, 0, 0], 1.0f0)
    EuclidReplEvaluation.complete_input(
        "prin", 4; show_candidates=false, context_module=Main)
    return nothing
end

exercise_sysimage_workload()