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
    "JULIA-SYNTAX" => Fail,
    "JULIA-CLOSING-PAREN-PLACEMENT" => Fail,
    "JULIA-RETURN-TUPLE" => Fail,
    "ODIN-SYNTAX" => Fail,
    "ODIN-CLOSING-PAREN-PLACEMENT" => Fail,
    "ODIN-RETURN-TUPLE" => Fail)

function euclid_rule_settings()
    return [
        RuleSetting(
            setting.rule_id,
            setting.enabled,
            get(Rule_Responses, setting.rule_id, Report))
        for setting in Base_Settings.rules
    ]
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
        ResponseThresholds(10, 14, 200)),
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