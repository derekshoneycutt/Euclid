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
    "ODIN-ALLOCATION-IMPLICIT" => Warn,
    "ODIN-ALLOCATION-UNKNOWN" => Fail,
    "ODIN-ALLOCATION-CONTEXT" => Warn,
    "ODIN-ALLOCATION-HEAP" => Warn,
    "ODIN-ALLOCATION-ARENA" => Warn,
    "ODIN-ALLOCATION-HIDDEN" => Warn,
    "ODIN-ALLOCATION-POLICY-DRIFT" => Fail,
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
            "latex-plain-text",
            "src/julia/latex.jl",
            EuclidAnalysisRoots.EuclidLatex.latex_to_plain_text,
            (String,)),
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
        BaseSettings.allocations.source_patterns,
        ReviewedAllocationPolicy[
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
            ReviewedAllocationPolicy(
                "bridge-runtime-create-dynview",
                "src/bridge/runtime_service.odin",
                "create_julia_runtime_service",
                :implicit,
                "Single one-time creation of the julia runtime service structure.";
                operation="new",
                target="core.Dynview_System",
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
                "view-runtime-session-shapes-system",
                "src/view/runtime_session.odin",
                "make_point_system",
                :implicit,
                "Created once at startup with a definitive destruction at application end.";
                operation="new",
                target="Shapes_Point_System",
                certainty=:definite,
                response=Ignore),
            ReviewedAllocationPolicy(
                "view-runtime-session-particle-system",
                "src/view/runtime_session.odin",
                "initiate_animations_state",
                :implicit,
                "Created once at startup with a definitive destruction at application end.";
                operation="new",
                target="Particle_System",
                certainty=:definite,
                response=Ignore),
            ReviewedAllocationPolicy(
                "view-runtime-session-general-state",
                "src/view/runtime_session.odin",
                "initiate_animations_state",
                :implicit,
                "Created once at startup with a definitive destruction at application end.";
                operation="new",
                target="Euclid_General_State",
                certainty=:definite,
                response=Ignore),
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
            # Evidence export allocates only at an explicit durable-output boundary.
            ReviewedAllocationPolicy(
                "evidence-artifact-trace-buffer",
                "src/evidence/artifact/artifact.odin",
                "artifact_trace_bytes",
                :temporary,
                "Bounded serialized trace buffer owned by bundle export and deleted after the write completes.";
                operation="make",
                target="[]byte",
                allocator_source="context.temp_allocator",
                certainty=:definite,
                response=Ignore),
            # Test Allocations -- every site is a test fixture destroyed by defer free
            ReviewedAllocationPolicy(
                "test-evidence-allocation-baseline-buffer",
                "src/evidence/allocation/allocation_test.odin",
                "allocation_test_baseline_restoration",
                :custom,
                "Bounded test allocation explicitly deleted before the tracked domain is destroyed.";
                operation="make",
                target="[]byte",
                allocator_source="allocator",
                certainty=:definite,
                response=Ignore),
            ReviewedAllocationPolicy(
                "test-evidence-allocation-foreign-buffer",
                "src/evidence/allocation/allocation_test.odin",
                "allocation_test_bad_free_is_evidence",
                :context,
                "Bounded bad-free test fixture released by defer in the test body.";
                operation="make",
                target="[]byte",
                allocator_source="context.allocator",
                certainty=:definite,
                response=Ignore),
            ReviewedAllocationPolicy(
                "test-evidence-observe-display-state",
                "src/evidence/observe/observe_test.odin",
                "observe_test_display_scalars",
                :implicit,
                "Test fixture destroyed by defer free in the test body.";
                operation="new",
                target="app_core.Euclid_General_State",
                certainty=:definite,
                response=Ignore),
            ReviewedAllocationPolicy(
                "test-evidence-observe-point-system",
                "src/evidence/observe/observe_test.odin",
                "observe_test_display_scalars",
                :implicit,
                "Test fixture destroyed by defer free in the test body.";
                operation="new",
                target="app_core.Shapes_Point_System",
                certainty=:definite,
                response=Ignore),
            ReviewedAllocationPolicy(
                "test-evidence-observe-particle-system",
                "src/evidence/observe/observe_test.odin",
                "observe_test_display_scalars",
                :implicit,
                "Test fixture destroyed by defer free in the test body.";
                operation="new",
                target="app_core.Particle_System",
                certainty=:definite,
                response=Ignore),
            ReviewedAllocationPolicy(
                "test-evidence-observe-display-julia-service",
                "src/evidence/observe/observe_test.odin",
                "observe_test_display_scalars",
                :implicit,
                "Test fixture destroyed by defer free in the test body.";
                operation="new",
                target="app_core.Julia_Runtime_Service",
                certainty=:definite,
                response=Ignore),
            ReviewedAllocationPolicy(
                "test-evidence-observe-julia-host-service",
                "src/evidence/observe/observe_test.odin",
                "observe_test_julia_host_scalars",
                :implicit,
                "Test fixture destroyed by defer free in the test body.";
                operation="new",
                target="app_core.Julia_Runtime_Service",
                certainty=:definite,
                response=Ignore),
            ReviewedAllocationPolicy(
                "test-view-font-preparation-arena-pages",
                "src/view/font/font_test.odin",
                "view_test_preparation_arena_reuses_committed_pages",
                :custom,
                "Two bounded test buffers verify reuse of the dedicated preparation arena before its explicit destruction.";
                operation="make",
                target="[]u8",
                allocator_source="allocator",
                certainty=:definite,
                response=Ignore,
                minimum_matches=2,
                maximum_matches=2),
            ReviewedAllocationPolicy(
                "test-view-scenario-actions-state",
                "src/view/scenario_runtime_tests.odin",
                "scenario_runtime_actions_use_display_owned_state",
                :implicit,
                "Test fixture destroyed by defer free in the test body.";
                operation="new",
                target="Euclid_General_State",
                certainty=:definite,
                response=Ignore),
            ReviewedAllocationPolicy(
                "test-view-scenario-capture-state",
                "src/view/scenario_runtime_tests.odin",
                "scenario_runtime_waits_for_post_present_capture",
                :implicit,
                "Test fixture destroyed by defer free in the test body.";
                operation="new",
                target="Euclid_General_State",
                certainty=:definite,
                response=Ignore),
            ReviewedAllocationPolicy(
                "test-gif-encode-collect-gce-packed-bytes",
                "src/files/gif_encode_tests.odin",
                "collect_gce_packed_bytes",
                :temporary,
                "Test helper buffer on the temporary allocator, freed by test teardown.";
                operation="make",
                target="[]u8",
                certainty=:definite,
                response=Ignore),
            ReviewedAllocationPolicy(
                "test-particles-reserve-dead-low-prefers-dead",
                "src/particles/particles_tests.odin",
                "reserve_dead_low_particle_slot_prefers_dead_then_wraps",
                :implicit,
                "Test fixture destroyed by defer free in the test body.";
                operation="new",
                target="app_core.Particle_System",
                certainty=:definite,
                response=Ignore),
            ReviewedAllocationPolicy(
                "test-particles-reserve-dead-ring-advances",
                "src/particles/particles_tests.odin",
                "reserve_dead_particle_slot_ring_advances",
                :implicit,
                "Test fixture destroyed by defer free in the test body.";
                operation="new",
                target="app_core.Particle_System",
                certainty=:definite,
                response=Ignore),
            ReviewedAllocationPolicy(
                "test-particles-resolve-pair-no-collision",
                "src/particles/particles_tests.odin",
                "resolve_dust_pair_no_collision_keeps_state",
                :implicit,
                "Test fixture destroyed by defer free in the test body.";
                operation="new",
                target="app_core.Particle_System",
                certainty=:definite,
                response=Ignore),
            ReviewedAllocationPolicy(
                "test-particles-resolve-pair-approach-impulse",
                "src/particles/particles_tests.odin",
                "resolve_dust_pair_overlap_with_approach_applies_impulse",
                :implicit,
                "Test fixture destroyed by defer free in the test body.";
                operation="new",
                target="app_core.Particle_System",
                certainty=:definite,
                response=Ignore),
            ReviewedAllocationPolicy(
                "test-particles-resolve-pair-separating-skips",
                "src/particles/particles_tests.odin",
                "resolve_dust_pair_overlap_with_separating_velocity_skips_impulse",
                :implicit,
                "Test fixture destroyed by defer free in the test body.";
                operation="new",
                target="app_core.Particle_System",
                certainty=:definite,
                response=Ignore),
            ReviewedAllocationPolicy(
                "test-particles-resolve-pair-exact-overlap",
                "src/particles/particles_tests.odin",
                "resolve_dust_pair_exact_overlap_uses_deterministic_separation",
                :implicit,
                "Test fixture destroyed by defer free in the test body.";
                operation="new",
                target="app_core.Particle_System",
                certainty=:definite,
                response=Ignore),
            ReviewedAllocationPolicy(
                "test-particles-random-ranges-independent",
                "src/particles/particles_tests.odin",
                "particle_random_ranges_use_independent_seeded_generators",
                :implicit,
                "Test fixtures destroyed by defer free in the test body.";
                operation="new",
                target="app_core.Particle_System",
                certainty=:definite,
                response=Ignore,
                minimum_matches=2,
                maximum_matches=2),
            ReviewedAllocationPolicy(
                "test-particles-resolve-collisions-rotates-samples",
                "src/particles/particles_tests.odin",
                "resolve_dust_collisions_rotates_dense_bucket_samples",
                :implicit,
                "Test fixture destroyed by defer free in the test body.";
                operation="new",
                target="app_core.Particle_System",
                certainty=:definite,
                response=Ignore),
            ReviewedAllocationPolicy(
                "test-particles-reset-clears-runtime-state",
                "src/particles/particles_tests.odin",
                "reset_particles_clears_runtime_state_and_marks_all_slots_dead",
                :implicit,
                "Test fixture destroyed by defer free in the test body.";
                operation="new",
                target="app_core.Particle_System",
                certainty=:definite,
                response=Ignore),
            ReviewedAllocationPolicy(
                "test-particles-reserve-dead-low-wraps",
                "src/particles/particles_tests.odin",
                "reserve_dead_low_particle_slot_wraps_when_all_slots_alive",
                :implicit,
                "Test fixture destroyed by defer free in the test body.";
                operation="new",
                target="app_core.Particle_System",
                certainty=:definite,
                response=Ignore),
            ReviewedAllocationPolicy(
                "test-particles-emit-shapes-hide-burst",
                "src/particles/particles_tests.odin",
                "emit_shapes_hide_burst_spawns_dust_for_supported_shapes",
                :implicit,
                "Test fixture destroyed by defer free in the test body.";
                operation="new",
                target="app_core.Particle_System",
                certainty=:definite,
                response=Ignore),
            ReviewedAllocationPolicy(
                "test-particles-clamp-xy-bounds-bounces",
                "src/particles/particles_tests.odin",
                "clamp_xy_bounds_index_bounces_particles_back_inside_bounds",
                :implicit,
                "Test fixture destroyed by defer free in the test body.";
                operation="new",
                target="app_core.Particle_System",
                certainty=:definite,
                response=Ignore),
            ReviewedAllocationPolicy(
                "test-shapes-clear-animation-data",
                "src/shapes/system_tests.odin",
                "clear_animation_data_clears_animation_owned_slots",
                :implicit,
                "Test fixture destroyed by defer free in the test body.";
                operation="new",
                target="app_core.Particle_System",
                certainty=:definite,
                response=Ignore),
            ReviewedAllocationPolicy(
                "test-dynview-generation-slots-alternate",
                "src/view/dynview_tests.odin",
                "julia_interface_generation_slots_are_stable_and_alternate",
                :implicit,
                "Test fixture destroyed by defer free in the test body.";
                operation="new",
                certainty=:definite,
                response=Ignore),
            ReviewedAllocationPolicy(
                "test-dynview-snapshot-rejects-recycled-interface",
                "src/view/dynview_tests.odin",
                "view_snapshot_rejects_recycled_interface_pointer_from_old_generation",
                :implicit,
                "Test fixtures destroyed by defer free in the test body.";
                operation="new",
                certainty=:definite,
                response=Ignore,
                minimum_matches=3,
                maximum_matches=3),
            ReviewedAllocationPolicy(
                "test-dynview-batch-commits-point-positions",
                "src/view/dynview_tests.odin",
                "scene_command_batch_commits_point_positions_in_order",
                :implicit,
                "Test fixtures destroyed by defer free in the test body.";
                operation="new",
                certainty=:definite,
                response=Ignore,
                minimum_matches=4,
                maximum_matches=4),
            ReviewedAllocationPolicy(
                "test-dynview-batch-rejects-invalid-tail",
                "src/view/dynview_tests.odin",
                "scene_command_batch_rejects_invalid_tail_atomically",
                :implicit,
                "Test fixtures destroyed by defer free in the test body.";
                operation="new",
                certainty=:definite,
                response=Ignore,
                minimum_matches=4,
                maximum_matches=4),
            ReviewedAllocationPolicy(
                "test-dynview-batch-rejects-overflow-stale",
                "src/view/dynview_tests.odin",
                "scene_command_batch_rejects_overflow_and_stale_animation",
                :implicit,
                "Test fixtures destroyed by defer free in the test body.";
                operation="new",
                certainty=:definite,
                response=Ignore,
                minimum_matches=5,
                maximum_matches=5),
            ReviewedAllocationPolicy(
                "test-dynview-tick-reject-reason-classifies",
                "src/view/dynview_tests.odin",
                "animation_tick_reject_reason_classifies_stale_generation_and_sequence",
                :implicit,
                "Test fixtures destroyed by defer free in the test body.";
                operation="new",
                certainty=:definite,
                response=Ignore,
                minimum_matches=4,
                maximum_matches=4),
            ReviewedAllocationPolicy(
                "test-dynview-batch-defers-point-properties",
                "src/view/dynview_tests.odin",
                "scene_command_batch_defers_general_point_properties_until_commit",
                :implicit,
                "Test fixtures destroyed by defer free in the test body.";
                operation="new",
                certainty=:definite,
                response=Ignore,
                minimum_matches=4,
                maximum_matches=4),
            ReviewedAllocationPolicy(
                "test-dynview-batch-rejects-implicit-compass",
                "src/view/dynview_tests.odin",
                "scene_command_batch_rejects_invalid_implicit_compass_handle_atomically",
                :implicit,
                "Test fixtures destroyed by defer free in the test body.";
                operation="new",
                certainty=:definite,
                response=Ignore,
                minimum_matches=4,
                maximum_matches=4),
            ReviewedAllocationPolicy(
                "test-dynview-query-snapshot-immutable",
                "src/view/dynview_tests.odin",
                "animation_query_snapshot_is_immutable_during_worker_tick",
                :implicit,
                "Test fixtures destroyed by defer free in the test body.";
                operation="new",
                certainty=:definite,
                response=Ignore,
                minimum_matches=2,
                maximum_matches=2),
            ReviewedAllocationPolicy(
                "test-dynview-tick-rejects-stale-generation",
                "src/view/dynview_tests.odin",
                "animation_tick_rejects_stale_generation_and_sequence",
                :implicit,
                "Test fixtures destroyed by defer free in the test body.";
                operation="new",
                certainty=:definite,
                response=Ignore,
                minimum_matches=4,
                maximum_matches=4),
            ReviewedAllocationPolicy(
                "test-dynview-tick-coalescing-caps-backlog",
                "src/view/dynview_tests.odin",
                "animation_tick_coalescing_caps_backlog_without_queue_growth",
                :implicit,
                "Test fixture destroyed by defer free in the test body.";
                operation="new",
                certainty=:definite,
                response=Ignore),
            ReviewedAllocationPolicy(
                "test-dynview-runtime-failure-event-identity",
                "src/view/dynview_tests.odin",
                "julia_runtime_failure_event_records_request_identity",
                :implicit,
                "Test fixture destroyed by defer free in the test body.";
                operation="new",
                certainty=:definite,
                response=Ignore),
            ReviewedAllocationPolicy(
                "test-dynview-runtime-terminal-failure",
                "src/view/dynview_tests.odin",
                "julia_runtime_terminal_failure_does_not_report_stopped",
                :implicit,
                "Test fixture destroyed by defer free in the test body.";
                operation="new",
                certainty=:definite,
                response=Ignore),
            ReviewedAllocationPolicy(
                "test-dynview-runtime-diagnostics-failure",
                "src/view/dynview_tests.odin",
                "julia_runtime_diagnostics_report_failure_and_saturation",
                :implicit,
                "Test fixture destroyed by defer free in the test body.";
                operation="new",
                certainty=:definite,
                response=Ignore),
            ReviewedAllocationPolicy(
                "test-dynview-reload-failure-records-revision",
                "src/view/dynview_tests.odin",
                "julia_reload_failure_records_package_revision",
                :implicit,
                "Test fixture destroyed by defer free in the test body.";
                operation="new",
                certainty=:definite,
                response=Ignore),
            ReviewedAllocationPolicy(
                "test-dynview-snapshot-copy-preserves-spans",
                "src/view/dynview_tests.odin",
                "view_snapshot_copy_preserves_recursive_math_spans",
                :implicit,
                "Test fixtures destroyed by defer free in the test body.";
                operation="new",
                certainty=:definite,
                response=Ignore,
                minimum_matches=2,
                maximum_matches=2),
            ReviewedAllocationPolicy(
                "test-dynview-snapshot-validation-rejects",
                "src/view/dynview_tests.odin",
                "view_snapshot_validation_rejects_incomplete_streams",
                :implicit,
                "Test fixture destroyed by defer free in the test body.";
                operation="new",
                certainty=:definite,
                response=Ignore),
            ReviewedAllocationPolicy(
                "test-dynview-completed-snapshot-found",
                "src/view/dynview_tests.odin",
                "completed_view_snapshot_is_found_without_event_index",
                :implicit,
                "Test fixture destroyed by defer free in the test body.";
                operation="new",
                certainty=:definite,
                response=Ignore),
            ReviewedAllocationPolicy(
                "test-dynview-newest-snapshot-supersedes",
                "src/view/dynview_tests.odin",
                "newest_completed_view_snapshot_supersedes_older_completion",
                :implicit,
                "Test fixture destroyed by defer free in the test body.";
                operation="new",
                certainty=:definite,
                response=Ignore),
            ReviewedAllocationPolicy(
                "test-dynview-stale-snapshot-clears-commands",
                "src/view/dynview_tests.odin",
                "stale_view_snapshot_clears_previous_animation_commands",
                :implicit,
                "Test fixtures destroyed by defer free in the test body.";
                operation="new",
                certainty=:definite,
                response=Ignore,
                minimum_matches=5,
                maximum_matches=5),
            ReviewedAllocationPolicy(
                "test-dynview-text-span-script-attach-bounds",
                "src/view/dynview_tests.odin",
                "dynview_text_span_and_script_attach_helpers_respect_bounds",
                :implicit,
                "Test fixture destroyed by defer free in the test body.";
                operation="new",
                certainty=:definite,
                response=Ignore),
            ReviewedAllocationPolicy(
                "test-dynview-layout-prepare-style-placement",
                "src/view/dynview_tests.odin",
                "dynview_layout_prepare_style_placement_forces_line_break_and_indent",
                :implicit,
                "Test fixture destroyed by defer free in the test body.";
                operation="new",
                certainty=:definite,
                response=Ignore),
            ReviewedAllocationPolicy(
                "test-dynview-layout-push-item-metadata",
                "src/view/dynview_tests.odin",
                "dynview_layout_push_item_records_block_and_column_metadata",
                :implicit,
                "Test fixture destroyed by defer free in the test body.";
                operation="new",
                certainty=:definite,
                response=Ignore),
            ReviewedAllocationPolicy(
                "test-dynview-layout-consume-text-run-wraps",
                "src/view/dynview_tests.odin",
                "dynview_layout_consume_text_run_wraps_and_places_segments",
                :implicit,
                "Test fixtures destroyed by defer free in the test body.";
                operation="new",
                certainty=:definite,
                response=Ignore,
                minimum_matches=2,
                maximum_matches=2),
            ReviewedAllocationPolicy(
                "test-dynview-measure-math-aggregates-children",
                "src/view/dynview_tests.odin",
                "dynview_measure_math_program_aggregates_child_metrics",
                :implicit,
                "Test fixtures destroyed by defer free in the test body.";
                operation="new",
                certainty=:definite,
                response=Ignore,
                minimum_matches=2,
                maximum_matches=2),
            ReviewedAllocationPolicy(
                "test-dynview-measure-math-rejects-invalid",
                "src/view/dynview_tests.odin",
                "dynview_measure_math_program_rejects_invalid_shapes",
                :implicit,
                "Test fixtures destroyed by defer free in the test body.";
                operation="new",
                certainty=:definite,
                response=Ignore,
                minimum_matches=2,
                maximum_matches=2),
            ReviewedAllocationPolicy(
                "test-dynview-measure-math-sums-widths",
                "src/view/dynview_tests.odin",
                "dynview_measure_math_program_sums_multiple_command_widths",
                :implicit,
                "Test fixtures destroyed by defer free in the test body.";
                operation="new",
                certainty=:definite,
                response=Ignore,
                minimum_matches=2,
                maximum_matches=2),
            ReviewedAllocationPolicy(
                "test-dynview-reset-cache-clears-layout",
                "src/view/dynview_tests.odin",
                "dynview_reset_cache_clears_layout_state",
                :implicit,
                "Test fixture destroyed by defer free in the test body.";
                operation="new",
                certainty=:definite,
                response=Ignore),
            ReviewedAllocationPolicy(
                "test-gif-capture-status-note-truncation",
                "src/view/gif_capture_tests.odin",
                "clear_and_set_gif_status_note_handles_truncation",
                :implicit,
                "Test fixture destroyed by defer free in the test body.";
                operation="new",
                target="app_core.Euclid_Ui_Runtime_State",
                certainty=:definite,
                response=Ignore),
            ReviewedAllocationPolicy(
                "test-gif-capture-last-path-truncation",
                "src/view/gif_capture_tests.odin",
                "clear_and_set_last_gif_path_handles_truncation",
                :implicit,
                "Test fixture destroyed by defer free in the test body.";
                operation="new",
                target="app_core.Euclid_Ui_Runtime_State",
                certainty=:definite,
                response=Ignore),
            ReviewedAllocationPolicy(
                "test-gif-capture-cycle-boundary-consumes-once",
                "src/view/gif_capture_tests.odin",
                "gif_capture_consume_cycle_boundary_consumes_once_per_generation",
                :implicit,
                "Test fixture destroyed by defer free in the test body.";
                operation="new",
                target="app_core.Euclid_General_State",
                certainty=:definite,
                response=Ignore),
            ReviewedAllocationPolicy(
                "test-gif-capture-batch-splits-hide-points",
                "src/view/gif_capture_tests.odin",
                "scene_command_batch_splits_large_hide_point_batches",
                :implicit,
                "Test fixtures destroyed by defer free in the test body.";
                operation="new",
                certainty=:definite,
                response=Ignore,
                minimum_matches=4,
                maximum_matches=4),
            ReviewedAllocationPolicy(
                "test-sim-executor-fixed-step-advances-identity",
                "src/view/simulation_executor_tests.odin",
                "deterministic_fixed_step_advances_identity_after_worker_join",
                :implicit,
                "Test fixtures destroyed by defer free in the test body.";
                operation="new",
                certainty=:definite,
                response=Ignore,
                minimum_matches=3,
                maximum_matches=3),
            ReviewedAllocationPolicy(
                "test-sim-executor-fixed-step-emits-snapshot",
                "src/view/simulation_executor_tests.odin",
                "deterministic_fixed_step_emits_post_join_checkpoint_snapshot",
                :implicit,
                "Test fixtures destroyed by defer free in the test body.";
                operation="new",
                certainty=:definite,
                response=Ignore,
                minimum_matches=4,
                maximum_matches=4),
            ReviewedAllocationPolicy(
                "test-sim-executor-parallel-step-joins-updates",
                "src/view/simulation_executor_tests.odin",
                "parallel_simulation_step_joins_particle_and_constraint_updates",
                :implicit,
                "Test fixtures destroyed by defer free in the test body.";
                operation="new",
                certainty=:definite,
                response=Ignore,
                minimum_matches=3,
                maximum_matches=3),
            ReviewedAllocationPolicy(
                "test-sim-executor-frame-prep-joins-caches",
                "src/view/simulation_executor_tests.odin",
                "parallel_frame_preparation_joins_shape_and_dynview_cache_updates",
                :implicit,
                "Test fixtures destroyed by defer free in the test body.";
                operation="new",
                certainty=:definite,
                response=Ignore,
                minimum_matches=2,
                maximum_matches=2),
            ]),
    ReportSettings(
        BaseSettings.report.color,
        BaseSettings.report.warning_limit,
        BaseSettings.report.report_limit;
        staging_maximum_response=Ignore),
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
            "the scratchpad REPL evaluates this command from user input")],
        ReviewedImportPolicy[]))