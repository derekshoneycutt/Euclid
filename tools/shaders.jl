module EuclidShaders

using SHA

export ShaderAbi, ShaderArtifacts, ShaderSpec, build_shaders, compile_command,
    msl_command, reflection_command, runtime_artifact_name,
    runtime_shader_entrypoint, runtime_shader_format, shader_abis, shader_specs,
    shadercross_build_command, shadercross_configure_command,
    validate_pipeline_contracts, validate_reflection, validate_spirv_abi

const SHADER_SCHEMA_VERSION = 1
const MSL_VERSION = "2.0.0"
const SHADERCROSS_ENV = "EUCLID_SHADERCROSS"
const SHADERCROSS_DEPENDENCIES = [
    "DirectXShaderCompiler", "SPIRV-Cross", "SPIRV-Headers", "SPIRV-Tools"]

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

"""Return the ordered colored and textured 2D shader contracts."""
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
        "stroke3d.vert" => ShaderAbi("StrokeVertexUniforms", 64, [0], 0,
            [1], [0, 0, 0], [0, 12, 20], [36, 36, 36]),
        "stroke3d.frag" => ShaderAbi("StrokeFragmentUniforms", 192,
            [0, 12, 16, 20, 24, 28, 32, 36, 40, 44, 48, 56, 64, 76,
                80, 84, 88, 92, 96, 128, 160],
            16, [3], Int[], Int[], Int[]),
        "dust_instanced.vert" => ShaderAbi("DustVertexUniforms", 16, [0, 8], 0,
            [1], [0, 0, 1, 1, 1], [0, 8, 0, 12, 28], [16, 16, 32, 32, 32]),
        "dust_instanced.frag" => ShaderAbi("", 0, Int[], 0,
            [2, 2], Int[], Int[], Int[]))
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
    by_name["stroke3d.vert"].outputs == by_name["stroke3d.frag"].inputs ||
        error("Stroke stage interface mismatch.")
    by_name["dust_instanced.vert"].outputs ==
        by_name["dust_instanced.frag"].inputs ||
        error("Dust stage interface mismatch.")
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

"""Return the packaged runtime shader format for one host kernel."""
function runtime_shader_format(kernel::Symbol=Sys.KERNEL)
    kernel == :Linux && return "SPIR-V"
    kernel == :Darwin && return "MSL"
    error("Runtime shader generation is unsupported on $kernel.")
end

"""Return the SDL GPU entrypoint for one host kernel."""
function runtime_shader_entrypoint(kernel::Symbol=Sys.KERNEL)
    kernel == :Linux && return "main"
    kernel == :Darwin && return "main0"
    error("Runtime shader generation is unsupported on $kernel.")
end

"""Return the packaged runtime artifact name for one shader."""
function runtime_artifact_name(spec::ShaderSpec, kernel::Symbol=Sys.KERNEL)
    extension = kernel == :Linux ? "spv" :
        kernel == :Darwin ? "msl" :
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

"""Construct the canonical configure command for the vendored shader compiler."""
function shadercross_configure_command(
    cmake::String, source::String, build::String)
    return Cmd([cmake, "--fresh", "-S", source, "-B", build, "-G", "Ninja",
        "-DCMAKE_BUILD_TYPE=Release", "-DSDLSHADERCROSS_VENDORED=ON",
        "-DSDLSHADERCROSS_CLI=ON", "-DSDLSHADERCROSS_INSTALL=OFF",
        "-DSDLSHADERCROSS_TESTS=OFF", "-DSPIRV_WERROR=OFF"])
end

"""Report whether the bundled shader compiler cache needs fresh configuration."""
function shadercross_needs_configure(build::String)
    cache = joinpath(build, "CMakeCache.txt")
    isfile(cache) || return true
    entries = Set(eachline(cache))
    return !("CMAKE_GENERATOR:INTERNAL=Ninja" in entries &&
        "SPIRV_WERROR:BOOL=OFF" in entries)
end

"""Construct the parallel build command for the vendored shader compiler."""
function shadercross_build_command(cmake::String, build::String)
    return Cmd([cmake, "--build", build, "--target", "shadercross",
        "--parallel"])
end

"""Run one visible setup command and report its owning stage on failure."""
function checked_setup_command(command::Cmd, stage::String)
    process = run(ignorestatus(command))
    process.exitcode == 0 || error("$stage failed with exit $(process.exitcode).")
end

"""Build and return the SDL_shadercross CLI from the repository submodule."""
function build_bundled_shadercross(repository_root::String)
    source = joinpath(repository_root, "tools", "shadercross")
    isfile(joinpath(source, "CMakeLists.txt")) || error(
        "SDL_shadercross submodule is missing. Run git submodule update --init --recursive.")
    for dependency in SHADERCROSS_DEPENDENCIES
        isfile(joinpath(source, "external", dependency, "CMakeLists.txt")) || error(
            "SDL_shadercross dependencies are missing. Run git submodule update --init --recursive.")
    end
    cmake = resolve_tool("cmake")
    build = joinpath(repository_root, ".build", "shadercross")
    if shadercross_needs_configure(build)
        checked_setup_command(
            shadercross_configure_command(cmake, source, build),
            "SDL_shadercross configuration")
    end
    checked_setup_command(
        shadercross_build_command(cmake, build), "SDL_shadercross build")
    candidates = Sys.iswindows() ?
        [joinpath(build, "Release", "shadercross.exe"),
            joinpath(build, "shadercross.exe")] :
        [joinpath(build, "shadercross")]
    executable = findfirst(isfile, candidates)
    executable === nothing && error("SDL_shadercross build produced no CLI executable.")
    return realpath(candidates[executable])
end

"""Resolve an explicit shader compiler override or build the bundled provider."""
function resolve_shadercross(repository_root::String)
    override = get(ENV, SHADERCROSS_ENV, "")
    isempty(override) || return resolve_tool(
        "shadercross"; environment_name=SHADERCROSS_ENV)
    return build_bundled_shadercross(repository_root)
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
        println(io, "shadercross_path = \"$tool\"")
        println(io, "shadercross_identity = \"sha256:$(file_sha256(tool))\"")
        println(io, "shadercross_sha256 = \"$(file_sha256(tool))\"")
        write_string_array(io, "shadercross_closure", tool_closure(tool))
        println(io, "spirv_validator_path = \"$validator\"")
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

"""Generate, reflect, validate, and identify every production shader."""
function build_shaders(repository_root::String;
    shadercross::Union{Nothing,String}=nothing,
    validator::String=resolve_tool("spirv-val"))
    shadercross_path = shadercross === nothing ?
        resolve_shadercross(repository_root) : realpath(shadercross)
    source_root = joinpath(repository_root, "src")
    output_dir = joinpath(repository_root, ".build", "shaders")
    rm(output_dir; recursive=true, force=true)
    mkpath(output_dir)
    specs = shader_specs(source_root)
    abis = shader_abis()
    validate_pipeline_contracts(specs, abis)
    disassembler = resolve_tool("spirv-dis")
    for spec in specs
        spirv = joinpath(output_dir, "$(spec.name).spv")
        reflection = joinpath(output_dir, "$(spec.name).json")
        checked_command(compile_command(shadercross_path, spec, spirv), spec.name)
        verify_reproducible_artifact(shadercross_path, spec, spirv)
        checked_command(Cmd([validator, spirv]), "$(spec.name) validation")
        disassembly = capture_command(Cmd([disassembler, spirv]))
        disassembly.exit_code == 0 || error("$(spec.name) disassembly failed.")
        validate_spirv_abi(spec, abis[spec.name], disassembly.output)
        checked_command(
            reflection_command(shadercross_path, spec, spirv, reflection),
            "$(spec.name) reflection")
        validate_reflection(spec, read(reflection, String))
        if Sys.isapple()
            msl = joinpath(output_dir, runtime_artifact_name(spec))
            checked_command(msl_command(shadercross_path, spec, spirv, msl),
                "$(spec.name) MSL generation")
            verify_reproducible_msl(shadercross_path, spec, spirv, msl)
        end
    end
    manifest = joinpath(output_dir, "manifest.toml")
    write_manifest(manifest, specs, shadercross_path, validator)
    return ShaderArtifacts(output_dir, manifest)
end

end