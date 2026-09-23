using OdinJuliaAnalysis

import OdinJuliaAnalysis: analyze_extension, extension_api_version, extension_id
import OdinJuliaAnalysis: extension_phases, extension_rules

const RAYLIB_BOUNDARY_RULE = "EUCLID-RAYLIB-BOUNDARY"
const RAYLIB_IMPORT_TARGETS = Set(("vendor:raylib", "vendor:raylib/rlgl"))

struct RaylibBoundaryExtension <: AnalysisExtension end

const RaylibOwnerPolicy = @NamedTuple begin
    path::String
    category::String
    count::Int
end

const RAYLIB_OWNER_POLICIES = RaylibOwnerPolicy[
    (path="src/audio/chalk.odin", category="audio", count=1),
    (path="src/audio/model/model.odin", category="audio", count=1),
    (path="src/view/core/copy_interaction.odin", category="subsystem drawing", count=1),
    (path="src/view/core/framebuffer_capture.odin", category="capture acquisition", count=1),
    (path="src/view/core/gif_capture.odin", category="capture acquisition", count=1),
    (path="src/view/core/icons.odin", category="subsystem drawing", count=1),
    (path="src/view/core/text.odin", category="subsystem drawing", count=1),
    (path="src/view/core/view_core.odin", category="subsystem drawing", count=1),
    (path="src/view/elements.odin", category="subsystem drawing", count=2),
    (path="src/view/font/finalize.odin", category="backend resource ownership", count=1),
    (path="src/view/font/font.odin", category="backend resource ownership", count=1),
    (path="src/view/font/model/model.odin", category="documented font/image compatibility requirement", count=1),
    (path="src/view/graphics/service.odin", category="backend resource ownership", count=1),
    (path="src/view/input/clipboard.odin", category="window/event shell", count=1),
    (path="src/view/input/device.odin", category="window/event shell", count=1),
    (path="src/view/loading.odin", category="window/event shell", count=1),
    (path="src/view/model/model.odin", category="backend resource ownership", count=1),
    (path="src/view/native/color.odin", category="subsystem drawing", count=1),
    (path="src/view/particles.odin", category="subsystem drawing", count=2),
    (path="src/view/startup_outline.odin", category="window/event shell", count=1),
    (path="src/view/terminal/geometry.odin", category="subsystem drawing", count=1),
    (path="src/view/terminal/input.odin", category="subsystem drawing", count=1),
    (path="src/view/terminal/lifecycle.odin", category="backend resource ownership", count=1),
    (path="src/view/terminal/links.odin", category="subsystem drawing", count=1),
    (path="src/view/terminal/render.odin", category="subsystem drawing", count=1),
    (path="src/view/terminal/terminal.odin", category="subsystem drawing", count=1),
    (path="src/view/terminal/text.odin", category="subsystem drawing", count=1),
    (path="src/view/terminal/types.odin", category="subsystem drawing", count=1),
    (path="src/view/terminal_service.odin", category="backend resource ownership", count=1),
    (path="src/view/ui/accordion.odin", category="subsystem drawing", count=1),
    (path="src/view/ui/animation_controls.odin", category="subsystem drawing", count=1),
    (path="src/view/ui/checkbox.odin", category="subsystem drawing", count=1),
    (path="src/view/ui/container.odin", category="subsystem drawing", count=1),
    (path="src/view/ui/dynview/dynview.odin", category="subsystem drawing", count=1),
    (path="src/view/ui/dynview/flow.odin", category="subsystem drawing", count=1),
    (path="src/view/ui/dynview/layout_draw.odin", category="subsystem drawing", count=1),
    (path="src/view/ui/dynview/selection.odin", category="subsystem drawing", count=1),
    (path="src/view/ui/gif_panel.odin", category="subsystem drawing", count=1),
    (path="src/view/ui/icon_button.odin", category="subsystem drawing", count=1),
    (path="src/view/ui/interaction.odin", category="subsystem drawing", count=1),
    (path="src/view/ui/layout.odin", category="subsystem drawing", count=1),
    (path="src/view/ui/list_item.odin", category="subsystem drawing", count=1),
    (path="src/view/ui/scroll.odin", category="subsystem drawing", count=1),
    (path="src/view/ui/settings_panel.odin", category="subsystem drawing", count=2),
    (path="src/view/ui/sliders.odin", category="subsystem drawing", count=1),
    (path="src/view/ui/splitter.odin", category="subsystem drawing", count=1),
    (path="src/view/ui/stack_panel.odin", category="subsystem drawing", count=1),
    (path="src/view/ui/terminal.odin", category="subsystem drawing", count=1),
    (path="src/view/ui/text_button.odin", category="subsystem drawing", count=1),
    (path="src/view/ui/text_panel.odin", category="subsystem drawing", count=1),
    (path="src/view/ui/tree_expander.odin", category="subsystem drawing", count=1),
    (path="src/view/ui/tree_panel.odin", category="subsystem drawing", count=1),
    (path="src/view/ui/ui.odin", category="subsystem drawing", count=1),
    (path="src/view/view.odin", category="window/event shell", count=2),
]

"""Return the stable Euclid Raylib-boundary extension identity."""
extension_id(_extension::RaylibBoundaryExtension) = "euclid-raylib-boundary"

"""Declare compatibility with the current trusted-extension API."""
extension_api_version(_extension::RaylibBoundaryExtension) = EXTENSION_API_VERSION

"""Register the blocking production Raylib import boundary rule."""
function extension_rules(_extension::RaylibBoundaryExtension)
    return RuleDefinition[
        RuleDefinition(
            RAYLIB_BOUNDARY_RULE,
            "odin",
            "Euclid Architecture > Backend Import Boundary",
            "parser-backed dependency inventory",
            "high",
            "default",
            false),
    ]
end

"""Run after parser-backed language dependency analysis is available."""
extension_phases(_extension::RaylibBoundaryExtension) = Set((AfterLanguageAnalysis,))

"""Normalize one repository path for platform-independent policy matching."""
normalize_boundary_path(path::AbstractString) = replace(String(path), '\\' => '/')

"""Report whether one source is a fixture rather than production code."""
function is_raylib_fixture(path::String)
    return endswith(path, "_test.odin") || startswith(path, "src/test_helpers/")
end

"""Construct one Raylib boundary diagnostic."""
function raylib_boundary_diagnostic(path, line, column, message)
    return Diagnostic(
        RAYLIB_BOUNDARY_RULE,
        Fail,
        path,
        line,
        column,
        message,
        nothing,
        nothing,
        "euclid-raylib-boundary")
end

"""Return exact production policy indexed by normalized source path."""
function raylib_owner_policy_by_path()
    return Dict(policy.path => policy for policy in RAYLIB_OWNER_POLICIES)
end

"""Classify one production Raylib dependency or report its missing owner."""
function classify_raylib_dependency!(
    diagnostics, counts, categories, policies, dependency)
    dependency.language == "odin" || return
    dependency.target in RAYLIB_IMPORT_TARGETS || return
    path = normalize_boundary_path(dependency.source_path)
    is_raylib_fixture(path) && return
    policy = get(policies, path, nothing)
    if policy === nothing
        push!(diagnostics, raylib_boundary_diagnostic(
            path,
            dependency.line,
            dependency.column,
            "Production Raylib/rlgl import has no classified display, input, audio, capture, or compatibility owner."))
        return
    end
    counts[path] += 1
    push!(get!(Vector{String}, categories, policy.category),
        "$(path):$(dependency.target)")
end

"""Report exact-count drift for every classified Raylib owner."""
function append_raylib_policy_drift!(diagnostics, counts)
    for policy in RAYLIB_OWNER_POLICIES
        actual = counts[policy.path]
        actual == policy.count && continue
        push!(diagnostics, raylib_boundary_diagnostic(
            policy.path,
            1,
            1,
            "Classified Raylib owner expected $(policy.count) import(s), found $(actual); update code and policy together."))
    end
end

"""Classify production Raylib imports and reject unowned or drifting dependencies."""
function analyze_extension(
    extension::RaylibBoundaryExtension,
    context::AnalysisContext,
    _prior_results)
    policies = raylib_owner_policy_by_path()
    counts = Dict(path => 0 for path in keys(policies))
    categories = Dict{String, Vector{String}}()
    diagnostics = Diagnostic[]
    for dependency in context.dependencies
        classify_raylib_dependency!(
            diagnostics, counts, categories, policies, dependency)
    end
    append_raylib_policy_drift!(diagnostics, counts)
    inventory = Dict(category => sort!(entries) for (category, entries) in categories)
    return ExtensionResult(
        extension_id(extension),
        context.phase;
        diagnostics,
        artifacts=Dict{String, Any}("allowed_imports_by_category" => inventory))
end
