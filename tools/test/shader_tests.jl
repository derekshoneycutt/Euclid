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
        "dust_instanced.vert", "dust_instanced.frag"]
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
    @test Shaders.runtime_shader_format(:Linux) == "SPIR-V"
    @test Shaders.runtime_shader_format(:Darwin) == "MSL"
    @test Shaders.runtime_shader_entrypoint(:Linux) == "main"
    @test Shaders.runtime_shader_entrypoint(:Darwin) == "main0"
    @test Shaders.runtime_artifact_name(spec, :Linux) ==
        "draw2d_colored.vert.spv"
    @test Shaders.runtime_artifact_name(spec, :Darwin) ==
        "draw2d_colored.vert.msl"
    reflection = Shaders.reflection_command(
        "shadercross", spec, "output.spv", "output.json")
    @test reflection.exec[3:6] == ["--source", "SPIRV", "--dest", "JSON"]
    configure = Shaders.shadercross_configure_command(
        "cmake", "/source/tools/shadercross", "/source/.build/shadercross")
    @test configure.exec[2] == "--fresh"
    @test configure.exec[7:8] == ["-G", "Ninja"]
    @test "-DSDLSHADERCROSS_VENDORED=ON" in configure.exec
    @test "-DSDLSHADERCROSS_INSTALL=OFF" in configure.exec
    @test "-DSPIRV_WERROR=OFF" in configure.exec
    mktempdir() do build
        @test Shaders.shadercross_needs_configure(build)
        write(joinpath(build, "CMakeCache.txt"), "SPIRV_WERROR:BOOL=ON\n")
        @test Shaders.shadercross_needs_configure(build)
        write(joinpath(build, "CMakeCache.txt"),
            "CMAKE_GENERATOR:INTERNAL=Unix Makefiles\nSPIRV_WERROR:BOOL=OFF\n")
        @test Shaders.shadercross_needs_configure(build)
        write(joinpath(build, "CMakeCache.txt"),
            "CMAKE_GENERATOR:INTERNAL=Ninja\nSPIRV_WERROR:BOOL=OFF\n")
        @test !Shaders.shadercross_needs_configure(build)
    end
    @test Shaders.shadercross_build_command(
        "cmake", "/source/.build/shadercross").exec[end] == "--parallel"

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
        tool = realpath(Sys.which("true"))
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