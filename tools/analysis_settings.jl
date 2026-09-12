using OdinJuliaAnalysis

Base.include(@__MODULE__, joinpath(@__DIR__, "build_config.jl"))
using .EuclidBuildConfiguration: native_linker_flags

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
    "IMPORT-POLICY-DRIFT" => Fail,
    "COMMON-LINE-90" => Warn,
    "COMMON-LINE-100" => Warn,
    "COMMON-LINE-120" => Fail,
    "COMMON-NO-TABS" => Fail,
    "JULIA-BROAD-CATCH" => Warn,
    "JULIA-SYNTAX" => Fail,
    "JULIA-CLOSING-PAREN-PLACEMENT" => Fail,
    "JULIA-JET-POSSIBLE-ERROR" => Fail,
    "JULIA-NAMING" => Warn,
    "JULIA-NONCONST-GLOBAL" => Warn,
    "JULIA-DECLARATION-ORDER" => Warn,
    "JULIA-RETURN-TUPLE" => Fail,
    "JULIA-PARAMETERS-FAIL" => Fail,
    "JULIA-FUNCTION-LINES-REPORT" => Warn,
    "JULIA-FUNCTION-LINES-WARN" => Fail,
    "JULIA-FUNCTION-LINES-FAIL" => Fail,
    "JULIA-CYCLOMATIC-REPORT" => Warn,
    "JULIA-CYCLOMATIC-WARN" => Fail,
    "JULIA-CYCLOMATIC-FAIL" => Fail,
    "ODIN-SYNTAX" => Fail,
    "ODIN-BUILD-FAILED" => Fail,
    "ODIN-CLOSING-PAREN-PLACEMENT" => Fail,
    "ODIN-NAMING" => Warn,
    "ODIN-NONCONST-GLOBAL" => Warn,
    "ODIN-DECLARATION-ORDER" => Fail,
    "ODIN-RETURN-TUPLE" => Fail,
    "ODIN-PARAMETERS-WARN" => Warn,
    "ODIN-PARAMETERS-FAIL" => Fail,
    "ODIN-FUNCTION-LINES-REPORT" => Warn,
    "ODIN-FUNCTION-LINES-WARN" => Fail,
    "ODIN-FUNCTION-LINES-FAIL" => Fail,
    "ODIN-CYCLOMATIC-REPORT" => Warn,
    "ODIN-CYCLOMATIC-WARN" => Fail,
    "ODIN-CYCLOMATIC-FAIL" => Fail,
    "ODIN-ALLOCATION-IMPLICIT" => Fail,
    "ODIN-ALLOCATION-UNKNOWN" => Fail,
    "ODIN-ALLOCATION-CONTEXT" => Warn,
    "ODIN-ALLOCATION-HEAP" => Warn,
    "ODIN-ALLOCATION-ARENA" => Warn,
    "ODIN-ALLOCATION-HIDDEN" => Warn,
    "ODIN-ALLOCATION-POLICY-DRIFT" => Fail,
    "REVIEWED-DIAGNOSTIC-POLICY-DRIFT" => Fail,
    "JULIA-DOC-MISSING" => Fail,
    "ODIN-DOC-MISSING" => Fail)

const AnimationLoopReason =
    "Animation state-machine loops enumerate every construction step in play order."

# Columns: id, path, procedure, operation, target, minimum, maximum, reason.
const CustomTestAllocationReviews = [
    ("test-core-arena-owner-growth-buffer", "src/core/arena_owner_test.odin",
        "core_test_arena_owner_reset_releases_growth_blocks", "make", "[]u8", 1, 1,
        "Arena-backed test payload is invalidated by reset and released by destroy."),
    ("test-core-arena-owner-destroy-buffer", "src/core/arena_owner_test.odin",
        "core_test_arena_owner_destroy_preserves_diagnostics", "make", "[]u8", 1, 1,
        "Arena-backed test payload is released by the owner destruction under test."),
    ("test-evidence-allocation-baseline-buffer",
        "src/evidence/allocation/allocation_test.odin",
        "allocation_test_baseline_restoration", "make", "[]byte", 1, 1,
        "Bounded test allocation is deleted before the tracked domain is destroyed."),
    ("test-view-font-preparation-arena-pages", "src/view/font/font_test.odin",
        "view_test_preparation_arena_reuses_committed_pages", "make", "[]u8", 2, 2,
        "Bounded buffers verify preparation-arena reuse before explicit destruction.")]

"""Build reviewed records for custom-allocator test fixtures."""
function custom_test_allocation_reviews()
    return [ReviewedAllocationPolicy(
        id, path, procedure, :custom, reason;
        operation=operation,
        target=target,
        allocator_source="allocator",
        certainty=:definite,
        response=Ignore,
        minimum_matches=minimum,
        maximum_matches=maximum)
        for (id, path, procedure, operation, target, minimum, maximum, reason) in
            CustomTestAllocationReviews]
end

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

"""Add reviewed animation complexity exceptions to the reviews list."""
function add_animation_reviews!(reviews)
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

"""Add the reviewed metric policy for the failure-test allocators."""
function add_builder_test_allocation_procs!(reviews)
    push!(reviews, ReviewedComplexity(
        "test-bounded-builder-allocator-parameters",
        "src/core/bounded_builder_test.odin",
        :odin,
        "bounded_builder_test_allocator_proc",
        :parameters,
        "The test allocator implements the required seven-parameter allocator ABI.";
        response=Ignore))
    push!(reviews, ReviewedComplexity(
        "test-shaped-builder-allocator-parameters",
        "src/dynview/math/storage_test.odin",
        :odin,
        "shaped_builder_test_allocator_proc",
        :parameters,
        "The test allocator implements the required seven-parameter allocator ABI.";
        response=Ignore))
    push!(reviews, ReviewedComplexity(
        "test-document-store-allocator-parameters",
        "src/dynview/core/document_store_test.odin",
        :odin,
        "document_store_test_allocator_proc",
        :parameters,
        "The test allocator implements the required seven-parameter allocator ABI.";
        response=Ignore))
end

"""Add reviewed metric policies for one animation state-machine module."""
function add_animation_loop_reviews!(reviews, path)
    functions = (
        ("loop", "animation-loop"),
        ("get_view_content", "animation-get-view-content"),
        ("initialize", "animation-initialize"),
        ("reset_cycle_state", "animation-reset-cycle-state"))
    for (function_name, policy_name) in functions
        push!(reviews, ReviewedComplexity(
            "$policy_name-lines:$path", path, :julia, function_name,
            :executable_lines, AnimationLoopReason;
            response=Ignore, minimum_matches=0))
        push!(reviews, ReviewedComplexity(
            "$policy_name-branching:$path", path, :julia, function_name,
            :cyclomatic_complexity, AnimationLoopReason;
            response=Ignore, minimum_matches=0))
    end
end

"""Return reviewed function metric policies for animation state-machine loops."""
function animation_loop_reviews()
    reviews = ReviewedComplexity[]
    foreach(path -> add_animation_loop_reviews!(reviews, path), AnimationLoopFiles)
    add_animation_reviews!(reviews)
    add_builder_test_allocation_procs!(reviews)
end

AnalysisSettings(
    BaseSettings.profile,
    BaseSettings.failure_threshold,
    BaseSettings.thresholds,
    [
        ScanProfile(:default, DefaultExcludes),
        ScanProfile(:all, AllExcludes),
        ScanProfile(:aspirational, DefaultExcludes),
    ],
    euclid_rule_settings(),
    euclid_naming_settings(),
    JetSettings([
        JetEntryPoint(
            "latex-canonical-presentation",
            "src/julia/latex.jl",
            EuclidAnalysisRoots.EuclidLatex.prime_latex!,
            (Ptr{Cvoid},)),
    ]),
    OdinBuildSettings([
        OdinBuildTarget(
            "application",
            "src",
            "euclid-analysis",
            [
                "-vet",
                "-strict-style",
                "-disallow-do",
                "-warnings-as-errors",
                "-define:RAYLIB_SHARED=true",
                "-extra-linker-flags:$(native_linker_flags())",
            ]),
    ]),
    ReturnTupleSettings(2, 2),
    ParameterCountSettings(8, 5, 8),
    FunctionMetricSettings(
        BaseSettings.function_metrics.julia_lines,
        BaseSettings.function_metrics.odin_lines,
        BaseSettings.function_metrics.julia_cyclomatic,
        BaseSettings.function_metrics.odin_cyclomatic,
        animation_loop_reviews()),
    default_architecture_settings(),
    AllocationSettings(
        BaseSettings.allocations.known_procedures,
        [
            BaseSettings.allocations.source_patterns...;
            AllocatorSourcePattern("builder.allocator", :custom);
            AllocatorSourcePattern("store.allocator", :custom);
            AllocatorSourcePattern("store.payload_allocator", :custom);
            AllocatorSourcePattern("state.allocator", :custom)
        ],
        [
            AllocationResponseOverride(r"_test\.odin$", :context, Ignore),
        ],
        ReviewedAllocationPolicy[
            # Shared arena ownership reserves virtual storage with explicit lifecycle.
            ReviewedAllocationPolicy(
                "core-arena-owner-growing-reservation",
                "src/core/arena_owner.odin",
                "arena_owner_growing_init",
                :arena,
                "Owner-scoped growing storage is reset in bulk and explicitly destroyed.";
                operation="arena_init_growing",
                target="arena",
                certainty=:definite,
                response=Ignore),
            ReviewedAllocationPolicy(
                "test-core-arena-owner-partial-init",
                "src/core/arena_owner_test.odin",
                "arena_owner_test_init_failure",
                :arena,
                "Test reservation is deliberately followed by failure to verify cleanup.";
                operation="arena_init_growing",
                target="arena",
                certainty=:definite,
                response=Ignore),
            custom_test_allocation_reviews()...,
            # Shared bounded builders grow within an explicit bulk-lifetime owner.
            ReviewedAllocationPolicy(
                "core-bounded-byte-builder-growth",
                "src/core/bounded_builder.odin",
                "bounded_byte_builder_reserve",
                :custom,
                "Hard-limit-checked geometric byte storage is reclaimed by the allocator owner at reset or destruction.";
                operation="make",
                target="[]u8",
                allocator_source="builder.allocator",
                certainty=:definite,
                response=Ignore),
            ReviewedAllocationPolicy(
                "core-bounded-element-builder-growth",
                "src/core/bounded_builder.odin",
                "bounded_element_builder_reserve",
                :custom,
                "Hard-limit-checked geometric plain-element storage is reclaimed by the allocator owner at reset or destruction.";
                operation="make",
                target="[]Element",
                allocator_source="builder.allocator",
                certainty=:definite,
                response=Ignore),
            ReviewedAllocationPolicy(
                "core-animation-value-store-payload",
                "src/core/animation_value_store.odin",
                "animation_value_store_insert",
                :custom,
                "Quota-checked opaque payload is retired by shared animation-memory reset or destruction.";
                operation="make",
                target="[]u8",
                allocator_source="store.allocator",
                certainty=:definite,
                response=Ignore),
            ReviewedAllocationPolicy(
                "core-animation-value-pending-payload",
                "src/core/animation_value_store.odin",
                "animation_value_pending_allocate_storage",
                :custom,
                "Validated pending payload storage is retired by shared animation-memory reset or destruction.";
                operation="make",
                target="[]u8",
                allocator_source="store.allocator",
                certainty=:definite,
                response=Ignore),
            # Terminal model storage is quota-bounded and reclaimed by its owner.
            ReviewedAllocationPolicy(
                "terminal-animation-pixels",
                "src/terminal/attachment/animation.odin",
                "animation_allocate",
                :custom,
                "Quota-checked animation pixels are released by attachment removal or store destruction.";
                operation="make",
                target="[]u8",
                allocator_source="store.payload_allocator",
                certainty=:definite,
                response=Ignore,
                minimum_matches=1,
                maximum_matches=1),
            ReviewedAllocationPolicy(
                "terminal-animation-frames",
                "src/terminal/attachment/animation.odin",
                "animation_allocate",
                :custom,
                "Quota-checked frame descriptors are released with their animation payload.";
                operation="make",
                target="[]Animation_Frame",
                allocator_source="store.payload_allocator",
                certainty=:definite,
                response=Ignore,
                minimum_matches=1,
                maximum_matches=1),
            ReviewedAllocationPolicy(
                "terminal-kitty-animation-pixels",
                "src/terminal/attachment/kitty_animation.odin",
                "kitty_animation_allocate",
                :custom,
                "Quota-checked replacement pixels are released on commit rollback or attachment teardown.";
                operation="make",
                target="[]u8",
                allocator_source="store.payload_allocator",
                certainty=:definite,
                response=Ignore,
                minimum_matches=1,
                maximum_matches=1),
            ReviewedAllocationPolicy(
                "terminal-kitty-animation-frames",
                "src/terminal/attachment/kitty_animation.odin",
                "kitty_animation_allocate",
                :custom,
                "Quota-checked replacement descriptors are released with their animation pixels.";
                operation="make",
                target="[]Animation_Frame",
                allocator_source="store.payload_allocator",
                certainty=:definite,
                response=Ignore,
                minimum_matches=1,
                maximum_matches=1),
            ReviewedAllocationPolicy(
                "terminal-attachment-admit-payload",
                "src/terminal/attachment/store.odin",
                "attachment_admit",
                :custom,
                "Exact admitted payload storage is released by removal, eviction, or store destruction.";
                operation="make",
                target="[]u8",
                allocator_source="store.payload_allocator",
                certainty=:definite,
                response=Ignore,
                minimum_matches=1,
                maximum_matches=1),
            ReviewedAllocationPolicy(
                "terminal-attachment-reserve-payload",
                "src/terminal/attachment/store.odin",
                "attachment_reserve",
                :custom,
                "Exact pending payload storage is released by publication, cancellation, or store destruction.";
                operation="make",
                target="[]u8",
                allocator_source="store.payload_allocator",
                certainty=:definite,
                response=Ignore,
                minimum_matches=1,
                maximum_matches=1),
            ReviewedAllocationPolicy(
                "terminal-transfer-payload",
                "src/terminal/attachment/store.odin",
                "transfer_begin",
                :custom,
                "Limit-checked transfer storage is released on completion or store destruction.";
                operation="make",
                target="[]u8",
                allocator_source="store.payload_allocator",
                certainty=:definite,
                response=Ignore,
                minimum_matches=1,
                maximum_matches=1),
            ReviewedAllocationPolicy(
                "terminal-attachment-store-table-attachments",
                "src/terminal/attachment/store.odin",
                "store_allocate_tables",
                :custom,
                "Capacity-bounded attachment table is allocated transactionally and released by store destruction or initialization rollback.";
                operation="make",
                target="[]Attachment_Entry",
                allocator_source="table_allocator",
                certainty=:definite,
                response=Ignore,
                minimum_matches=1,
                maximum_matches=1),
            ReviewedAllocationPolicy(
                "terminal-attachment-store-table-placements",
                "src/terminal/attachment/store.odin",
                "store_allocate_tables",
                :custom,
                "Capacity-bounded placement table is allocated transactionally and released by store destruction or initialization rollback.";
                operation="make",
                target="[]Placement_Entry",
                allocator_source="table_allocator",
                certainty=:definite,
                response=Ignore,
                minimum_matches=1,
                maximum_matches=1),
            ReviewedAllocationPolicy(
                "terminal-attachment-store-table-transfers",
                "src/terminal/attachment/store.odin",
                "store_allocate_tables",
                :custom,
                "Capacity-bounded transfer table is allocated transactionally and released by store destruction or initialization rollback.";
                operation="make",
                target="[]Transfer_Entry",
                allocator_source="table_allocator",
                certainty=:definite,
                response=Ignore,
                minimum_matches=1,
                maximum_matches=1),
            ReviewedAllocationPolicy(
                "terminal-attachment-store-table-residency",
                "src/terminal/attachment/store.odin",
                "store_allocate_tables",
                :custom,
                "Capacity-bounded residency table is allocated transactionally and released by store destruction or initialization rollback.";
                operation="make",
                target="[]Residency_Entry",
                allocator_source="table_allocator",
                certainty=:definite,
                response=Ignore,
                minimum_matches=1,
                maximum_matches=1),
            ReviewedAllocationPolicy(
                "terminal-placement-checkpoint-placements",
                "src/terminal/attachment/store.odin",
                "placement_checkpoint_init",
                :custom,
                "Placement-capacity mirror is allocated transactionally, reused across captures, and released by checkpoint destruction.";
                operation="make",
                target="[]Placement_Entry",
                allocator_source="allocator",
                certainty=:definite,
                response=Ignore,
                minimum_matches=1,
                maximum_matches=1),
            ReviewedAllocationPolicy(
                "terminal-placement-checkpoint-pins",
                "src/terminal/attachment/store.odin",
                "placement_checkpoint_init",
                :custom,
                "Placement-capacity attachment identity mirror is rolled back on partial failure and released by checkpoint destruction.";
                operation="make",
                target="[]Attachment_Id",
                allocator_source="allocator",
                certainty=:definite,
                response=Ignore,
                minimum_matches=1,
                maximum_matches=1),
            ReviewedAllocationPolicy(
                "terminal-clipboard-action-queue",
                "src/terminal/clipboard/clipboard.odin",
                "clipboard_action_queue_init",
                :custom,
                "Fixed-capacity action queue storage is retained by the Terminal clipboard owner and released by queue destruction.";
                operation="make",
                target="[]Clipboard_Action",
                allocator_source="allocator",
                certainty=:definite,
                response=Ignore,
                minimum_matches=1,
                maximum_matches=1),
            ReviewedAllocationPolicy(
                "terminal-grid-cells",
                "src/terminal/grid/grid.odin",
                "grid_init",
                :custom,
                "Geometry-bounded contiguous cell storage is rolled back on partial initialization and released by grid destruction.";
                operation="make",
                target="[]Cell",
                allocator_source="allocator",
                certainty=:definite,
                response=Ignore,
                minimum_matches=1,
                maximum_matches=1),
            ReviewedAllocationPolicy(
                "terminal-grid-rows",
                "src/terminal/grid/grid.odin",
                "grid_init",
                :custom,
                "Geometry-bounded row descriptors are rolled back on partial initialization and released by grid destruction.";
                operation="make",
                target="[]Row",
                allocator_source="allocator",
                certainty=:definite,
                response=Ignore,
                minimum_matches=1,
                maximum_matches=1),
            ReviewedAllocationPolicy(
                "terminal-grid-editing-state",
                "src/terminal/grid/grid.odin",
                "grid_init",
                :custom,
                "One stable editing-state slot is allocated with each grid and released by grid destruction.";
                operation="make",
                target="[]Grid_Editing_State",
                allocator_source="allocator",
                certainty=:definite,
                response=Ignore,
                minimum_matches=1,
                maximum_matches=1),
            ReviewedAllocationPolicy(
                "terminal-grid-snapshot-cells",
                "src/terminal/grid/grid.odin",
                "snapshot_init",
                :custom,
                "Exact visible-cell snapshot is rolled back on partial initialization and released by snapshot destruction.";
                operation="make",
                target="[]Cell",
                allocator_source="allocator",
                certainty=:definite,
                response=Ignore,
                minimum_matches=1,
                maximum_matches=1),
            ReviewedAllocationPolicy(
                "terminal-grid-snapshot-rows",
                "src/terminal/grid/grid.odin",
                "snapshot_init",
                :custom,
                "Exact visible-row metadata snapshot is released with its owning snapshot.";
                operation="make",
                target="[]Snapshot_Row",
                allocator_source="allocator",
                certainty=:definite,
                response=Ignore,
                minimum_matches=1,
                maximum_matches=1),
            ReviewedAllocationPolicy(
                "terminal-reflow-cells",
                "src/terminal/grid/reflow.odin",
                "reflow_allocate",
                :custom,
                "Shape-bounded reflow cells are allocated failure-atomically and released by reflow destruction.";
                operation="make",
                target="[]Cell",
                allocator_source="allocator",
                certainty=:definite,
                response=Ignore,
                minimum_matches=1,
                maximum_matches=1),
            ReviewedAllocationPolicy(
                "terminal-reflow-rows",
                "src/terminal/grid/reflow.odin",
                "reflow_allocate",
                :custom,
                "Shape-bounded reflow row descriptors are allocated failure-atomically and released by reflow destruction.";
                operation="make",
                target="[]Reflow_Row",
                allocator_source="allocator",
                certainty=:definite,
                response=Ignore,
                minimum_matches=1,
                maximum_matches=1),
            ReviewedAllocationPolicy(
                "terminal-reflow-old-boundaries",
                "src/terminal/grid/reflow.odin",
                "reflow_allocate",
                :custom,
                "Shape-bounded old-to-semantic boundary map is allocated failure-atomically and released by reflow destruction.";
                operation="make",
                target="[]Reflow_Old_To_Semantic",
                allocator_source="allocator",
                certainty=:definite,
                response=Ignore,
                minimum_matches=1,
                maximum_matches=1),
            ReviewedAllocationPolicy(
                "terminal-reflow-new-boundaries",
                "src/terminal/grid/reflow.odin",
                "reflow_allocate",
                :custom,
                "Shape-bounded semantic-to-new boundary map is allocated failure-atomically and released by reflow destruction.";
                operation="make",
                target="[]Reflow_Semantic_To_New",
                allocator_source="allocator",
                certainty=:definite,
                response=Ignore,
                minimum_matches=1,
                maximum_matches=1),
            ReviewedAllocationPolicy(
                "terminal-primary-reflow-source-rows",
                "src/terminal/grid/reflow.odin",
                "primary_reflow_source",
                :custom,
                "Source descriptors are bounded by retained rows and freed after primary reflow preparation or on failure.";
                operation="make",
                target="[]Reflow_Source_Row",
                allocator_source="allocator",
                certainty=:definite,
                response=Ignore,
                minimum_matches=1,
                maximum_matches=1),
            ReviewedAllocationPolicy(
                "terminal-checkpoint-reflow-source-rows",
                "src/terminal/grid/reflow.odin",
                "reflow_checkpoint_source",
                :custom,
                "Source descriptors are bounded by checkpoint rows and freed after checkpoint reflow preparation or on failure.";
                operation="make",
                target="[]Reflow_Source_Row",
                allocator_source="allocator",
                certainty=:definite,
                response=Ignore,
                minimum_matches=1,
                maximum_matches=1),
            ReviewedAllocationPolicy(
                "terminal-scrollback-cells",
                "src/terminal/grid/scrollback.odin",
                "scrollback_init",
                :custom,
                "Capacity-and-geometry-bounded cell ring is rolled back on partial initialization and released by scrollback destruction.";
                operation="make",
                target="[]Cell",
                allocator_source="allocator",
                certainty=:definite,
                response=Ignore,
                minimum_matches=1,
                maximum_matches=1),
            ReviewedAllocationPolicy(
                "terminal-scrollback-rows",
                "src/terminal/grid/scrollback.odin",
                "scrollback_init",
                :custom,
                "Fixed-capacity row metadata ring is released with its owning scrollback.";
                operation="make",
                target="[]Scrollback_Row",
                allocator_source="allocator",
                certainty=:definite,
                response=Ignore,
                minimum_matches=1,
                maximum_matches=1),
            ReviewedAllocationPolicy(
                "terminal-display-checkpoint-cells",
                "src/terminal/grid/scrollback.odin",
                "display_checkpoint_init",
                :custom,
                "Exact grid and scrollback cell mirrors are allocated transactionally, reused across captures, and released by checkpoint destruction.";
                operation="make",
                target="[]Cell",
                allocator_source="allocator",
                certainty=:definite,
                response=Ignore,
                minimum_matches=2,
                maximum_matches=2),
            ReviewedAllocationPolicy(
                "terminal-display-checkpoint-grid-rows",
                "src/terminal/grid/scrollback.odin",
                "display_checkpoint_init",
                :custom,
                "Exact visible-row metadata mirror is released by checkpoint destruction or initialization rollback.";
                operation="make",
                target="[]Snapshot_Row",
                allocator_source="allocator",
                certainty=:definite,
                response=Ignore,
                minimum_matches=1,
                maximum_matches=1),
            ReviewedAllocationPolicy(
                "terminal-display-checkpoint-scrollback-rows",
                "src/terminal/grid/scrollback.odin",
                "display_checkpoint_init",
                :custom,
                "Exact scrollback row-ring mirror is released by checkpoint destruction or initialization rollback.";
                operation="make",
                target="[]Scrollback_Row",
                allocator_source="allocator",
                certainty=:definite,
                response=Ignore,
                minimum_matches=1,
                maximum_matches=1),
            ReviewedAllocationPolicy(
                "terminal-display-checkpoint-command-blocks",
                "src/terminal/grid/scrollback.odin",
                "display_checkpoint_init",
                :custom,
                "Optional command-block mirror is bounded by shell history and released by checkpoint destruction or initialization rollback.";
                operation="make",
                target="[]termmodel.Command_Block",
                allocator_source="allocator",
                certainty=:definite,
                response=Ignore,
                minimum_matches=1,
                maximum_matches=1),
            ReviewedAllocationPolicy(
                "terminal-history-text-storage",
                "src/terminal/history/termhist.odin",
                "termhist_allocate_storage",
                :custom,
                "Editor text and backup storage are explicitly destroyed with the history state.";
                operation="make",
                target="[]u8",
                allocator_source="state.allocator",
                certainty=:definite,
                response=Ignore,
                minimum_matches=2,
                maximum_matches=2),
            ReviewedAllocationPolicy(
                "terminal-history-entry-storage",
                "src/terminal/history/termhist.odin",
                "termhist_allocate_storage",
                :custom,
                "History entry storage is explicitly destroyed with the history state.";
                operation="make",
                target="[]Termhist_Entry",
                allocator_source="state.allocator",
                certainty=:definite,
                response=Ignore,
                minimum_matches=1,
                maximum_matches=1),
            ReviewedAllocationPolicy(
                "terminal-history-cloned-text",
                "src/terminal/history/termhist.odin",
                "termhist_clone_text",
                :custom,
                "Exact UTF-8 history snapshot is deleted on replacement or with the bounded history owner.";
                operation="make",
                target="[]u8",
                allocator_source="allocator",
                certainty=:definite,
                response=Ignore,
                minimum_matches=1,
                maximum_matches=1),
            ReviewedAllocationPolicy(
                "terminal-hyperlink-registry",
                "src/terminal/hyperlink/hyperlink.odin",
                "hyperlink_registry_init",
                :custom,
                "Fixed-capacity hyperlink entries are retained by the registry and released by registry destruction.";
                operation="make",
                target="[]Hyperlink_Entry",
                allocator_source="allocator",
                certainty=:definite,
                response=Ignore,
                minimum_matches=1,
                maximum_matches=1),
            ReviewedAllocationPolicy(
                "terminal-unix-backend-workspace-storage",
                "src/terminal/session/unix_backend_unix.odin",
                "unix_terminal_backend_init",
                :custom,
                "Fixed native launch workspace is allocated from the backend arena and reclaimed when that arena is destroyed on failure or teardown.";
                operation="make",
                target="[]u8",
                allocator_source="allocator",
                certainty=:definite,
                response=Ignore,
                minimum_matches=1,
                maximum_matches=1),
            ReviewedAllocationPolicy(
                "terminal-windows-backend-workspace-storage",
                "src/terminal/session/windows_backend_windows.odin",
                "windows_terminal_backend_init",
                :custom,
                "Fixed native launch workspace is allocated from the backend arena and reclaimed when that arena is destroyed on failure or teardown.";
                operation="make",
                target="[]u8",
                allocator_source="allocator",
                certainty=:definite,
                response=Ignore,
                minimum_matches=1,
                maximum_matches=1),
            ReviewedAllocationPolicy(
                "terminal-shell-integration-command-blocks",
                "src/terminal/shell_integration/shell_integration.odin",
                "shell_integration_init",
                :custom,
                "Fixed-capacity command-block ring is retained by shell integration and released by explicit destruction.";
                operation="make",
                target="[]termmodel.Command_Block",
                allocator_source="allocator",
                certainty=:definite,
                response=Ignore,
                minimum_matches=1,
                maximum_matches=1),
            ReviewedAllocationPolicy(
                "terminal-history-entry-growth",
                "src/terminal/history/termhist.odin",
                "termhist_ensure_history_capacity",
                :custom,
                "Bounded history growth replaces and frees prior owner-backed storage.";
                operation="make",
                target="[]Termhist_Entry",
                allocator_source="state.allocator",
                certainty=:definite,
                response=Ignore,
                minimum_matches=1,
                maximum_matches=1),
            ReviewedAllocationPolicy(
                "terminal-history-buffer-growth",
                "src/terminal/history/termhist.odin",
                "termhist_ensure_u8_capacity",
                :custom,
                "Bounded UTF-8 buffer growth replaces and frees prior owner-backed storage.";
                operation="make",
                target="[]u8",
                allocator_source="state.allocator",
                certainty=:definite,
                response=Ignore,
                minimum_matches=1,
                maximum_matches=1),
            ReviewedAllocationPolicy(
                "test-animation-memory-generation-payload",
                "src/core/animation_memory_test.odin",
                "core_test_animation_memory_advances_generation",
                :custom,
                "Test payload is invalidated by generation reset and its arena is destroyed by deferred fixture teardown.";
                operation="make",
                target="[]u8",
                certainty=:definite,
                response=Ignore,
                minimum_matches=1,
                maximum_matches=1),
            ReviewedAllocationPolicy(
                "test-animation-memory-destroy-payload",
                "src/core/animation_memory_test.odin",
                "core_test_animation_memory_destroy_preserves_diagnostics",
                :custom,
                "Test payload is released by the explicit destroy whose terminal diagnostics the test verifies.";
                operation="make",
                target="[]u8",
                certainty=:definite,
                response=Ignore,
                minimum_matches=1,
                maximum_matches=1),
            ReviewedAllocationPolicy(
                "dynview-math-kern-record-cache",
                "src/dynview/math/shaping_cache.odin",
                "cache_math_kern_records",
                :custom,
                "Exact-size immutable kern-table storage is reclaimed when the cache arena is reset or destroyed.";
                operation="make",
                target="[]app_core.Font_Math_Kern_Table",
                allocator_source="allocator",
                certainty=:definite,
                response=Ignore,
                minimum_matches=1,
                maximum_matches=1),
            ReviewedAllocationPolicy(
                "dynview-math-accent-source-cache",
                "src/dynview/math/shaping_cache.odin",
                "cache_math_accent_source_records",
                :custom,
                "Exact-size immutable accent-source storage is reclaimed when the cache arena is reset or destroyed.";
                operation="make",
                target="[][2]app_core.Font_Math_Stretch_Source",
                allocator_source="allocator",
                certainty=:definite,
                response=Ignore,
                minimum_matches=1,
                maximum_matches=1),
            ReviewedAllocationPolicy(
                "bridge-interface-registry-growing-arena",
                "src/bridge/bootstrap.odin",
                "ensure_julia_interface_registry_arena",
                :arena,
                "One interface-generation arena is bulk-reset on reuse or rollback and destroyed at service teardown.";
                operation="arena_init_growing",
                target="iface^.animation_registry_arena",
                certainty=:definite,
                response=Ignore),
            ReviewedAllocationPolicy(
                "view-terminal-retained-text",
                "src/view/terminal/lifecycle.odin",
                "terminal_init_retained_text",
                :custom,
                "Three fixed-capacity editable-text buffers are allocated transactionally from the Terminal owner allocator and reclaimed with that allocator after semantic teardown.";
                operation="make",
                target="[]u8",
                allocator_source="allocator",
                certainty=:definite,
                response=Ignore,
                minimum_matches=3,
                maximum_matches=3),
            ReviewedAllocationPolicy(
                "view-terminal-retained-title-state",
                "src/view/terminal/lifecycle.odin",
                "terminal_init_retained_storage",
                :custom,
                "One stable title-state slot is published only after complete Terminal initialization and reclaimed with the Terminal owner allocator.";
                operation="make",
                target="[]termemulator.Terminal_Title_State",
                allocator_source="allocator",
                certainty=:definite,
                response=Ignore,
                minimum_matches=1,
                maximum_matches=1),
            ReviewedAllocationPolicy(
                "view-terminal-retained-display-checkpoint",
                "src/view/terminal/lifecycle.odin",
                "terminal_init_retained_storage",
                :custom,
                "One stable display-checkpoint owner slot is published after initialization and reclaimed with the Terminal owner allocator after checkpoint teardown.";
                operation="make",
                target="[]termgrid.Display_Checkpoint",
                allocator_source="allocator",
                certainty=:definite,
                response=Ignore,
                minimum_matches=1,
                maximum_matches=1),
            ReviewedAllocationPolicy(
                "view-terminal-retained-synchronized-output",
                "src/view/terminal/lifecycle.odin",
                "terminal_init_retained_storage",
                :custom,
                "One stable synchronized-output slot is published after initialization and reclaimed with the Terminal owner allocator after semantic teardown.";
                operation="make",
                target="[]termemulator.Synchronized_Output_State",
                allocator_source="allocator",
                certainty=:definite,
                response=Ignore,
                minimum_matches=1,
                maximum_matches=1),
            ReviewedAllocationPolicy(
                "view-terminal-retained-attachment-store",
                "src/view/terminal/lifecycle.odin",
                "terminal_init_retained_storage",
                :custom,
                "One stable attachment-store slot is published after initialization and reclaimed with the Terminal owner allocator after store teardown.";
                operation="make",
                target="[]termattachment.Store",
                allocator_source="allocator",
                certainty=:definite,
                response=Ignore,
                minimum_matches=1,
                maximum_matches=1),
            ReviewedAllocationPolicy(
                "view-terminal-retained-graphics-parser",
                "src/view/terminal/lifecycle.odin",
                "terminal_init_retained_storage",
                :custom,
                "One stable graphics-parser slot is published after initialization and reclaimed with the Terminal owner allocator after parser teardown.";
                operation="make",
                target="[]gfxprotocol.Graphics_Parser_State",
                allocator_source="allocator",
                certainty=:definite,
                response=Ignore,
                minimum_matches=1,
                maximum_matches=1),
            ReviewedAllocationPolicy(
                "view-terminal-retained-hyperlink-registry",
                "src/view/terminal/lifecycle.odin",
                "terminal_init_retained_storage",
                :custom,
                "One stable hyperlink-registry slot is published after initialization and reclaimed with the Terminal owner allocator after registry teardown.";
                operation="make",
                target="[]termhyperlink.Hyperlink_Registry",
                allocator_source="allocator",
                certainty=:definite,
                response=Ignore,
                minimum_matches=1,
                maximum_matches=1),
            ReviewedAllocationPolicy(
                "view-terminal-retained-clipboard-queue",
                "src/view/terminal/lifecycle.odin",
                "terminal_init_retained_storage",
                :custom,
                "One stable clipboard-queue slot is published after initialization and reclaimed with the Terminal owner allocator after queue teardown.";
                operation="make",
                target="[]termclipboard.Clipboard_Action_Queue",
                allocator_source="allocator",
                certainty=:definite,
                response=Ignore,
                minimum_matches=1,
                maximum_matches=1),
            ReviewedAllocationPolicy(
                "view-terminal-retained-shell-integration",
                "src/view/terminal/lifecycle.odin",
                "terminal_init_retained_storage",
                :custom,
                "One stable shell-integration slot is published after initialization and reclaimed with the Terminal owner allocator after shell-state teardown.";
                operation="make",
                target="[]termshellintegration.Shell_Integration_State",
                allocator_source="allocator",
                certainty=:definite,
                response=Ignore,
                minimum_matches=1,
                maximum_matches=1),
            ReviewedAllocationPolicy(
                "view-terminal-selection-line-table",
                "src/view/terminal/clipboard.odin",
                "terminal_view_selection_text",
                :temporary,
                "Frame-local line views are bounded by the selected terminal extent, do not escape clipboard composition, and are reclaimed at temporary-allocator reset.";
                operation="make",
                target="[]string",
                allocator_source="context.temp_allocator",
                certainty=:definite,
                response=Ignore,
                minimum_matches=1,
                maximum_matches=1),
            ReviewedAllocationPolicy(
                "test-terminal-alternate-screen-cell-snapshot",
                "src/terminal/emulator/interpreter_test.odin",
                "termgrid_test_interpreter_alternate_screen_restores_primary",
                :temporary,
                "Test-only exact cell snapshot remains local to one assertion sequence and is reclaimed at temporary-allocator reset.";
                operation="make",
                target="[]Cell",
                allocator_source="context.temp_allocator",
                certainty=:definite,
                response=Ignore,
                minimum_matches=1,
                maximum_matches=1),
            ReviewedAllocationPolicy(
                "files-gif-session-growing-arena",
                "src/files/gif_encode.odin",
                "gif_encode_ensure_arena",
                :arena,
                "One capture-session arena is bulk-reset between recordings and destroyed with encoder state.";
                operation="arena_init_growing",
                target="state.arena",
                certainty=:definite,
                response=Ignore),
            # Bridge Animations Allocations ; these use a dedicated arena
            ReviewedAllocationPolicy(
                "bridge-animation-lookup-arena",
                "src/bridge/animations.odin",
                "animation_lookup_allocate",
                :unknown,
                "A dedicated arena is used to allocate lookup information.";
                operation="make",
                target="[]core.Euclid_Julia_Animation_Lookup_Entry",
                certainty=:definite,
                response=Ignore),
            ReviewedAllocationPolicy(
                "bridge-animation-add-registered-arena",
                "src/bridge/animations.odin",
                "add_animation_to_registry",
                :unknown,
                "A dedicated arena is used to allocate new animation registries.";
                operation="new",
                target="core.Euclid_Julia_Animation_Interface",
                certainty=:definite,
                response=Ignore),
            # Bridge Runtime Service Allocations ; these allocate the main bridge runtime
            ReviewedAllocationPolicy(
                "bridge-runtime-create-services",
                "src/bridge/runtime_service.odin",
                "create_julia_runtime_service",
                :implicit,
                "Single one-time creation of the julia runtime service structure.";
                operation="new",
                target="Julia_Runtime_Service",
                certainty=:definite,
                response=Ignore),
            # Communication links own one bounded TLSF pool and reclaim transferred data.
            ReviewedAllocationPolicy(
                "bridge-communication-link-backing",
                "src/bridge/communication_link.odin",
                "communication_link_init",
                :custom,
                "Fixed pool backing is stored on the link and deleted after both channels are destroyed.";
                operation="make",
                target="[]byte",
                certainty=:definite,
                response=Ignore,
                minimum_matches=1,
                maximum_matches=1),
            ReviewedAllocationPolicy(
                "bridge-communication-link-envelope",
                "src/bridge/communication_link.odin",
                "communication_link_alloc",
                :custom,
                "Producer-owned envelopes use the bounded link pool and are reclaimed after return.";
                operation="new",
                target="T",
                certainty=:definite,
                response=Ignore,
                minimum_matches=1,
                maximum_matches=1),
            ReviewedAllocationPolicy(
                "bridge-communication-link-nested-bytes",
                "src/bridge/communication_link.odin",
                "communication_link_alloc_bytes",
                :custom,
                "Nested payload bytes use the bounded link pool and are reclaimed with their envelope.";
                operation="make",
                target="[]u8",
                certainty=:definite,
                response=Ignore,
                minimum_matches=1,
                maximum_matches=1),
            # Display presentation allocations live for one runtime session.
            ReviewedAllocationPolicy(
                "view-presentation-runtime-storage",
                "src/view/presentation_runtime.odin",
                "create_presentation_runtime",
                :context,
                "Display-owned presentation state is created once per process run and explicitly destroyed after parse work joins.";
                operation="new",
                target="Presentation_Runtime",
                certainty=:definite,
                response=Ignore,
                minimum_matches=1,
                maximum_matches=1),
            ReviewedAllocationPolicy(
                "view-presentation-parse-result-storage",
                "src/view/presentation_runtime.odin",
                "create_presentation_runtime",
                :context,
                "Display-owned parser result storage persists for one process run and is explicitly destroyed with its presentation runtime.";
                operation="new",
                target="dyncore.Dynview_Parse_Result",
                certainty=:definite,
                response=Ignore,
                minimum_matches=1,
                maximum_matches=1),
            ReviewedAllocationPolicy(
                "view-presentation-staging-storage",
                "src/view/presentation_runtime.odin",
                "create_presentation_runtime",
                :context,
                "Display-owned Dynview staging persists for one process run and is explicitly destroyed with its presentation runtime.";
                operation="new",
                target="core.Dynview_System",
                certainty=:definite,
                response=Ignore,
                minimum_matches=1,
                maximum_matches=1),
            # Native document storage and layout scratch use explicit allocator owners.
            ReviewedAllocationPolicy(
                "dynview-document-store-parse-result",
                "src/dynview/core/document_store.odin",
                "document_store_intern_keyed",
                :temporary,
                "One parse result is explicitly freed from the temporary allocator before interning returns.";
                operation="new",
                target="Dynview_Parse_Result",
                certainty=:definite,
                response=Ignore,
                minimum_matches=1,
                maximum_matches=1),
            ReviewedAllocationPolicy(
                "dynview-document-store-blob",
                "src/dynview/core/document_store.odin",
                "document_store_allocate_blob",
                :custom,
                "Quota-checked immutable document bytes are owned by the store arena and retired on reset or destruction.";
                operation="make",
                target="[]u64",
                certainty=:definite,
                response=Ignore,
                minimum_matches=1,
                maximum_matches=1),
            ReviewedAllocationPolicy(
                "dynview-document-break-candidates",
                "src/dynview/layout/optimal.odin",
                "document_break_allocate_scratch",
                :custom,
                "Bounded candidate scratch belongs to the caller's layout transaction arena.";
                operation="make",
                target="[]Document_Break_Candidate",
                certainty=:definite,
                response=Ignore,
                minimum_matches=1,
                maximum_matches=1),
            ReviewedAllocationPolicy(
                "dynview-document-break-states",
                "src/dynview/layout/optimal.odin",
                "document_break_allocate_scratch",
                :custom,
                "Bounded state scratch belongs to the caller's layout transaction arena.";
                operation="make",
                target="[]Document_Break_State",
                certainty=:definite,
                response=Ignore,
                minimum_matches=1,
                maximum_matches=1),
            # Focused Dynview fixtures are reclaimed by their explicit arena owners.
            ReviewedAllocationPolicy(
                "test-prose-shaping-complete-cache",
                "src/dynview/compile/prose_shaping_test.odin",
                "document_prose_shaping_seals_complete_records",
                :custom,
                "Compile-cache fixture storage is reclaimed by deferred arena-owner destruction.";
                operation="new",
                target="app_core.Dynview_Compile_Cache",
                certainty=:definite,
                response=Ignore,
                minimum_matches=1,
                maximum_matches=1),
            ReviewedAllocationPolicy(
                "test-prose-shaping-stale-cache",
                "src/dynview/compile/prose_shaping_test.odin",
                "document_prose_shaping_rejects_stale_generation",
                :custom,
                "Compile-cache fixture storage is reclaimed by deferred arena-owner destruction.";
                operation="new",
                target="app_core.Dynview_Compile_Cache",
                certainty=:definite,
                response=Ignore,
                minimum_matches=1,
                maximum_matches=1),
            ReviewedAllocationPolicy(
                "test-prose-shaping-runtime",
                "src/dynview/compile/prose_shaping_test.odin",
                "document_prose_shaping_measures_semantic_inlines_deterministically",
                :custom,
                "Runtime fixture storage is reclaimed by deferred runtime-arena destruction.";
                operation="new",
                target="app_core.Dynview_System",
                certainty=:definite,
                response=Ignore,
                minimum_matches=1,
                maximum_matches=1),
            ReviewedAllocationPolicy(
                "test-document-parse-isolated-results",
                "src/dynview/core/document_store_test.odin",
                "document_parse_builds_are_isolated_from_store_state",
                :temporary,
                "Both independent parse results are explicitly freed from the temporary allocator.";
                operation="new",
                target="Dynview_Parse_Result",
                certainty=:definite,
                response=Ignore,
                minimum_matches=2,
                maximum_matches=2),
            ReviewedAllocationPolicy(
                "test-document-parse-legacy-result",
                "src/dynview/core/document_store_test.odin",
                "document_parse_commit_matches_legacy_intern",
                :temporary,
                "The split-path parse result is explicitly freed after comparison with direct interning.";
                operation="new",
                target="Dynview_Parse_Result",
                certainty=:definite,
                response=Ignore,
                minimum_matches=1,
                maximum_matches=1),
            ReviewedAllocationPolicy(
                "test-document-parse-negative-result",
                "src/dynview/core/document_store_test.odin",
                "document_parse_commit_preserves_negative_cache",
                :temporary,
                "The rejected parse result is explicitly freed after negative-cache verification.";
                operation="new",
                target="Dynview_Parse_Result",
                certainty=:definite,
                response=Ignore,
                minimum_matches=1,
                maximum_matches=1),
            ReviewedAllocationPolicy(
                "test-document-parse-retired-result",
                "src/dynview/core/document_store_test.odin",
                "document_parse_commit_rejects_retired_generation",
                :temporary,
                "The stale-generation parse result is explicitly freed after rejection verification.";
                operation="new",
                target="Dynview_Parse_Result",
                certainty=:definite,
                response=Ignore,
                minimum_matches=1,
                maximum_matches=1),
            ReviewedAllocationPolicy(
                "test-document-parse-atomic-result",
                "src/dynview/core/document_store_test.odin",
                "document_parse_split_path_fails_atomically",
                :temporary,
                "The reused failure-path parse result is explicitly freed after transactional checks.";
                operation="new",
                target="Dynview_Parse_Result",
                certainty=:definite,
                response=Ignore,
                minimum_matches=1,
                maximum_matches=1),
            ReviewedAllocationPolicy(
                "test-document-parse-dispatch-result",
                "src/dynview/core/document_store_test.odin",
                "document_parse_commit_preserves_dispatch_rejection",
                :temporary,
                "The unsupported-mode parse result is explicitly freed after rejection verification.";
                operation="new",
                target="Dynview_Parse_Result",
                certainty=:definite,
                response=Ignore,
                minimum_matches=1,
                maximum_matches=1),
            ReviewedAllocationPolicy(
                "test-document-layout-runtime",
                "src/dynview/layout/document_build_test.odin",
                "document_layout_test_runtime",
                :custom,
                "Runtime fixture storage belongs to the caller-provided arena owner.";
                operation="new",
                target="app_core.Dynview_System",
                certainty=:definite,
                response=Ignore,
                minimum_matches=1,
                maximum_matches=1),
            ReviewedAllocationPolicy(
                "test-dynview-prose-font-runtime",
                "src/view/dynview_test.odin",
                "dynview_track_prose_fonts_includes_effective_variant",
                :custom,
                "Runtime fixture storage is reclaimed by deferred arena-owner destruction.";
                operation="new",
                target="app_core.Dynview_System",
                certainty=:definite,
                response=Ignore,
                minimum_matches=1,
                maximum_matches=1),
            ReviewedAllocationPolicy(
                "input-runtime",
                "src/view/input/runtime.odin",
                "input_runtime_create",
                :custom,
                "The display owner allocates one fixed-layout input runtime before the " *
                    "window loop and releases it during orderly display teardown.";
                operation="new",
                target="Input_Runtime",
                allocator_source="allocator",
                certainty=:definite,
                response=Ignore),
            # GIF Encoding Allocations ; There is a dedicated arena and some minor heap allocation
            ReviewedAllocationPolicy(
                "files-gif-encode-lzwmem",
                "src/files/gif_encode.odin",
                "gif_encode_allocate_buffers",
                :unknown,
                "Allocate GIF buffers on the dedicated GIF capture arena.";
                operation="make",
                target="[]i16",
                certainty=:definite,
                response=Ignore),
            ReviewedAllocationPolicy(
                "files-gif-encode-tlb-used-mem",
                "src/files/gif_encode.odin",
                "gif_encode_allocate_buffers",
                :unknown,
                "Allocate GIF buffers on the dedicated GIF capture arena.";
                operation="make",
                target="[]u8",
                certainty=:definite,
                response=Ignore,
                maximum_matches=2),
            ReviewedAllocationPolicy(
                "files-gif-encode-pixels",
                "src/files/gif_encode.odin",
                "gif_encode_allocate_buffers",
                :unknown,
                "Allocate GIF buffers on the dedicated GIF capture arena.";
                operation="make",
                target="[]u32",
                certainty=:definite,
                response=Ignore,
                maximum_matches=2),
            ReviewedAllocationPolicy(
                "files-gif-encode-end-file-data",
                "src/files/gif_encode.odin",
                "gif_encode_end",
                :implicit,
                "One time allocation with a known destruction.";
                operation="make",
                target="[]u8",
                certainty=:definite,
                response=Ignore),
            ReviewedAllocationPolicy(
                "files-gif-encode-new-buffer",
                "src/files/gif_encode.odin",
                "gif_encode_new_buffer",
                :unknown,
                "Allocates on a dedicated and well managed arena for GIF capture.";
                operation="new",
                target="Gif_Encode_Buffer",
                certainty=:definite,
                response=Ignore),
            ReviewedAllocationPolicy(
                "files-gif-encode-new-buffer-data",
                "src/files/gif_encode.odin",
                "gif_encode_new_buffer",
                :unknown,
                "Allocates on a dedicated and well managed arena for GIF capture.";
                operation="make",
                target="[]u8",
                certainty=:definite,
                response=Ignore),
            ReviewedAllocationPolicy(
                "files-gif-encode-begin-lzw-stream",
                "src/files/gif_encode.odin",
                "gif_encode_begin_lzw_bitstream",
                :unknown,
                "Allocates on a dedicated and well managed arena for GIF capture.";
                operation="make",
                target="[]u8",
                certainty=:definite,
                response=Ignore),
            # Primary Runtime Allocations -- These are all single allocations made once
            ReviewedAllocationPolicy(
                "view-runtime-session-iso-scale",
                "src/view/runtime_session.odin",
                "make_iso_scale",
                :implicit,
                "Created once at startup with a definitive destruction at application end.";
                operation="new",
                target="Iso_Scale",
                certainty=:definite,
                response=Ignore),
            ReviewedAllocationPolicy(
                "view-runtime-session-drawing-surface",
                "src/view/runtime_session.odin",
                "make_drawing_surface",
                :implicit,
                "Created once at startup with a definitive destruction at application end.";
                operation="new",
                target="Euclid_Drawing_Surface",
                certainty=:definite,
                response=Ignore),
            ReviewedAllocationPolicy(
                "view-runtime-session-shape-world",
                "src/view/runtime_session.odin",
                "make_shape_storage",
                :context,
                "Created once at startup with a definitive destruction at application end.";
                operation="new",
                target="core.Shape_World",
                certainty=:definite,
                response=Ignore,
                minimum_matches=1,
                maximum_matches=1),
            ReviewedAllocationPolicy(
                "view-runtime-session-particle-system",
                "src/view/runtime_session.odin",
                "make_animations_state",
                :context,
                "Created once at startup with a definitive destruction at application end.";
                operation="new",
                target="Particle_System",
                certainty=:definite,
                response=Ignore,
                minimum_matches=1,
                maximum_matches=1),
            ReviewedAllocationPolicy(
                "view-runtime-session-general-state",
                "src/view/runtime_session.odin",
                "make_animations_state",
                :context,
                "Created once at startup with a definitive destruction at application end.";
                operation="new",
                target="Euclid_General_State",
                certainty=:definite,
                response=Ignore,
                minimum_matches=1,
                maximum_matches=1),
            ReviewedAllocationPolicy(
                "view-simulation-executor",
                "src/view/simulation_executor.odin",
                "create_simulation_executor",
                :implicit,
                "Created once at startup with a definitive destruction at application end.";
                operation="new",
                target="Simulation_Executor",
                certainty=:definite,
                response=Ignore),
            ReviewedAllocationPolicy(
                "view-prose-shaping-workspace",
                "src/view/simulation_executor.odin",
                "create_simulation_executor",
                :implicit,
                "Bounded workspace created with the executor and released after its worker pool joins.";
                operation="new",
                target="core.Document_Prose_Shaping_Workspace",
                certainty=:definite,
                response=Ignore),
            ReviewedAllocationPolicy(
                "view-font-preparation-arena",
                "src/view/font/async.odin",
                "cache_preparation_arena_init",
                :arena,
                "Reserved once on first optional-font demand, reused across preparations, and destroyed with the font cache.";
                operation="arena_init_static",
                target="cache.preparation_arena",
                certainty=:definite,
                response=Ignore),
            # TODO : This next is allocated on context.allocator i.e. the heap
            #        re-review if safer allocator can fill
            ReviewedAllocationPolicy(
                "view-font-generation-glyph-metadata",
                "src/view/font/font.odin",
                "font_generation_glyphs_init",
                :custom,
                "Exact-size glyph state allocated once per resident font generation " *
                    "and released during generation teardown.";
                operation="make",
                target="[]Font_Glyph_Record",
                allocator_source="allocator",
                certainty=:definite,
                response=Ignore),
            ReviewedAllocationPolicy(
                "view-font-harfbuzz-ownership-test-arena",
                "src/view/font/font_test.odin",
                "view_test_harfbuzz_owns_source_and_bounds_output",
                :arena,
                "Test-only arena is destroyed before shaping to verify HarfBuzz copied the source bytes.";
                operation="arena_init_static",
                target="arena",
                certainty=:definite,
                response=Ignore),
            # Font preparation buffers use the dedicated preparation allocator and are
            # released together when preparation is reset or destroyed.
            ReviewedAllocationPolicy(
                "view-font-prepare-glyph-metadata",
                "src/view/font/prepare.odin",
                "prepare_allocate_metadata",
                :custom,
                "Bounded glyph metadata owned by Prepared_Font and released by prepare_destroy or the preparation arena reset.";
                operation="make",
                target="[]Prepared_Glyph",
                allocator_source="allocator",
                certainty=:definite,
                response=Ignore),
            ReviewedAllocationPolicy(
                "view-font-prepare-rectangle-metadata",
                "src/view/font/prepare.odin",
                "prepare_allocate_metadata",
                :custom,
                "Bounded rectangle metadata owned by Prepared_Font and released by prepare_destroy or the preparation arena reset.";
                operation="make",
                target="[]Prepared_Rectangle",
                allocator_source="allocator",
                certainty=:definite,
                response=Ignore),
            ReviewedAllocationPolicy(
                "view-font-prepare-atlas-pixels",
                "src/view/font/prepare.odin",
                "prepare_allocate_atlas",
                :custom,
                "Sized font-atlas storage owned by Prepared_Font and released by prepare_destroy or the preparation arena reset.";
                operation="make",
                target="[]u8",
                allocator_source="allocator",
                certainty=:definite,
                response=Ignore),
            # Task-pool storage is capacity-bounded and released by pool or fence teardown.
            ReviewedAllocationPolicy(
                "taskpool-backend-slots",
                "src/taskpool/taskpool.odin",
                "task_pool_init_backend",
                :custom,
                "Fixed-capacity task slots allocated once during pool initialization and released during pool teardown.";
                operation="make",
                target="[]Task_Slot",
                allocator_source="allocator",
                certainty=:definite,
                response=Ignore),
            ReviewedAllocationPolicy(
                "taskpool-backend-completion-reserve",
                "src/taskpool/taskpool.odin",
                "task_pool_init_backend",
                :dynamic_growth,
                "Completion storage is fully reserved to the configured task capacity before workers start.";
                operation="reserve",
                target="pool.backend.tasks_done",
                certainty=:potential,
                response=Ignore),
            ReviewedAllocationPolicy(
                "taskpool-fence-handles",
                "src/taskpool/taskpool.odin",
                "task_fence_begin",
                :custom,
                "One handle per fixed task slot, released when the deterministic fence is completed.";
                operation="make",
                target="[]Task_Handle",
                allocator_source="allocator",
                certainty=:definite,
                response=Ignore),
            # Native terminal backends reserve one fixed workspace for their complete
            # lifetime and destroy it on initialization failure or backend teardown.
            ReviewedAllocationPolicy(
                "terminal-unix-backend-workspace-arena",
                "src/terminal/session/unix_backend_unix.odin",
                "unix_terminal_backend_init",
                :arena,
                "One fixed-capacity native launch workspace reserved per backend and destroyed on initialization failure or backend teardown.";
                operation="arena_init_static",
                target="backend.workspace_arena",
                certainty=:definite,
                response=Ignore),
            ReviewedAllocationPolicy(
                "terminal-windows-backend-workspace-arena",
                "src/terminal/session/windows_backend_windows.odin",
                "windows_terminal_backend_init",
                :arena,
                "One fixed-capacity native launch workspace reserved per backend and destroyed on initialization failure or backend teardown.";
                operation="arena_init_static",
                target="backend.workspace_arena",
                certainty=:definite,
                response=Ignore),
            # The display state owns one reusable graphics service across Terminal
            # generations and deletes it after shutdown, before task-pool teardown.
            ReviewedAllocationPolicy(
                "view-terminal-graphics-service",
                "src/view/terminal_graphics_service.odin",
                "terminal_graphics_runtime_init",
                :context,
                "Single display-owned service allocated at runtime initialization, reused across Terminal generations, and freed after service shutdown before its task-pool owner.";
                operation="new",
                target="viewgraphics.Service",
                allocator_source="context.allocator",
                certainty=:definite,
                response=Ignore),
            # Evidence export allocates only at an explicit durable-output boundary.
            ReviewedAllocationPolicy(
                "evidence-artifact-trace-buffer",
                "src/evidence/artifact/artifact.odin",
                "artifact_trace_bytes",
                :context,
                "Bounded serialized trace buffer deleted by standalone and bundle writers after the write completes.";
                operation="make",
                target="[]byte",
                allocator_source="context.allocator",
                certainty=:definite,
                response=Ignore),
            # Test Allocations -- every site is a test fixture destroyed by defer free
            ReviewedAllocationPolicy(
                "test-gif-encode-collect-gce-packed-bytes",
                "src/files/gif_encode_test.odin",
                "collect_gce_packed_bytes",
                :temporary,
                "Test helper buffer on the temporary allocator, freed by test teardown.";
                operation="make",
                target="[]u8",
                certainty=:definite,
                response=Ignore),
            ]),
    ReportSettings(
        BaseSettings.report.color,
        BaseSettings.report.warning_limit,
        BaseSettings.report.report_limit;
        staging_maximum_response=Ignore,
        reviewed_diagnostics=ReviewedDiagnosticPolicy[
            ReviewedDiagnosticPolicy(
                "bridge-standard-julia-callback-wrapper",
                "ODIN-UNREACHABLE-PROCEDURE",
                "src/bridge/animations.odin",
                "call_julia_callback1",
                "Intentional standard Julia-caller shape retained to clarify the typed callback convention."),
            ReviewedDiagnosticPolicy(
                "julia-platform-host-symbol-cache",
                "JULIA-NONCONST-GLOBAL",
                "src/julia/bridge/common.jl",
                "HOST_SYMBOL_CACHE",
                "Platform-dependent host symbol resolution is cached for the process lifetime in this unique bridge boundary."),
        ]),
    AnalysisExtension[],
    default_duplicate_code_settings(),
    default_resource_lifetime_settings(),
    default_security_settings(),
    default_coverage_settings(),
    default_documentation_settings(),
    CallRootSettings([
        CallRootEntryPoint(
            "odin-bridge:invoke_with_exception_diagnostics", :julia,
            "invoke_with_exception_diagnostics",
            "src/bridge/bootstrap.odin resolves this symbol through jl_get_function"),
        CallRootEntryPoint(
            "odin-bridge:init_euclid_scripts", :julia, "init_euclid_scripts",
            "src/bridge/bootstrap.odin resolves this symbol through jl_get_function"),
        CallRootEntryPoint(
            "odin-bridge:ensure_generation_animation_loaded", :julia,
            "ensure_generation_animation_loaded",
            "src/bridge/animations.odin resolves this symbol through jl_get_function"),
        CallRootEntryPoint(
            "odin-bridge:invoke_generation_harness_scenario", :julia,
            "invoke_generation_harness_scenario",
            "src/bridge/animations.odin resolves this symbol through jl_get_function"),
        CallRootEntryPoint(
            "odin-bridge:is_euclid_runtime_host", :julia,
            "is_euclid_runtime_host",
            "src/bridge/runtime_service.odin resolves this symbol through jl_get_function"),
        CallRootEntryPoint(
            "odin-bridge:global_euclid_loop", :julia, "global_euclid_loop",
            "src/bridge/bootstrap.odin resolves this symbol through jl_get_function")],
        ReviewedImportPolicy[]))