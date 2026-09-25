@testset "SDL3 capability probe" begin
    invocation = parse_driver_invocation(["probe-sdl3"])
    @test invocation.action == :probe_sdl3
    @test isempty(invocation.arguments)
    @test occursin("probe-sdl3", show_help())

    build = EuclidSDL3Probe.probe_build_command(
        "tools/sdl3_probe", ".build/sdl3-probe/probe")
    @test build.exec[1:3] == ["odin", "build", "tools/sdl3_probe"]
    @test "-vet" in build.exec
    @test "-strict-style" in build.exec
    @test "-disallow-do" in build.exec
    @test "-warnings-as-errors" in build.exec

    shader = EuclidSDL3Probe.probe_shader_command(
        "triangle.vert", "triangle.vert.spv", "vertex")
    @test shader.exec == [
        "glslc", "-fshader-stage=vertex", "triangle.vert", "-o",
        "triangle.vert.spv"]
    @test_throws ErrorException EuclidSDL3Probe.probe_shader_command(
        "triangle.geom", "triangle.geom.spv", "geometry")
    msl = EuclidSDL3Probe.probe_msl_command(
        "shadercross", "triangle.vert.spv", "triangle.vert.msl", "vertex")
    @test msl.exec == ["shadercross", "triangle.vert.spv", "--source",
        "SPIRV", "--dest", "MSL", "--stage", "vertex", "--entrypoint",
        "main", "--msl-version", "2.0.0", "--output", "triangle.vert.msl"]

    facts = EuclidSDL3Probe.parse_probe_output("""
noise
probe.binding_version=3.4.2
probe.gpu_driver[0]=vulkan
probe.gpu_driver[1]=metal
probe.resize_status=indeterminate
probe.result=passed
""")
    @test facts["binding_version"] == "3.4.2"
    @test facts["gpu_drivers"] == "vulkan,metal"
    @test facts["resize_status"] == "indeterminate"
    @test facts["result"] == "passed"

    mktempdir() do root
        binding_root = joinpath(root, "vendor", "sdl3")
        mkpath(binding_root)
        for name in ("sdl3__foreign.odin", "sdl3_gpu.odin", "sdl3_version.odin")
            write(joinpath(binding_root, name), name)
        end
        paths = EuclidSDL3Probe.binding_paths(root; kernel=:Linux)
        @test basename.(paths) == [
            "sdl3__foreign.odin", "sdl3_gpu.odin", "sdl3_version.odin"]
        @test length(EuclidSDL3Probe.binding_paths(root; kernel=:Darwin)) == 3
        rm(last(paths))
        @test_throws ErrorException EuclidSDL3Probe.binding_paths(root; kernel=:Linux)
    end

    @test EuclidSDL3Probe.loaded_sdl_path_darwin("""
probe:
    /opt/homebrew/opt/sdl3/lib/libSDL3.0.dylib (compatibility version 1.0.0)
""") == "/opt/homebrew/opt/sdl3/lib/libSDL3.0.dylib"
end
