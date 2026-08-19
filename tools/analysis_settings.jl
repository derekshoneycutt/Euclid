using OdinJuliaAnalysis

const RepositoryRoot = normpath(joinpath(@__DIR__, ".."))
const JuliaProject = joinpath(RepositoryRoot, "src", "julia")
const AnalyzerRoot = dirname(dirname(pathof(OdinJuliaAnalysis)))
const BaseSettings = Base.include(
    @__MODULE__, joinpath(AnalyzerRoot, "settings.jl"))

JuliaProject in LOAD_PATH || pushfirst!(LOAD_PATH, JuliaProject)

module EuclidAnalysisRoots

const JuliaRoot = normpath(joinpath(@__DIR__, "..", "src", "julia"))

Base.include(@__MODULE__, joinpath(JuliaRoot, "odin-julia-bridge.jl"))
Base.include(@__MODULE__, joinpath(JuliaRoot, "latex.jl"))

end

const DefaultExcludes = [
    "tools/analysis",
    "src/julialib",
]
const AllExcludes = [
    "tools/analysis",
]

const RuleResponses = Dict(
    "DUPLICATE-CODE-POLICY-DRIFT" => Fail,
    "FUNCTION-METRIC-POLICY-DRIFT" => Fail,
    "NAMING-POLICY-DRIFT" => Fail,
    "CALL-ROOT-POLICY-DRIFT" => Fail,
    "ODIN-ALLOCATION-POLICY-DRIFT" => Fail,
    "COMMON-LINE-90" => Warn,
    "COMMON-LINE-100" => Warn,
    "COMMON-LINE-120" => Fail,
    "COMMON-NO-TABS" => Fail,
    "JULIA-SYNTAX" => Fail,
    "JULIA-CLOSING-PAREN-PLACEMENT" => Fail,
    "JULIA-JET-POSSIBLE-ERROR" => Fail,
    "JULIA-NAMING" => Warn,
    "JULIA-NONCONST-GLOBAL" => Warn,
    "JULIA-DECLARATION-ORDER" => Warn,
    "JULIA-RETURN-TUPLE" => Fail,
    "JULIA-PARAMETERS-FAIL" => Fail,
    "JULIA-FUNCTION-LINES-WARN" => Warn,
    "JULIA-FUNCTION-LINES-FAIL" => Fail,
    "JULIA-CYCLOMATIC-WARN" => Warn,
    "JULIA-CYCLOMATIC-FAIL" => Fail,
    "ODIN-SYNTAX" => Fail,
    "ODIN-BUILD-FAILED" => Fail,
    "ODIN-CLOSING-PAREN-PLACEMENT" => Fail,
    "ODIN-NAMING" => Warn,
    "ODIN-NONCONST-GLOBAL" => Warn,
    "ODIN-DECLARATION-ORDER" => Warn,
    "ODIN-RETURN-TUPLE" => Fail,
    "ODIN-PARAMETERS-WARN" => Warn,
    "ODIN-PARAMETERS-FAIL" => Fail,
    "ODIN-FUNCTION-LINES-WARN" => Warn,
    "ODIN-FUNCTION-LINES-FAIL" => Fail,
    "ODIN-CYCLOMATIC-WARN" => Warn,
    "ODIN-CYCLOMATIC-FAIL" => Fail,
    "JULIA-DOC-MISSING" => Fail,
    "ODIN-DOC-MISSING" => Fail)

const AnimationLoopReason =
    "Animation state-machine loops enumerate every construction step in play order."

# Modules whose exported `loop` drives one animation as a flat step sequence.
const AnimationLoopFiles = [
    "src/julia/algebra/groups/C_n.jl",
    "src/julia/algebra/groups/C_n_abelian.jl",
    "src/julia/algebra/groups/C_n_associative.jl",
    "src/julia/algebra/groups/z_2.jl",
    "src/julia/algebra/groups/z_2_closure.jl",
    "src/julia/algebra/groups/z_2_identity.jl",
    "src/julia/algebra/groups/z_2_inverse.jl",
    "src/julia/elements/book1/commonnotions.jl",
    "src/julia/elements/book1/def_001_point.jl",
    "src/julia/elements/book1/def_002_line.jl",
    "src/julia/elements/book1/def_003_linextrem.jl",
    "src/julia/elements/book1/def_004_straightline.jl",
    "src/julia/elements/book1/def_005_surface.jl",
    "src/julia/elements/book1/def_006_surfextrem.jl",
    "src/julia/elements/book1/def_007_planesurface.jl",
    "src/julia/elements/book1/def_008_angle.jl",
    "src/julia/elements/book1/def_010_perpendicular.jl",
    "src/julia/elements/book1/def_011_obtuseangle.jl",
    "src/julia/elements/book1/def_012_acuteangle.jl",
    "src/julia/elements/book1/def_013_boundary.jl",
    "src/julia/elements/book1/def_014_figure.jl",
    "src/julia/elements/book1/def_015_circle.jl",
    "src/julia/elements/book1/def_017_diameter.jl",
    "src/julia/elements/book1/def_018_semicircle.jl",
    "src/julia/elements/book1/def_019a_trilateral.jl",
    "src/julia/elements/book1/def_019b_quadrilateral.jl",
    "src/julia/elements/book1/def_019c_multilateral.jl",
    "src/julia/elements/book1/def_020a_equilateral.jl",
    "src/julia/elements/book1/def_020b_isosceles.jl",
    "src/julia/elements/book1/def_020c_scalene.jl",
    "src/julia/elements/book1/def_021a_righttriangle.jl",
    "src/julia/elements/book1/def_021b_obtusetriangle.jl",
    "src/julia/elements/book1/def_021c_acutetriangle.jl",
    "src/julia/elements/book1/def_022a_square.jl",
    "src/julia/elements/book1/def_022b_oblong.jl",
    "src/julia/elements/book1/def_022c_rhombus.jl",
    "src/julia/elements/book1/def_022d_rhomboid.jl",
    "src/julia/elements/book1/def_022d_trapezia.jl",
    "src/julia/elements/book1/def_023_parallel.jl",
    "src/julia/elements/book1/post_01_drawline.jl",
    "src/julia/elements/book1/post_02_finiteline.jl",
    "src/julia/elements/book1/post_03_drawcircle.jl",
    "src/julia/elements/book1/post_04_equalright.jl",
    "src/julia/elements/book1/post_05_nonparallel.jl",
    "src/julia/elements/book1/prop_01.jl",
    "src/julia/hilbert/1.fivegroupsaxioms/axiom_I1.jl",
    "src/julia/hilbert/1.fivegroupsaxioms/axiom_I2.jl",
    "src/julia/hilbert/1.fivegroupsaxioms/axiom_I3.jl",
    "src/julia/hilbert/1.fivegroupsaxioms/axiom_I4.jl",
    "src/julia/hilbert/1.fivegroupsaxioms/axiom_I5.jl",
    "src/julia/hilbert/1.fivegroupsaxioms/axiom_I6.jl",
    "src/julia/hilbert/1.fivegroupsaxioms/axiom_I7.jl",
    "src/julia/hilbert/1.fivegroupsaxioms/axiom_II1.jl",
    "src/julia/hilbert/1.fivegroupsaxioms/axiom_II2.jl",
    "src/julia/hilbert/1.fivegroupsaxioms/axiom_II3.jl",
    "src/julia/hilbert/1.fivegroupsaxioms/axiom_II4.jl",
    "src/julia/hilbert/1.fivegroupsaxioms/axiom_II5.jl",
    "src/julia/hilbert/1.fivegroupsaxioms/axiom_III1.jl",
    "src/julia/hilbert/1.fivegroupsaxioms/axiom_IV1.jl",
    "src/julia/hilbert/1.fivegroupsaxioms/axiom_IV2.jl",
    "src/julia/hilbert/1.fivegroupsaxioms/axiom_IV3.jl",
    "src/julia/hilbert/1.fivegroupsaxioms/axiom_IV4.jl",
    "src/julia/hilbert/1.fivegroupsaxioms/axiom_IV5.jl",
    "src/julia/hilbert/1.fivegroupsaxioms/axiom_IV6.jl",
    "src/julia/hilbert/1.fivegroupsaxioms/axiom_V.jl",
    "src/julia/hilbert/1.fivegroupsaxioms/axiom_completeness.jl",
    "src/julia/hilbert/1.fivegroupsaxioms/def_angle.jl",
    "src/julia/hilbert/1.fivegroupsaxioms/def_circle.jl",
    "src/julia/hilbert/1.fivegroupsaxioms/def_congruent_angles.jl",
    "src/julia/hilbert/1.fivegroupsaxioms/def_congruent_triangles.jl",
    "src/julia/hilbert/1.fivegroupsaxioms/def_figure.jl",
    "src/julia/hilbert/1.fivegroupsaxioms/def_halfrays.jl",
    "src/julia/hilbert/1.fivegroupsaxioms/def_polygon.jl",
    "src/julia/hilbert/1.fivegroupsaxioms/def_segments.jl",
    "src/julia/hilbert/1.fivegroupsaxioms/def_sideofline.jl",
    "src/julia/hilbert/1.fivegroupsaxioms/def_supplementary_angles.jl",
    "src/julia/hilbert/1.fivegroupsaxioms/def_triangle_angle.jl",
    "src/julia/hilbert/1.fivegroupsaxioms/theorem_1.jl",
    "src/julia/hilbert/1.fivegroupsaxioms/theorem_10.jl",
    "src/julia/hilbert/1.fivegroupsaxioms/theorem_11.jl",
    "src/julia/hilbert/1.fivegroupsaxioms/theorem_12.jl",
    "src/julia/hilbert/1.fivegroupsaxioms/theorem_13.jl",
    "src/julia/hilbert/1.fivegroupsaxioms/theorem_14.jl",
    "src/julia/hilbert/1.fivegroupsaxioms/theorem_15.jl",
    "src/julia/hilbert/1.fivegroupsaxioms/theorem_16.jl",
    "src/julia/hilbert/1.fivegroupsaxioms/theorem_17.jl",
    "src/julia/hilbert/1.fivegroupsaxioms/theorem_18.jl",
    "src/julia/hilbert/1.fivegroupsaxioms/theorem_19.jl",
    "src/julia/hilbert/1.fivegroupsaxioms/theorem_2.jl",
    "src/julia/hilbert/1.fivegroupsaxioms/theorem_20.jl",
    "src/julia/hilbert/1.fivegroupsaxioms/theorem_3.jl",
    "src/julia/hilbert/1.fivegroupsaxioms/theorem_4.jl",
    "src/julia/hilbert/1.fivegroupsaxioms/theorem_5.jl",
    "src/julia/hilbert/1.fivegroupsaxioms/theorem_6.jl",
    "src/julia/hilbert/1.fivegroupsaxioms/theorem_7.jl",
    "src/julia/hilbert/1.fivegroupsaxioms/theorem_8.jl",
    "src/julia/hilbert/1.fivegroupsaxioms/theorem_9.jl",
    "src/julia/proclus/proclus_01_isosceles.jl",
    "src/julia/proclus/proclus_02_scalene.jl",
]

"""Construct the rule settings to utilize for the analysis and report"""
function euclid_rule_settings()
    return [
        RuleSetting(
            setting.rule_id,
            setting.enabled,
            get(RuleResponses, setting.rule_id, Report))
        for setting in BaseSettings.rules
    ]
end

"""Return naming settings that permit Julia constructors to match their type names."""
function euclid_naming_settings()
    conventions = [
        convention.language == :julia && convention.kind == :function ?
            NamingConvention(
                :julia, :function, convention.casing;
                allow_leading_underscore=convention.allow_leading_underscore,
                allow_trailing_bang=convention.allow_trailing_bang,
                allow_constructor_names=true) :
            convention
        for convention in default_naming_settings().conventions
    ]
    return NamingSettings(conventions)
end

"""Add the parent animation reviews that are good to ignore to the reviews list"""
function add_parent_reviews!(reviews)
    path = "src/julia/algebra/groups/groups.jl"
    push!(reviews, ReviewedComplexity(
        "groups-init-euclid-scripts-lines:$path", path, :julia,
        "init_euclid_scripts", :executable_lines, AnimationLoopReason;
        response=Ignore, minimum_matches=0))
    path = "src/julia/elements/book1/book1.jl"
    push!(reviews, ReviewedComplexity(
        "euclidbook1-init-euclid-scripts-lines:$path", path, :julia,
        "init_euclid_scripts", :executable_lines, AnimationLoopReason;
        response=Ignore, minimum_matches=0))
    path = "src/julia/hilbert/1.fivegroupsaxioms/fivegroupsaxioms.jl"
    push!(reviews, ReviewedComplexity(
        "hilbert1-init-euclid-scripts-lines:$path", path, :julia,
        "init_euclid_scripts", :executable_lines, AnimationLoopReason;
        response=Ignore, minimum_matches=0))
    path = "src/julia/nullanimation.jl"
    push!(reviews, ReviewedComplexity(
        "nullanimation-initialize-lines:$path", path, :julia,
        "initialize", :executable_lines, AnimationLoopReason;
        response=Ignore, minimum_matches=0))
    push!(reviews, ReviewedComplexity(
        "nullanimation-draw-line-lines:$path", path, :julia,
        "draw_line", :executable_lines, AnimationLoopReason;
        response=Ignore, minimum_matches=0))
    reviews
end

"""Return reviewed function metric policies for animation state-machine loops."""
function animation_loop_reviews()
    reviews = ReviewedComplexity[]
    for path in AnimationLoopFiles
        push!(reviews, ReviewedComplexity(
            "animation-loop-lines:$path", path, :julia, "loop", :executable_lines,
            AnimationLoopReason; response=Ignore, minimum_matches=0))
        push!(reviews, ReviewedComplexity(
            "animation-loop-branching:$path", path, :julia, "loop",
            :cyclomatic_complexity, AnimationLoopReason;
            response=Ignore, minimum_matches=0))
        push!(reviews, ReviewedComplexity(
            "animation-get-view-text-lines:$path", path, :julia, "get_view_text",
            :executable_lines, AnimationLoopReason;
            response=Ignore, minimum_matches=0))
        push!(reviews, ReviewedComplexity(
            "animation-get-view-text-branching:$path", path, :julia, "get_view_text",
            :cyclomatic_complexity, AnimationLoopReason;
            response=Ignore, minimum_matches=0))
        push!(reviews, ReviewedComplexity(
            "animation-initialize-lines:$path", path, :julia, "initialize",
            :executable_lines, AnimationLoopReason;
            response=Ignore, minimum_matches=0))
        push!(reviews, ReviewedComplexity(
            "animation-initialize-branching:$path", path, :julia, "initialize",
            :cyclomatic_complexity, AnimationLoopReason;
            response=Ignore, minimum_matches=0))
        push!(reviews, ReviewedComplexity(
            "animation-reset-cycle-state-lines:$path", path, :julia, "reset_cycle_state",
            :executable_lines, AnimationLoopReason;
            response=Ignore, minimum_matches=0))
        push!(reviews, ReviewedComplexity(
            "animation-reset-cycle-state-branching:$path", path, :julia,
            "reset_cycle_state", :cyclomatic_complexity, AnimationLoopReason;
            response=Ignore, minimum_matches=0))
    end
    add_parent_reviews!(reviews)
end

AnalysisSettings(
    :default,
    Fail,
    AnalysisThresholds(90, 100, 120, 20, 30, 5, 10, 15, 15),
    [
        ScanProfile(:default, DefaultExcludes),
        ScanProfile(:all, AllExcludes),
        ScanProfile(:aspirational, DefaultExcludes),
    ],
    euclid_rule_settings(),
    euclid_naming_settings(),
    JetSettings([
        JetEntryPoint(
            "latex-plain-text",
            "src/julia/latex.jl",
            EuclidAnalysisRoots.EuclidLatex.latex_to_plain_text,
            (String,)),
    ]),
    OdinBuildSettings(OdinBuildTarget[]),
    ReturnTupleSettings(2, 2),
    ParameterCountSettings(8, 5, 8),
    FunctionMetricSettings(
        ResponseThresholds(35, 45, 65),
        ResponseThresholds(35, 45, 65),
        ResponseThresholds(10, 14, 200),
        ResponseThresholds(10, 15, 200),
        animation_loop_reviews()),
    default_architecture_settings(),
    AllocationSettings(
        KnownAllocatingProcedure[],
        [
            AllocatorSourcePattern("context.temp_allocator", :temporary),
            AllocatorSourcePattern("context.allocator", :context),
            AllocatorSourcePattern("heap.allocator()", :heap),
        ],
        ReviewedAllocationPolicy[]),
    ReportSettings(:auto, 100, 100),
    AnalysisExtension[],
    default_duplicate_code_settings(),
    default_resource_lifetime_settings(),
    default_security_settings(),
    default_coverage_settings(),
    default_documentation_settings(),
    CallRootSettings([
        CallRootEntryPoint(
            "odin-bridge:init_euclid_scripts", :julia, "init_euclid_scripts",
            "src/bridge/bootstrap.odin resolves this symbol through jl_get_function"),
        CallRootEntryPoint(
            "odin-bridge:global_euclid_loop", :julia, "global_euclid_loop",
            "src/bridge/bootstrap.odin resolves this symbol through jl_get_function"),
        CallRootEntryPoint(
            "odin-bridge:scratchpad_classify_input", :julia,
            "scratchpad_classify_input",
            "src/bridge/bootstrap.odin resolves this symbol through jl_get_function"),
        CallRootEntryPoint(
            "odin-bridge:scratchpad_complete_backslash", :julia,
            "scratchpad_complete_backslash",
            "src/bridge/bootstrap.odin resolves this symbol through jl_get_function"),
        CallRootEntryPoint(
            "odin-bridge:scratchpad_complete_input", :julia,
            "scratchpad_complete_input",
            "src/bridge/bootstrap.odin resolves this symbol through jl_get_function"),
        CallRootEntryPoint(
            "odin-bridge:scratchpad_queue_input", :julia, "scratchpad_queue_input",
            "src/bridge/bootstrap.odin resolves this symbol through jl_get_function"),
        CallRootEntryPoint(
            "odin-bridge:scratchpad_save_history_to_file", :julia,
            "scratchpad_save_history_to_file",
            "src/bridge/bootstrap.odin resolves this symbol through jl_get_function"),
        CallRootEntryPoint(
            "odin-bridge:scratchpad_history_previous", :julia,
            "scratchpad_history_previous",
            "src/bridge/bootstrap.odin resolves this symbol through jl_get_function"),
        CallRootEntryPoint(
            "odin-bridge:scratchpad_history_next", :julia, "scratchpad_history_next",
            "src/bridge/bootstrap.odin resolves this symbol through jl_get_function"),
        CallRootEntryPoint(
            "odin-bridge:scratchpad_history_reset_cursor", :julia,
            "scratchpad_history_reset_cursor",
            "src/bridge/bootstrap.odin resolves this symbol through jl_get_function"),
        CallRootEntryPoint(
            "scratchpad-repl:save_history", :julia, "install_hook_helpers!.save_history",
            "the scratchpad REPL evaluates this command from user input"),
        CallRootEntryPoint(
            "scratchpad-repl:quit", :julia, "install_hook_helpers!.quit",
            "the scratchpad REPL evaluates this command from user input"),
    ]))