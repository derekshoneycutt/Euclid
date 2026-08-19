using OdinJuliaAnalysis

const Repository_Root = normpath(joinpath(@__DIR__, ".."))
const Julia_Project = joinpath(Repository_Root, "src", "julia")
const Analyzer_Root = dirname(dirname(pathof(OdinJuliaAnalysis)))
const Base_Settings = Base.include(
    @__MODULE__, joinpath(Analyzer_Root, "settings.jl"))

Julia_Project in LOAD_PATH || pushfirst!(LOAD_PATH, Julia_Project)

module Euclid_Analysis_Roots

const Julia_Root = normpath(joinpath(@__DIR__, "..", "src", "julia"))

Base.include(@__MODULE__, joinpath(Julia_Root, "odin-julia-bridge.jl"))
Base.include(@__MODULE__, joinpath(Julia_Root, "latex.jl"))

end

const Default_Excludes = [
    "tools/analysis",
    "src/julialib",
    "staging_AnalysisConversion.md",
    "staging_FirstGroups.md",
    "staging_logic.md",
    "staging_SemanticTrace.md",
]
const All_Excludes = [
    "tools/analysis",
    "staging_AnalysisConversion.md",
    "staging_FirstGroups.md",
    "staging_logic.md",
    "staging_SemanticTrace.md",
]

const Rule_Responses = Dict(
    "DUPLICATE-CODE-POLICY-DRIFT" => Fail,
    "FUNCTION-METRIC-POLICY-DRIFT" => Fail,
    "NAMING-POLICY-DRIFT" => Fail,
    "CALL-ROOT-POLICY-DRIFT" => Fail,
    "ODIN-ALLOCATION-POLICY-DRIFT" => Fail,
    "COMMON-LINE-90" => Warn,
    "COMMON-LINE-100" => Warn,
    "COMMON-LINE-120" => Fail,
    "COMMON-NO-TABS" => Fail,
    "JULIA-CYCLOMATIC-WARN" => Warn,
    "JULIA-SYNTAX" => Fail,
    "JULIA-CLOSING-PAREN-PLACEMENT" => Fail,
    "JULIA-RETURN-TUPLE" => Fail,
    "ODIN-CYCLOMATIC-WARN" => Warn,
    "ODIN-SYNTAX" => Fail,
    "ODIN-CLOSING-PAREN-PLACEMENT" => Fail,
    "ODIN-RETURN-TUPLE" => Fail)

const Animation_Loop_Reason =
    "Animation state-machine loops enumerate every construction step in play order."

# Modules whose exported `loop` drives one animation as a flat step sequence.
const Animation_Loop_Files = [
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

# Loops long enough to review for length while still under the branching thresholds.
const Animation_Loop_Linear_Files = [
    "src/julia/elements/book1/def_001_point.jl",
    "src/julia/elements/book1/def_002_line.jl",
]

"""Construct the rule settings to utilize for the analysis and report"""
function euclid_rule_settings()
    return [
        RuleSetting(
            setting.rule_id,
            setting.enabled,
            get(Rule_Responses, setting.rule_id, Report))
        for setting in Base_Settings.rules
    ]
end

"""Return reviewed function metric policies for animation state-machine loops."""
function animation_loop_reviews()
    reviews = ReviewedComplexity[]
    for path in Animation_Loop_Files
        push!(reviews, ReviewedComplexity(
            "animation-loop-lines:$path", path, :julia, "loop", :executable_lines,
            Animation_Loop_Reason; response=Report))
        path in Animation_Loop_Linear_Files && continue
        push!(reviews, ReviewedComplexity(
            "animation-loop-branching:$path", path, :julia, "loop",
            :cyclomatic_complexity, Animation_Loop_Reason; response=Report))
    end
    return reviews
end

AnalysisSettings(
    :default,
    Fail,
    AnalysisThresholds(90, 100, 120, 20, 30, 5, 10, 15, 15),
    [
        ScanProfile(:default, Default_Excludes),
        ScanProfile(:all, All_Excludes),
        ScanProfile(:aspirational, Default_Excludes),
    ],
    euclid_rule_settings(),
    default_naming_settings(),
    JetSettings([
        JetEntryPoint(
            "latex-plain-text",
            "src/julia/latex.jl",
            Euclid_Analysis_Roots.EuclidLatex.latex_to_plain_text,
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
            "scratchpad-repl:save_history", :julia, "create_runtime_module.save_history",
            "the scratchpad REPL evaluates this command from user input"),
        CallRootEntryPoint(
            "scratchpad-repl:quit", :julia, "create_runtime_module.quit",
            "the scratchpad REPL evaluates this command from user input"),
    ]))