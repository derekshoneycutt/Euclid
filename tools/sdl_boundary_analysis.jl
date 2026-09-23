using OdinJuliaAnalysis

import OdinJuliaAnalysis: analyze_extension, extension_api_version, extension_id
import OdinJuliaAnalysis: extension_phases, extension_rules

const SDL_BOUNDARY_RULE = "EUCLID-SDL-BOUNDARY"
const SDL_IMPORT_TARGET = "vendor:sdl3"

struct SdlBoundaryExtension <: AnalysisExtension end

const SdlOwnerPolicy = @NamedTuple begin
    path::String
    category::String
    count::Int
end

const SDL_OWNER_POLICIES = SdlOwnerPolicy[
    (path="src/view/native/color.odin", category="native color conversion", count=1),
    (path="src/view/native/sdl_draw_runtime.odin", category="GPU 2D renderer", count=1),
    (path="src/view/native/sdl_icon.odin", category="window icon", count=1),
    (path="src/view/native/sdl_platform.odin", category="window and GPU shell", count=1),
    (path="src/view/native/sdl_services.odin", category="platform services", count=1),
    (path="src/view/native/sdl_timing.odin", category="display timing", count=1),
    (path="src/view/input/clipboard.odin", category="system clipboard", count=1),
    (path="src/view/sdl_input.odin", category="input coordinator", count=1),
]

"""Return the stable Euclid SDL-boundary extension identity."""
extension_id(_extension::SdlBoundaryExtension) = "euclid-sdl-boundary"

"""Declare compatibility with the current trusted-extension API."""
extension_api_version(_extension::SdlBoundaryExtension) = EXTENSION_API_VERSION

"""Register the blocking production SDL import boundary rule."""
function extension_rules(_extension::SdlBoundaryExtension)
    return RuleDefinition[
        RuleDefinition(
            SDL_BOUNDARY_RULE,
            "odin",
            "Euclid Architecture > Backend Import Boundary",
            "parser-backed dependency inventory",
            "high",
            "default",
            false),
    ]
end

"""Run after parser-backed language dependency analysis is available."""
extension_phases(_extension::SdlBoundaryExtension) = Set((AfterLanguageAnalysis,))

"""Report whether one source is a fixture rather than production code."""
function is_sdl_fixture(path::String)
    return endswith(path, "_test.odin") || startswith(path, "src/test_helpers/") ||
        startswith(path, "tools/sdl3_probe/")
end

"""Construct one SDL boundary diagnostic."""
function sdl_boundary_diagnostic(path, line, column, message)
    return Diagnostic(
        SDL_BOUNDARY_RULE,
        Fail,
        path,
        line,
        column,
        message,
        nothing,
        nothing,
        "euclid-sdl-boundary")
end

"""Return exact production SDL policy indexed by normalized source path."""
function sdl_owner_policy_by_path()
    return Dict(policy.path => policy for policy in SDL_OWNER_POLICIES)
end

"""Classify one production SDL dependency or report its missing owner."""
function classify_sdl_dependency!(diagnostics, counts, categories, policies, dependency)
    dependency.language == "odin" || return
    dependency.target == SDL_IMPORT_TARGET || return
    path = normalize_boundary_path(dependency.source_path)
    is_sdl_fixture(path) && return
    policy = get(policies, path, nothing)
    if policy === nothing
        push!(diagnostics, sdl_boundary_diagnostic(
            path,
            dependency.line,
            dependency.column,
            "Production SDL import has no classified native display owner."))
        return
    end
    counts[path] += 1
    push!(get!(Vector{String}, categories, policy.category),
        "$(path):$(dependency.target)")
end

"""Report exact-count drift for every classified SDL owner."""
function append_sdl_policy_drift!(diagnostics, counts)
    for policy in SDL_OWNER_POLICIES
        actual = counts[policy.path]
        actual == policy.count && continue
        push!(diagnostics, sdl_boundary_diagnostic(
            policy.path,
            1,
            1,
            "Classified SDL owner expected $(policy.count) import(s), found $(actual); update code and policy together."))
    end
end

"""Classify production SDL imports and reject unowned or drifting dependencies."""
function analyze_extension(
    extension::SdlBoundaryExtension,
    context::AnalysisContext,
    _prior_results)
    policies = sdl_owner_policy_by_path()
    counts = Dict(path => 0 for path in keys(policies))
    categories = Dict{String, Vector{String}}()
    diagnostics = Diagnostic[]
    for dependency in context.dependencies
        classify_sdl_dependency!(diagnostics, counts, categories, policies, dependency)
    end
    append_sdl_policy_drift!(diagnostics, counts)
    inventory = Dict(category => sort!(entries) for (category, entries) in categories)
    return ExtensionResult(
        extension_id(extension),
        context.phase;
        diagnostics,
        artifacts=Dict{String, Any}("allowed_imports_by_category" => inventory))
end