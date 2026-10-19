using Test
using TOML

include(joinpath(@__DIR__, "..", "shaders.jl"))
const Shaders = EuclidShaders

"""Serialize reflected stage-interface entries in shadercross form."""
function reflected_interface(entries)
    return join([
        "{ \"name\": \"value\", \"type\": \"$(entry.second)\", " *
        "\"location\": $(entry.first) }" for entry in entries], ", ")
end

if Sys.isapple()
    @testset "relocated Apple Silicon production shaders" begin
        mktempdir() do root
            payload = joinpath(root, "relocated payload")
            cp(Shaders.MACOS_SHADERCROSS_DIR, payload)
            Shaders.macos_shadercross_manifest(payload)
            original = joinpath(root, "original")
            relocated = joinpath(root, "relocated")
            mkpath(original)
            mkpath(relocated)
            specs = Shaders.shader_specs(joinpath(Shaders.REPOSITORY_ROOT, "src"))
            abis = Shaders.shader_abis()
            withenv("DYLD_LIBRARY_PATH" => nothing,
                "DYLD_FALLBACK_LIBRARY_PATH" => nothing) do
                for spec in specs
                    for (tools, output) in (
                        (Shaders.MACOS_SHADERCROSS_DIR, original), (payload, relocated))
                        Shaders.build_shader(spec, abis[spec.name], output,
                            joinpath(tools, "shadercross"), joinpath(tools, "spirv-val"),
                            joinpath(tools, "spirv-dis"))
                    end
                    for extension in ("spv", "msl", "json")
                        filename = "$(spec.name).$extension"
                        @test read(joinpath(original, filename)) ==
                            read(joinpath(relocated, filename))
                    end
                end
            end
        end
    end
end

"""Build a minimal shadercross reflection document for contract tests."""
function reflected_document(
    uniforms::Int, samplers::Int,
    inputs::Vector{Pair{Int,String}}, outputs::Vector{Pair{Int,String}})
    return "{ \"samplers\": $samplers, \"storage_textures\": 0, " *
        "\"storage_buffers\": 0, \"uniform_buffers\": $uniforms, " *
        "\"inputs\": [$(reflected_interface(inputs))], " *
        "\"outputs\": [$(reflected_interface(outputs))] }"
end

@testset "offline shader contracts" begin
    specs = Shaders.shader_specs("/source")
    @test getfield.(specs, :name) == [
        "draw2d_colored.vert", "draw2d_colored.frag",
        "draw2d_textured.vert", "draw2d_textured.frag",
        "stroke3d.vert", "stroke3d.frag",
        "dust_instanced.vert", "dust_instanced.frag",
        "leaper_light.frag"]
    @test Shaders.validate_pipeline_contracts(specs)
    @test Shaders.shader_abis()["draw2d_colored.vert"].vertex_offsets == [0, 16]
    @test Shaders.shader_abis()["draw2d_textured.vert"].vertex_offsets == [0, 8, 16]
    @test Shaders.shader_abis()["draw2d_textured.frag"].descriptor_sets == [2, 2]
    @test Shaders.shader_abis()["dust_instanced.vert"].vertex_strides ==
        [16, 16, 32, 32, 32]
    @test_throws ErrorException Shaders.resolve_tool(
        "__euclid_missing_shader_tool__")

    spec = first(specs)
    compile = Shaders.compile_command("shadercross", spec, "output.spv")
    @test compile.exec == ["shadercross", spec.source, "--source", "HLSL",
        "--dest", "SPIRV", "--stage", "vertex", "--entrypoint", "main",
        "--output", "output.spv"]
    msl = Shaders.msl_command(
        "shadercross", spec, "input.spv", "output.msl")
    @test msl.exec == ["shadercross", "input.spv", "--source", "SPIRV",
        "--dest", "MSL", "--stage", "vertex", "--entrypoint", "main",
        "--msl-version", "2.0.0", "--output", "output.msl"]
    dxil = Shaders.dxil_command(
        "shadercross", spec, "input.spv", "output.dxil")
    @test dxil.exec == ["shadercross", "input.spv", "--source", "SPIRV",
        "--dest", "DXIL", "--stage", "vertex", "--entrypoint", "main",
        "--output", "output.dxil"]
    @test Shaders.runtime_shader_format(:Linux) == "SPIR-V"
    @test Shaders.runtime_shader_format(:Darwin) == "MSL"
    @test Shaders.runtime_shader_format(:NT) == "DXIL"
    @test Shaders.runtime_shader_entrypoint(:Linux) == "main"
    @test Shaders.runtime_shader_entrypoint(:Darwin) == "main0"
    @test Shaders.runtime_shader_entrypoint(:NT) == "main"
    @test Shaders.runtime_artifact_name(spec, :Linux) ==
        "draw2d_colored.vert.spv"
    @test Shaders.runtime_artifact_name(spec, :Darwin) ==
        "draw2d_colored.vert.msl"
    @test Shaders.runtime_artifact_name(spec, :NT) ==
        "draw2d_colored.vert.dxil"
    reflection = Shaders.reflection_command(
        "shadercross", spec, "output.spv", "output.json")
    @test reflection.exec[3:6] == ["--source", "SPIRV", "--dest", "JSON"]
    @test Shaders.repository_shadercross_commit(Shaders.REPOSITORY_ROOT) ==
        "1ff05bec573988a98ef9e0260b4da44f512b8367"
    for (validate, architecture) in (
        (Shaders.windows_shadercross_manifest, :x86_64),
        (Shaders.linux_shadercross_manifest, :x86_64),
        (Shaders.macos_shadercross_manifest, :aarch64))
        @test validate(; architecture,
            expected_source_commit=Shaders.repository_shadercross_commit(
                Shaders.REPOSITORY_ROOT))["source_commit"] ==
            "1ff05bec573988a98ef9e0260b4da44f512b8367"
    end
    mktempdir() do repository
        @test_throws ErrorException Shaders.repository_shadercross_commit(repository)
        root = joinpath(repository, "libs", "sdl_shadercross")
        mkpath(root)
        pin = joinpath(root, "source-pin.toml")
        write(pin, "source_commit = \"invalid\"\n")
        @test_throws ErrorException Shaders.repository_shadercross_commit(repository)
        write(pin, "source_commit = \"$(repeat("a", 40))\"\n")
        @test Shaders.repository_shadercross_commit(repository) == repeat("a", 40)
    end

    if Sys.iswindows()
        manifest = Shaders.windows_shadercross_manifest(
            Shaders.WINDOWS_SHADERCROSS_DIR;
            expected_source_commit=Shaders.repository_shadercross_commit(
                Shaders.REPOSITORY_ROOT))
        @test manifest["source_commit"] ==
            "1ff05bec573988a98ef9e0260b4da44f512b8367"
        @test Set(artifact["file"] for component in manifest["component"]
            for artifact in get(component, "artifact", Any[])) ==
            Shaders.WINDOWS_SHADERCROSS_ARTIFACTS
        @test Shaders.windows_shadercross_runtime_dirs() == [
            Shaders.WINDOWS_SDL_DIR, Shaders.WINDOWS_SHADERCROSS_DIR]
        withenv(Shaders.SHADERCROSS_ENV => nothing) do
            @test Shaders.resolve_shadercross(Shaders.REPOSITORY_ROOT) ==
                realpath(joinpath(
                    Shaders.WINDOWS_SHADERCROSS_DIR, "shadercross.exe"))
            @test Shaders.resolve_bundled_spirv_tool(
                Shaders.REPOSITORY_ROOT, "spirv-val") == realpath(joinpath(
                    Shaders.WINDOWS_SHADERCROSS_DIR, "spirv-val.exe"))
        end
        @test_throws ErrorException Shaders.windows_shadercross_manifest(
            Shaders.WINDOWS_SHADERCROSS_DIR;
            expected_source_commit=repeat("0", 40))
    end

    @testset "Apple Silicon binary provider" begin
        manifest = Shaders.macos_shadercross_manifest(; architecture=:aarch64,
            expected_source_commit=Shaders.repository_shadercross_commit(
                Shaders.REPOSITORY_ROOT))
        @test manifest["macos_minimum"] == "11.0"
        @test Set(artifact["file"] for component in manifest["component"]
            for artifact in get(component, "artifact", Any[])) ==
            Shaders.MACOS_SHADERCROSS_ARTIFACTS
        @test_throws ErrorException Shaders.macos_shadercross_manifest(
            ; architecture=:x86_64)
        @test_throws ErrorException Shaders.macos_shadercross_manifest(
            ; architecture=:aarch64, expected_source_commit=repeat("0", 40))
        @test_throws ErrorException Shaders.macos_shadercross_manifest(
            ; architecture=:aarch64, hash_file=_ -> "invalid")
        @test_throws ErrorException Shaders.macos_shadercross_manifest(
            ; architecture=:aarch64, file_size=_ -> -1)
        for mutation in (
            Dict("schema_version" => 2), Dict("platform" => "linux"),
            Dict("provider" => "unknown"), Dict("toolchain" => "gcc"),
            Dict("architecture" => "x86_64"), Dict("macos_minimum" => "26.0"),
            Dict("runtime_search_path" => "/build"), Dict("component" => Any[]),
            Dict("source_commit" => "invalid"), Dict("source_dependency" => Any[]))
            @test_throws ErrorException Shaders.macos_shadercross_manifest(
                ; architecture=:aarch64,
                parse_file=path -> merge(TOML.parsefile(path), mutation))
        end
        mktempdir() do root
            payload = joinpath(root, "payload")
            cp(Shaders.MACOS_SHADERCROSS_DIR, payload)
            rm(joinpath(payload, "libdxil.dylib"))
            @test_throws ErrorException Shaders.macos_shadercross_manifest(
                payload; architecture=:aarch64)
        end
        if Sys.isapple()
            withenv(Shaders.SHADERCROSS_ENV => nothing) do
                tools = Shaders.resolve_shader_build_tools(
                    Shaders.REPOSITORY_ROOT, nothing, nothing, nothing)
                @test tools.compiler ==
                    realpath(joinpath(Shaders.MACOS_SHADERCROSS_DIR, "shadercross"))
                @test tools.validator ==
                    realpath(joinpath(Shaders.MACOS_SHADERCROSS_DIR, "spirv-val"))
                @test tools.disassembler ==
                    realpath(joinpath(Shaders.MACOS_SHADERCROSS_DIR, "spirv-dis"))
                mktempdir() do repository
                    @test_throws ErrorException Shaders.resolve_shadercross(repository)
                    @test_throws ErrorException Shaders.resolve_bundled_spirv_tool(
                        repository, "spirv-val")
                end
            end
            withenv(Shaders.SHADERCROSS_ENV => Base.julia_cmd().exec[1]) do
                @test Shaders.resolve_shadercross(Shaders.REPOSITORY_ROOT) ==
                    realpath(Base.julia_cmd().exec[1])
            end
        end
    end

    if Sys.islinux()
        manifest = Shaders.linux_shadercross_manifest(
            Shaders.LINUX_SHADERCROSS_DIR;
            expected_source_commit=Shaders.repository_shadercross_commit(
                Shaders.REPOSITORY_ROOT))
        @test manifest["glibc_minimum"] == "2.35"
        @test manifest["source_commit"] ==
            "1ff05bec573988a98ef9e0260b4da44f512b8367"
        @test Set(artifact["file"] for component in manifest["component"]
            for artifact in get(component, "artifact", Any[])) ==
            Shaders.LINUX_SHADERCROSS_ARTIFACTS
        withenv(Shaders.SHADERCROSS_ENV => nothing) do
            tools = Shaders.resolve_shader_build_tools(
                Shaders.REPOSITORY_ROOT, nothing, nothing, nothing)
            @test tools.compiler ==
                realpath(joinpath(Shaders.LINUX_SHADERCROSS_DIR, "shadercross"))
            @test tools.validator ==
                realpath(joinpath(Shaders.LINUX_SHADERCROSS_DIR, "spirv-val"))
            @test tools.disassembler ==
                realpath(joinpath(Shaders.LINUX_SHADERCROSS_DIR, "spirv-dis"))
            mktempdir() do empty_repository
                @test_throws ErrorException Shaders.resolve_shadercross(empty_repository)
            end
        end
        withenv(Shaders.SHADERCROSS_ENV => Base.julia_cmd().exec[1]) do
            @test Shaders.resolve_shadercross(Shaders.REPOSITORY_ROOT) ==
                realpath(Base.julia_cmd().exec[1])
        end
        @test_throws ErrorException Shaders.linux_shadercross_manifest(
            ; architecture=:aarch64)
        @test_throws ErrorException Shaders.linux_shadercross_manifest(
            ; expected_source_commit=repeat("0", 40))
        @test_throws ErrorException Shaders.linux_shadercross_manifest(
            ; hash_file=_ -> "invalid")
        @test_throws ErrorException Shaders.linux_shadercross_manifest(
            ; file_size=_ -> -1)
        for mutation in (
            Dict("schema_version" => 2), Dict("platform" => "windows"),
            Dict("glibc_minimum" => "2.43"), Dict("glibcxx_minimum" => "3.4.35"),
            Dict("runtime_search_path" => "/build"), Dict("component" => Any[]))
            @test_throws ErrorException Shaders.linux_shadercross_manifest(
                ; parse_file=path -> merge(TOML.parsefile(path), mutation))
        end
    end

    document = reflected_document(
        spec.uniform_buffers, spec.samplers, spec.inputs, spec.outputs)
    @test Shaders.validate_reflection(spec, document)
    @test_throws ErrorException Shaders.validate_reflection(
        spec, replace(document, "\"uniform_buffers\": 1" =>
            "\"uniform_buffers\": 0"))
    @test_throws ErrorException Shaders.validate_reflection(
        spec, replace(document, "\"location\": 2" => "\"location\": 4"))

    disassembly = """
OpEntryPoint Vertex %main \"main\"
OpDecorate %uniforms DescriptorSet 1
OpMemberDecorate %type_StrokeVertexUniforms 0 Offset 0
"""
    stroke_spec = only(filter(item -> item.name == "stroke3d.vert", specs))
    @test Shaders.validate_spirv_abi(
        stroke_spec, Shaders.shader_abis()[stroke_spec.name], disassembly)
    @test_throws ErrorException Shaders.validate_spirv_abi(
        stroke_spec, Shaders.shader_abis()[stroke_spec.name], replace(disassembly,
            "Offset 0" => "Offset 16"))

    integer_array = IOBuffer()
    Shaders.write_integer_array(integer_array, "values", Int[])
    @test TOML.parse(String(take!(integer_array)))["values"] == []

    mktempdir() do root
        source = joinpath(root, "sample.vert.hlsl")
        write(source, "shader source")
        generated = Shaders.ShaderSpec(
            "stroke3d.vert", source, "vertex", 0, 0, Pair{Int,String}[],
            Pair{Int,String}[])
        write(joinpath(root, "stroke3d.vert.spv"), "spirv")
        write(joinpath(root, "stroke3d.vert.json"), "reflection")
        manifest_path = joinpath(root, "manifest.toml")
        tool = realpath(Base.julia_cmd().exec[1])
        Shaders.write_manifest(manifest_path, [generated], tool, tool;
            kernel=:Linux)
        manifest = TOML.parsefile(manifest_path)
        @test manifest["shadercross_path"] == tool
        @test startswith(manifest["shadercross_identity"], "sha256:")
        @test manifest["shader"][1]["artifact_sha256"] ==
            bytes2hex(open(Shaders.sha256, joinpath(root, "stroke3d.vert.spv")))
        @test manifest["shader"][1]["runtime_format"] == "SPIR-V"
        @test manifest["shader"][1]["runtime_entrypoint"] == "main"
        @test manifest["shader"][1]["runtime_artifact"] ==
            "stroke3d.vert.spv"
        @test manifest["shader"][1]["uniform_size"] == 64
        @test manifest["shader"][1]["vertex_strides"] == [36, 36, 36]
    end
end