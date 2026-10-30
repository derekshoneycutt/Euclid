module EuclidShaders

using SHA
using TOML

export ShaderAbi, ShaderArtifacts, ShaderSpec, build_shaders, compile_command,
    dxil_command, msl_command, reflection_command, runtime_artifact_name,
    runtime_shader_entrypoint, runtime_shader_format, shader_abis, shader_specs,
    validate_pipeline_contracts, validate_reflection, validate_spirv_abi,
    windows_shadercross_manifest, windows_shadercross_runtime_dirs,
    linux_shadercross_manifest, macos_shadercross_manifest

const SHADER_SCHEMA_VERSION = 1
const MSL_VERSION = "2.0.0"
const SHADERCROSS_ENV = "EUCLID_SHADERCROSS"
const REPOSITORY_ROOT = normpath(joinpath(@__DIR__, ".."))
const WINDOWS_SDL_DIR = joinpath(REPOSITORY_ROOT, "libs", "sdl", "bin", "win64")
const WINDOWS_SHADERCROSS_DIR = joinpath(
    REPOSITORY_ROOT, "libs", "sdl_shadercross", "bin", "win64")
const WINDOWS_SHADERCROSS_ARTIFACTS = Set([
    "shadercross.exe", "SDL3_shadercross.dll", "spirv-cross-c-shared.dll",
    "dxcompiler.dll", "dxil.dll", "spirv-val.exe", "spirv-dis.exe"])
const WINDOWS_SHADERCROSS_COMPONENTS = Set([
    "SDL_shadercross", "SPIRV-Cross", "DirectXShaderCompiler",
    "SPIRV-Tools", "SPIRV-Headers"])
const WINDOWS_SHADERCROSS_SOURCE_DEPENDENCIES = Set([
    "DirectX-Headers", "DXC-SPIRV-Headers", "DXC-SPIRV-Tools"])
const STATIC_SHADERCROSS_COMPONENTS = union(
    WINDOWS_SHADERCROSS_COMPONENTS, Set(["SDL3"]))

struct ShaderBuildTools
    compiler::String
    validator::String
    disassembler::String
end

"""Return DLL directories required by the repository Windows shadercross CLI."""
function windows_shadercross_runtime_dirs(
    repository_root::String=REPOSITORY_ROOT)
    return [
        joinpath(repository_root, "libs", "sdl", "bin", "win64"),
        joinpath(repository_root, "libs", "sdl_shadercross", "bin", "win64"),
    ]
end

"""Read the explicit upstream source pin independently of Git or submodules."""
function repository_shadercross_commit(repository_root::String)
    path = joinpath(repository_root, "libs", "sdl_shadercross", "source-pin.toml")
    isfile(path) || error("Missing SDL_shadercross source pin at $path")
    commit = String(get(TOML.parsefile(path), "source_commit", ""))
    occursin(r"^[0-9a-f]{40}$", commit) || error(
        "SDL_shadercross source pin has an invalid commit.")
    return commit
end

"""Validate fixed Windows shadercross manifest platform fields."""
function validate_shadercross_platform(
    manifest::AbstractDict, architecture::Symbol)
    get(manifest, "schema_version", 0) == 1 || error(
        "Unsupported Windows SDL_shadercross manifest schema.")
    get(manifest, "platform", "") == "windows" || error(
        "Windows SDL_shadercross manifest has the wrong platform.")
    expected_architecture = architecture == :x86_64 ?
        "x86_64" : string(architecture)
    get(manifest, "architecture", "") == expected_architecture || error(
        "Windows SDL_shadercross manifest does not support $expected_architecture.")
    get(manifest, "toolchain", "") == "msvc" || error(
        "Windows SDL_shadercross manifest must use the MSVC toolchain.")
    get(manifest, "provider", "") == "euclid-built" || error(
        "Windows SDL_shadercross manifest has an unknown provider.")
end

"""Validate Windows shadercross manifest metadata and repository identity."""
function validate_shadercross_manifest_header(manifest::AbstractDict,
    root::AbstractString, architecture::Symbol,
    expected_source_commit::Union{Nothing,String})
    validate_shadercross_platform(manifest, architecture)
    source_commit = String(get(manifest, "source_commit", ""))
    occursin(r"^[0-9a-f]{40}$", source_commit) || error(
        "Windows SDL_shadercross manifest has an invalid source commit.")
    expected_source_commit === nothing ||
        source_commit == expected_source_commit || error(
            "Windows SDL_shadercross payload does not match the repository source pin.")
    sdl_manifest = normpath(joinpath(root,
        String(get(manifest, "sdl_manifest", ""))))
    isfile(sdl_manifest) || error(
        "Windows SDL_shadercross manifest references a missing SDL provider.")
end

"""Validate and register one shadercross binary artifact."""
function validate_shadercross_artifact!(artifact::AbstractDict,
    artifact_names::Set{String}, root::AbstractString,
    hash_file::Function, file_size::Function)
    filename = String(get(artifact, "file", ""))
    filename in artifact_names && error(
        "Duplicate SDL_shadercross artifact: $filename")
    push!(artifact_names, filename)
    path = joinpath(root, filename)
    isfile(path) || error("Missing SDL_shadercross artifact: $filename")
    file_size(path) == get(artifact, "bytes", -1) || error(
        "SDL_shadercross artifact size mismatch: $filename")
    hash_file(path) == get(artifact, "sha256", "") || error(
        "SDL_shadercross artifact hash mismatch: $filename")
end

"""Validate shadercross source dependencies and return their names."""
function validate_shadercross_source_dependencies!(manifest::AbstractDict,
    root::AbstractString, hash_file::Function)
    source_dependencies = get(manifest, "source_dependency", Any[])
    source_dependency_names = Set(String(get(dependency, "name", ""))
        for dependency in source_dependencies)
    source_dependency_names == WINDOWS_SHADERCROSS_SOURCE_DEPENDENCIES || error(
        "SDL_shadercross manifest has incomplete source dependencies.")
    all(dependency -> occursin(r"^[0-9a-f]{40}$",
        String(get(dependency, "source_commit", ""))),
        source_dependencies) || error(
        "SDL_shadercross manifest has an invalid dependency commit.")
    for dependency in source_dependencies
        name = String(get(dependency, "name", ""))
        license_path = joinpath(root,
            String(get(dependency, "license_file", "")))
        isfile(license_path) || error(
            "Missing SDL_shadercross dependency license for $name.")
        hash_file(license_path) == get(dependency, "license_sha256", "") || error(
            "SDL_shadercross dependency license hash mismatch for $name.")
    end
    return source_dependency_names
end

"""Validate one platform's shadercross component and append its inventory."""
function validate_shadercross_component!(component::AbstractDict,
    allowed_dependencies::Set{String}, artifact_names::Set{String},
    root::AbstractString, hash_file::Function, file_size::Function)
    name = String(get(component, "name", ""))
    isempty(name) && error(
        "SDL_shadercross manifest contains an unnamed component.")
    occursin(r"^[0-9a-f]{40}$", String(get(component, "source_commit", ""))) ||
        error("SDL_shadercross manifest has an invalid commit for $name.")
    all(dependency -> dependency in allowed_dependencies,
        String.(get(component, "dependencies", String[]))) || error(
        "SDL_shadercross manifest has an unknown dependency for $name.")
    license_path = joinpath(root, String(get(component, "license_file", "")))
    isfile(license_path) || error("Missing SDL_shadercross license for $name.")
    hash_file(license_path) == get(component, "license_sha256", "") || error(
        "SDL_shadercross license hash mismatch for $name.")
    for artifact in get(component, "artifact", Any[])
        validate_shadercross_artifact!(
            artifact, artifact_names, root, hash_file, file_size)
    end
end

"""Validate and return the repository-owned Windows shadercross manifest."""
function windows_shadercross_manifest(
    root::AbstractString=WINDOWS_SHADERCROSS_DIR;
    architecture::Symbol=Sys.ARCH,
    expected_source_commit::Union{Nothing,String}=nothing,
    parse_file::Function=TOML.parsefile,
    hash_file::Function=path -> bytes2hex(open(sha256, path)),
    file_size::Function=filesize)
    manifest_path = joinpath(normpath(root), "manifest.toml")
    isfile(manifest_path) || error(
        "Missing Windows SDL_shadercross manifest at $manifest_path")
    manifest = parse_file(manifest_path)
    validate_shadercross_manifest_header(
        manifest, root, architecture, expected_source_commit)
    components = get(manifest, "component", Any[])
    component_names = Set(String(get(component, "name", "")) for component in components)
    length(component_names) == length(components) || error(
        "Windows SDL_shadercross manifest contains duplicate components.")
    component_names == WINDOWS_SHADERCROSS_COMPONENTS || error(
        "Windows SDL_shadercross manifest has an incomplete component inventory.")
    shadercross = only(filter(component -> component["name"] == "SDL_shadercross", components))
    shadercross["source_commit"] == manifest["source_commit"] || error(
        "SDL_shadercross component does not match the manifest source commit.")
    source_names = validate_shadercross_source_dependencies!(manifest, root, hash_file)
    allowed_dependencies = union(component_names, source_names, Set(["SDL3"]))
    artifact_names = Set{String}()
    for component in components
        validate_shadercross_component!(component, allowed_dependencies,
            artifact_names, root, hash_file, file_size)
    end
    artifact_names == WINDOWS_SHADERCROSS_ARTIFACTS || error(
        "Windows SDL_shadercross manifest has an incomplete artifact inventory.")
    return manifest
end

"""Validate and return one checked-in Windows shadercross artifact."""
function windows_shadercross_artifact(repository_root::String, filename::String)
    root = joinpath(repository_root, "libs", "sdl_shadercross", "bin", "win64")
    windows_shadercross_manifest(root;
        expected_source_commit=repository_shadercross_commit(repository_root))
    return realpath(joinpath(root, filename))
end

include(joinpath(@__DIR__, "shadercross_linux.jl"))
include(joinpath(@__DIR__, "shadercross_macos.jl"))

struct ShaderSpec
    name::String
    source::String
    stage::String
    uniform_buffers::Int
    samplers::Int
    inputs::Vector{Pair{Int,String}}
    outputs::Vector{Pair{Int,String}}
end

struct ShaderArtifacts
    directory::String
    manifest_path::String
end

struct ShaderAbi
    uniform_struct::String
    uniform_size::Int
    uniform_offsets::Vector{Int}
    array_stride::Int
    descriptor_sets::Vector{Int}
    vertex_bindings::Vector{Int}
    vertex_offsets::Vector{Int}
    vertex_strides::Vector{Int}
end

struct ShaderCommandResult
    exit_code::Int
    output::String
    error_output::String
end

"""Return 2D drawing and final-composition shader contracts."""
function draw2d_shader_specs(shader_root::String)
    return ShaderSpec[
        ShaderSpec("draw2d_colored.vert",
            joinpath(shader_root, "draw2d_colored.vert.hlsl"),
            "vertex", 1, 0,
            [0 => "float2", 2 => "float4"], [0 => "float4"]),
        ShaderSpec("draw2d_colored.frag",
            joinpath(shader_root, "draw2d_colored.frag.hlsl"),
            "fragment", 0, 0,
            [0 => "float4"], [0 => "float4"]),
        ShaderSpec("draw2d_textured.vert",
            joinpath(shader_root, "draw2d_textured.vert.hlsl"),
            "vertex", 1, 0,
            [0 => "float2", 1 => "float2", 2 => "float4"],
            [0 => "float2", 1 => "float4"]),
        ShaderSpec("draw2d_textured.frag",
            joinpath(shader_root, "draw2d_textured.frag.hlsl"),
            "fragment", 0, 1,
            [0 => "float2", 1 => "float4"], [0 => "float4"]),
        ShaderSpec("magnifier.vert",
            joinpath(shader_root, "magnifier.vert.hlsl"),
            "vertex", 0, 0, Pair{Int,String}[], [0 => "float2"]),
        ShaderSpec("magnifier.frag",
            joinpath(shader_root, "magnifier.frag.hlsl"),
            "fragment", 1, 2, [0 => "float2"], [0 => "float4"]),
    ]
end

"""Return the complete ordered shader interface contract."""
function shader_specs(source_root::String)
    shader_root = joinpath(source_root, "view", "shaders")
    return vcat(draw2d_shader_specs(shader_root), ShaderSpec[
        ShaderSpec("stroke3d.vert", joinpath(shader_root, "stroke3d.vert.hlsl"),
            "vertex", 1, 0,
            [0 => "float3", 1 => "float2", 2 => "float4"],
            [0 => "float2", 1 => "float4"]),
        ShaderSpec("stroke3d.frag", joinpath(shader_root, "stroke3d.frag.hlsl"),
            "fragment", 1, 0,
            [0 => "float2", 1 => "float4"], [0 => "float4"]),
        ShaderSpec("dust_instanced.vert",
            joinpath(shader_root, "dust_instanced.vert.hlsl"),
            "vertex", 1, 0,
            [0 => "float2", 1 => "float2", 2 => "float3", 3 => "float4",
                4 => "float"],
            [0 => "float2", 1 => "float4", 2 => "float"]),
        ShaderSpec("dust_instanced.frag",
            joinpath(shader_root, "dust_instanced.frag.hlsl"),
            "fragment", 0, 1,
            [0 => "float2", 1 => "float4", 2 => "float"], [0 => "float4"]),
        ShaderSpec("leaper_light.frag",
            joinpath(shader_root, "leaper_light.frag.hlsl"),
            "fragment", 0, 0,
            [0 => "float2", 1 => "float4", 2 => "float"], [0 => "float4"]),
    ])
end

"""Return fixed CPU/GPU layout contracts keyed by shader name."""
function shader_abis()
    return Dict(
        "draw2d_colored.vert" => ShaderAbi("Draw2DVertexUniforms", 16, [0, 8],
            0, [1], [0, 0], [0, 16], [24, 24]),
        "draw2d_colored.frag" => ShaderAbi(
            "", 0, Int[], 0, Int[], Int[], Int[], Int[]),
        "draw2d_textured.vert" => ShaderAbi("Draw2DVertexUniforms", 16, [0, 8],
            0, [1], [0, 0, 0], [0, 8, 16], [24, 24, 24]),
        "draw2d_textured.frag" => ShaderAbi(
            "", 0, Int[], 0, [2, 2], Int[], Int[], Int[]),
        "magnifier.vert" => ShaderAbi(
            "", 0, Int[], 0, Int[], Int[], Int[], Int[]),
        "magnifier.frag" => ShaderAbi(
            "MagnifierUniforms", 48, [0, 16, 24, 32, 36, 40, 44],
            0, [2, 2, 2, 2, 3], Int[], Int[], Int[]),
        "stroke3d.vert" => ShaderAbi("StrokeVertexUniforms", 64, [0], 0,
            [1], [0, 0, 0], [0, 12, 20], [36, 36, 36]),
        "stroke3d.frag" => ShaderAbi("StrokeFragmentUniforms", 192,
            [0, 12, 16, 20, 24, 28, 32, 36, 40, 44, 48, 56, 64, 76,
                80, 84, 88, 92, 96, 128, 160],
            16, [3], Int[], Int[], Int[]),
        "dust_instanced.vert" => ShaderAbi("DustVertexUniforms", 16, [0, 8], 0,
            [1], [0, 0, 1, 1, 1], [0, 8, 0, 12, 28], [16, 16, 32, 32, 32]),
        "dust_instanced.frag" => ShaderAbi("", 0, Int[], 0,
            [2, 2], Int[], Int[], Int[]),
        "leaper_light.frag" => ShaderAbi(
            "", 0, Int[], 0, Int[], Int[], Int[], Int[]))
end

"""Validate cross-stage interfaces and fixed vertex-record contracts."""
function validate_pipeline_contracts(specs::Vector{ShaderSpec}, abis=shader_abis())
    by_name = Dict(spec.name => spec for spec in specs)
    by_name["draw2d_colored.vert"].outputs ==
        by_name["draw2d_colored.frag"].inputs ||
        error("Colored 2D stage interface mismatch.")
    by_name["draw2d_textured.vert"].outputs ==
        by_name["draw2d_textured.frag"].inputs ||
        error("Textured 2D stage interface mismatch.")
    by_name["magnifier.vert"].outputs ==
        by_name["magnifier.frag"].inputs ||
        error("Magnifier stage interface mismatch.")
    by_name["stroke3d.vert"].outputs == by_name["stroke3d.frag"].inputs ||
        error("Stroke stage interface mismatch.")
    by_name["dust_instanced.vert"].outputs ==
        by_name["dust_instanced.frag"].inputs ||
        error("Dust stage interface mismatch.")
    by_name["dust_instanced.vert"].outputs ==
        by_name["leaper_light.frag"].inputs ||
        error("Leaper light stage interface mismatch.")
    dust = abis["dust_instanced.vert"]
    all(dust.vertex_strides[index] == (dust.vertex_bindings[index] == 1 ? 32 : 16)
        for index in eachindex(dust.vertex_bindings)) ||
        error("Dust vertex-record stride mismatch.")
    draw_abis = [abis["draw2d_colored.vert"], abis["draw2d_textured.vert"]]
    all(all(==(24), abi.vertex_strides) for abi in draw_abis) ||
        error("2D vertex-record stride mismatch.")
    return true
end

"""Construct one canonical HLSL-to-SPIR-V shadercross command."""
function compile_command(tool::String, spec::ShaderSpec, output::String)
    return Cmd([tool, spec.source, "--source", "HLSL", "--dest", "SPIRV",
        "--stage", spec.stage, "--entrypoint", "main", "--output", output])
end

"""Construct one canonical SPIR-V-to-MSL shadercross command."""
function msl_command(
    tool::String, spec::ShaderSpec, spirv::String, output::String)
    return Cmd([tool, spirv, "--source", "SPIRV", "--dest", "MSL",
        "--stage", spec.stage, "--entrypoint", "main",
        "--msl-version", MSL_VERSION, "--output", output])
end

"""Construct one canonical SPIR-V-to-DXIL shadercross command."""
function dxil_command(
    tool::String, spec::ShaderSpec, spirv::String, output::String)
    return Cmd([tool, spirv, "--source", "SPIRV", "--dest", "DXIL",
        "--stage", spec.stage, "--entrypoint", "main", "--output", output])
end

"""Return the packaged runtime shader format for one host kernel."""
function runtime_shader_format(kernel::Symbol=Sys.KERNEL)
    kernel == :Linux && return "SPIR-V"
    kernel == :Darwin && return "MSL"
    kernel == :NT && return "DXIL"
    error("Runtime shader generation is unsupported on $kernel.")
end

"""Return the SDL GPU entrypoint for one host kernel."""
function runtime_shader_entrypoint(kernel::Symbol=Sys.KERNEL)
    kernel == :Linux && return "main"
    kernel == :Darwin && return "main0"
    kernel == :NT && return "main"
    error("Runtime shader generation is unsupported on $kernel.")
end

"""Return the packaged runtime artifact name for one shader."""
function runtime_artifact_name(spec::ShaderSpec, kernel::Symbol=Sys.KERNEL)
    extension = kernel == :Linux ? "spv" :
        kernel == :Darwin ? "msl" :
        kernel == :NT ? "dxil" :
        error("Runtime shader generation is unsupported on $kernel.")
    return "$(spec.name).$extension"
end

"""Construct one canonical SPIR-V reflection command."""
function reflection_command(
    tool::String, spec::ShaderSpec, spirv::String, output::String)
    return Cmd([tool, spirv, "--source", "SPIRV", "--dest", "JSON",
        "--stage", spec.stage, "--entrypoint", "main", "--output", output])
end

"""Capture one subprocess without inheriting terminal output."""
function capture_command(command::Cmd)
    if Sys.iswindows()
        runtime_path = join(windows_shadercross_runtime_dirs(), ';')
        command = addenv(command, "PATH" => string(
            runtime_path, ';', get(ENV, "PATH", "")))
    end
    output = IOBuffer()
    error_output = IOBuffer()
    process = run(pipeline(
        ignorestatus(command), stdout=output, stderr=error_output))
    return ShaderCommandResult(
        process.exitcode, String(take!(output)), String(take!(error_output)))
end

"""Require one build-only executable from an override or PATH."""
function resolve_tool(name::String; environment_name::String="")
    override = isempty(environment_name) ? "" : get(ENV, environment_name, "")
    path = isempty(override) ? Sys.which(name) : override
    if path === nothing
        hint = isempty(environment_name) ? "Install it on PATH." :
            "Install it on PATH or set $environment_name to its executable path."
        error("$name is required for offline shader generation. $hint")
    end
    isfile(path) || error("Missing $name executable at $path")
    return realpath(path)
end

"""Resolve an override or the platform's verified binary build-tool provider."""
function resolve_shadercross(repository_root::String)
    override = get(ENV, SHADERCROSS_ENV, "")
    isempty(override) || return resolve_tool(
        "shadercross"; environment_name=SHADERCROSS_ENV)
    Sys.iswindows() && return windows_shadercross_artifact(
        repository_root, "shadercross.exe")
    Sys.islinux() && return linux_shadercross_artifact(
        repository_root, "shadercross")
    Sys.isapple() && return macos_shadercross_artifact(repository_root, "shadercross")
    error("SDL_shadercross binary provider is unsupported on $(Sys.KERNEL).")
end

"""Resolve one verified SPIRV-Tools executable from the binary provider."""
function resolve_bundled_spirv_tool(repository_root::String, name::String)
    executable = Sys.iswindows() ? "$name.exe" : name
    Sys.iswindows() && return windows_shadercross_artifact(
        repository_root, executable)
    Sys.islinux() && return linux_shadercross_artifact(repository_root, executable)
    Sys.isapple() && return macos_shadercross_artifact(repository_root, executable)
    error("SPIRV-Tools binary provider is unsupported on $(Sys.KERNEL).")
end

"""Run one checked shader build command."""
function checked_command(command::Cmd, stage::String)
    result = capture_command(command)
    result.exit_code == 0 || error(
        "$stage failed: $(strip(result.error_output))")
    return nothing
end

"""Compile a second artifact and reject nondeterministic shader output."""
function verify_reproducible_artifact(
    tool::String, spec::ShaderSpec, artifact::String)
    comparison = artifact * ".repro"
    try
        checked_command(
            compile_command(tool, spec, comparison), "$(spec.name) reproduction")
        file_sha256(comparison) == file_sha256(artifact) ||
            error("$(spec.name) artifact is not reproducible.")
    finally
        rm(comparison; force=true)
    end
    return nothing
end

"""Compile a second MSL artifact and reject nondeterministic output."""
function verify_reproducible_msl(
    tool::String, spec::ShaderSpec, spirv::String, artifact::String)
    comparison = artifact * ".repro"
    try
        checked_command(msl_command(tool, spec, spirv, comparison),
            "$(spec.name) MSL reproduction")
        file_sha256(comparison) == file_sha256(artifact) ||
            error("$(spec.name) MSL artifact is not reproducible.")
    finally
        rm(comparison; force=true)
    end
    return nothing
end

"""Compile a second DXIL artifact and reject nondeterministic output."""
function verify_reproducible_dxil(
    tool::String, spec::ShaderSpec, spirv::String, artifact::String)
    comparison = artifact * ".repro"
    try
        checked_command(dxil_command(tool, spec, spirv, comparison),
            "$(spec.name) DXIL reproduction")
        file_sha256(comparison) == file_sha256(artifact) ||
            error("$(spec.name) DXIL artifact is not reproducible.")
    finally
        rm(comparison; force=true)
    end
    return nothing
end

"""Extract one numeric field from shadercross's fixed reflection protocol."""
function reflection_count(document::String, field::String)
    match_result = match(Regex("\\\"$field\\\"\\s*:\\s*(\\d+)"), document)
    match_result === nothing && error("Reflection is missing $field.")
    return parse(Int, only(match_result.captures))
end

"""Extract one reflected stage-interface array as location/type pairs."""
function reflection_interface(document::String, field::String)
    array_match = match(
        Regex("\\\"$field\\\"\\s*:\\s*\\[(.*?)\\]"), document)
    array_match === nothing && error("Reflection is missing $field.")
    entries = Pair{Int,String}[]
    pattern = r"\"type\"\s*:\s*\"([^\"]+)\"\s*,\s*\"location\"\s*:\s*(\d+)"
    for entry in eachmatch(pattern, only(array_match.captures))
        push!(entries, parse(Int, entry.captures[2]) => entry.captures[1])
    end
    sort!(entries; by=first)
    return entries
end

"""Validate reflected resources and stage interfaces against one contract."""
function validate_reflection(spec::ShaderSpec, document::String)
    reflection_count(document, "uniform_buffers") == spec.uniform_buffers ||
        error("$(spec.name) uniform-buffer contract mismatch.")
    reflection_count(document, "samplers") == spec.samplers ||
        error("$(spec.name) sampler contract mismatch.")
    reflection_count(document, "storage_textures") == 0 ||
        error("$(spec.name) unexpectedly uses storage textures.")
    reflection_count(document, "storage_buffers") == 0 ||
        error("$(spec.name) unexpectedly uses storage buffers.")
    reflection_interface(document, "inputs") == spec.inputs ||
        error("$(spec.name) input contract mismatch.")
    reflection_interface(document, "outputs") == spec.outputs ||
        error("$(spec.name) output contract mismatch.")
    return true
end

"""Validate uniform offsets and array stride from SPIR-V disassembly."""
function validate_spirv_abi(spec::ShaderSpec, abi::ShaderAbi, document::String)
    entry_stage = spec.stage == "vertex" ? "Vertex" : "Fragment"
    occursin(Regex("OpEntryPoint\\s+$entry_stage\\s+%\\w+\\s+\"main\""),
        document) || error("$(spec.name) entry-point contract mismatch.")
    descriptor_sets = [parse(Int, only(item.captures)) for item in
        eachmatch(r"OpDecorate\s+%\w+\s+DescriptorSet\s+(\d+)", document)]
    sort!(descriptor_sets)
    descriptor_sets == abi.descriptor_sets ||
        error("$(spec.name) descriptor-set contract mismatch.")
    isempty(abi.uniform_struct) && return true
    offsets = Int[]
    pattern = Regex(
            "OpMemberDecorate\\s+%(?:type_)?$(abi.uniform_struct)" *
            "\\s+\\d+\\s+Offset\\s+(\\d+)")
    for offset in eachmatch(pattern, document)
        push!(offsets, parse(Int, only(offset.captures)))
    end
    offsets == abi.uniform_offsets ||
        error("$(spec.name) uniform-offset contract mismatch.")
    if abi.array_stride > 0
        strides = [parse(Int, only(item.captures)) for item in
            eachmatch(r"OpDecorate\s+%\w+\s+ArrayStride\s+(\d+)", document)]
        !isempty(strides) && all(==(abi.array_stride), strides) ||
            error("$(spec.name) array-stride contract mismatch.")
    end
    return true
end

"""Return the SHA-256 identity of one build input or artifact."""
file_sha256(path::String) = bytes2hex(open(sha256, path))

"""Collect the sorted dynamic-library closure of one Linux build tool."""
function tool_closure(path::String)
    Sys.islinux() || return String[]
    result = capture_command(Cmd(["ldd", path]))
    result.exit_code == 0 || error("Could not inspect build-tool closure for $path")
    occursin("not found", result.output) && error(
        "Build-tool closure for $path contains an unresolved library.")
    libraries = String[]
    for line in split(result.output, '\n')
        path_match = match(r"=>\s+(/\S+)", line)
        path_match === nothing && (path_match = match(r"^\s*(/\S+)", line))
        path_match === nothing || push!(libraries, realpath(path_match.captures[1]))
    end
    return sort!(unique(libraries))
end

"""Write one TOML string array without depending on a package serializer."""
function write_string_array(io::IO, field::String, values::Vector{String})
    escaped = ["\"$(replace(value, '\\' => "\\\\", '"' => "\\\""))\""
        for value in values]
    println(io, "$field = [$(join(escaped, ", "))]")
end

"""Write one TOML integer array, including a valid untyped empty array."""
function write_integer_array(io::IO, field::String, values::Vector{Int})
    println(io, "$field = [$(join(values, ", "))]")
end

"""Escape one string for a TOML basic-string value."""
toml_string(value::AbstractString) =
    replace(String(value), '\\' => "\\\\", '"' => "\\\"")

"""Write one validated shader artifact and ABI record."""
function write_shader_record(
    io::IO, directory::String, spec::ShaderSpec, abi::ShaderAbi;
    kernel::Symbol=Sys.KERNEL)
    source_name = basename(spec.source)
    artifact_name = "$(spec.name).spv"
    runtime_name = runtime_artifact_name(spec, kernel)
    reflection_name = "$(spec.name).json"
    println(io)
    println(io, "[[shader]]")
    println(io, "name = \"$(spec.name)\"")
    println(io, "stage = \"$(spec.stage)\"")
    println(io, "entrypoint = \"main\"")
    println(io, "uniform_size = $(abi.uniform_size)")
    write_integer_array(io, "uniform_offsets", abi.uniform_offsets)
    println(io, "array_stride = $(abi.array_stride)")
    write_integer_array(io, "descriptor_sets", abi.descriptor_sets)
    write_integer_array(io, "vertex_bindings", abi.vertex_bindings)
    write_integer_array(io, "vertex_offsets", abi.vertex_offsets)
    write_integer_array(io, "vertex_strides", abi.vertex_strides)
    println(io, "source = \"$source_name\"")
    println(io, "source_sha256 = \"$(file_sha256(spec.source))\"")
    println(io, "artifact = \"$artifact_name\"")
    println(io, "artifact_sha256 = \"$(file_sha256(
        joinpath(directory, artifact_name)))\"")
    println(io, "runtime_format = \"$(runtime_shader_format(kernel))\"")
    println(io,
        "runtime_entrypoint = \"$(runtime_shader_entrypoint(kernel))\"")
    println(io, "runtime_artifact = \"$runtime_name\"")
    println(io, "runtime_artifact_sha256 = \"$(file_sha256(
        joinpath(directory, runtime_name)))\"")
    println(io, "reflection = \"$reflection_name\"")
    println(io, "reflection_sha256 = \"$(file_sha256(
        joinpath(directory, reflection_name)))\"")
end

"""Write the deterministic packaged shader manifest."""
function write_manifest(
    path::String, specs::Vector{ShaderSpec}, tool::String, validator::String;
    kernel::Symbol=Sys.KERNEL)
    abis = shader_abis()
    open(path, "w") do io
        println(io, "schema_version = $SHADER_SCHEMA_VERSION")
        println(io, "shadercross_path = \"$(toml_string(tool))\"")
        println(io, "shadercross_identity = \"sha256:$(file_sha256(tool))\"")
        println(io, "shadercross_sha256 = \"$(file_sha256(tool))\"")
        write_string_array(io, "shadercross_closure", tool_closure(tool))
        println(io,
            "spirv_validator_path = \"$(toml_string(validator))\"")
        println(io,
            "spirv_validator_identity = \"sha256:$(file_sha256(validator))\"")
        println(io, "spirv_validator_sha256 = \"$(file_sha256(validator))\"")
        write_string_array(io, "spirv_validator_closure", tool_closure(validator))
        for spec in specs
            write_shader_record(
                io, dirname(path), spec, abis[spec.name]; kernel)
        end
    end
end

"""Resolve the shader compiler, validator, and disassembler executables."""
function resolve_shader_build_tools(repository_root::String,
    shadercross::Union{Nothing,String}, validator::Union{Nothing,String},
    disassembler::Union{Nothing,String})
    shadercross_path = shadercross === nothing ?
        resolve_shadercross(repository_root) : realpath(shadercross)
    validator_path = validator === nothing ?
        resolve_bundled_spirv_tool(repository_root, "spirv-val") :
        realpath(validator)
    disassembler_path = disassembler === nothing ?
        resolve_bundled_spirv_tool(repository_root, "spirv-dis") :
        realpath(disassembler)
    return ShaderBuildTools(
        shadercross_path, validator_path, disassembler_path)
end

"""Generate and validate all artifacts for one production shader."""
function build_shader(spec::ShaderSpec, abi::ShaderAbi, output_dir::String,
    shadercross::String, validator::String, disassembler::String)
    spirv = joinpath(output_dir, "$(spec.name).spv")
    reflection = joinpath(output_dir, "$(spec.name).json")
    checked_command(compile_command(shadercross, spec, spirv), spec.name)
    verify_reproducible_artifact(shadercross, spec, spirv)
    checked_command(Cmd([validator, spirv]), "$(spec.name) validation")
    disassembly = capture_command(Cmd([disassembler, spirv]))
    disassembly.exit_code == 0 || error("$(spec.name) disassembly failed.")
    validate_spirv_abi(spec, abi, disassembly.output)
    checked_command(reflection_command(shadercross, spec, spirv, reflection),
        "$(spec.name) reflection")
    validate_reflection(spec, read(reflection, String))
    if Sys.isapple()
        msl = joinpath(output_dir, runtime_artifact_name(spec))
        checked_command(msl_command(shadercross, spec, spirv, msl),
            "$(spec.name) MSL generation")
        verify_reproducible_msl(shadercross, spec, spirv, msl)
    elseif Sys.iswindows()
        dxil = joinpath(output_dir, runtime_artifact_name(spec))
        checked_command(dxil_command(shadercross, spec, spirv, dxil),
            "$(spec.name) DXIL generation")
        verify_reproducible_dxil(shadercross, spec, spirv, dxil)
    end
end

"""Generate, reflect, validate, and identify every production shader."""
function build_shaders(repository_root::String;
    shadercross::Union{Nothing,String}=nothing,
    validator::Union{Nothing,String}=nothing,
    disassembler::Union{Nothing,String}=nothing)
    tools = resolve_shader_build_tools(
        repository_root, shadercross, validator, disassembler)
    source_root = joinpath(repository_root, "src")
    output_dir = joinpath(repository_root, ".build", "shaders")
    rm(output_dir; recursive=true, force=true)
    mkpath(output_dir)
    specs = shader_specs(source_root)
    abis = shader_abis()
    validate_pipeline_contracts(specs, abis)
    for spec in specs
        build_shader(spec, abis[spec.name], output_dir, tools.compiler,
            tools.validator, tools.disassembler)
    end
    manifest = joinpath(output_dir, "manifest.toml")
    write_manifest(manifest, specs, tools.compiler, tools.validator)
    return ShaderArtifacts(output_dir, manifest)
end

end