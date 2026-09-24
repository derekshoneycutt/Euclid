@testset "SDL_image capability probe" begin
    @testset "deterministic fixtures" begin
        @test length(SDL3ImageProbe.base64decode(SDL3ImageProbe.JPEG_FIXTURE)) == 285
        @test length(SDL3ImageProbe.base64decode(SDL3ImageProbe.PNG_FIXTURE)) == 68
        @test length(SDL3ImageProbe.base64decode(SDL3ImageProbe.GIF_FIXTURE)) == 34
    end

    @testset "binding resolution" begin
        mktempdir() do root
            binding = joinpath(root, "vendor", "sdl3", "image", "sdl_image.odin")
            mkpath(dirname(binding))
            write(binding, "package sdl3_image\n")
            @test SDL3ImageProbe.image_binding_path(root; kernel=:Linux) == binding
            @test_throws ErrorException SDL3ImageProbe.image_binding_path(
                root; kernel=:Darwin)
        end
    end

    @testset "strict build command" begin
        command = SDL3ImageProbe.image_probe_build_command(
            "tools/sdl3_image_probe", ".build/probe",
            SubString(" -lSDL3_image -lSDL3", 2))
        @test command.exec == [
            "odin", "build", "tools/sdl3_image_probe", "-out:.build/probe",
            "-vet", "-strict-style", "-disallow-do", "-warnings-as-errors",
            "-extra-linker-flags:-lSDL3_image -lSDL3",
        ]
        @test_throws ErrorException SDL3ImageProbe.image_probe_build_command(
            "source", "output", "")
    end

    @testset "runtime evidence" begin
        facts = Dict(
            "binding_version" => "3.4.0",
            "runtime_version" => "3004000",
            "jpeg_decode" => "true",
            "png_decode" => "true",
            "gif_decode" => "true",
            "gif_encode" => "true",
            "gif_stream_decode" => "true",
            "animation_frames" => "2",
            "animation_delays" => "40,80",
            "cleanup_complete" => "true")
        evidence = SDL3ImageProbe.image_runtime_evidence(facts)
        @test evidence["binding_version"] == "3.4.0"
        @test evidence["runtime_version"] == "3.4.0"
        @test evidence["jpeg_decode"]
        @test evidence["png_decode"]
        @test evidence["gif_decode"]
        @test evidence["gif_encode"]
        @test evidence["gif_stream_decode"]
        @test evidence["animation_frames"] == 2
        @test evidence["animation_delays_ms"] == [40, 80]
        @test evidence["cleanup_complete"]
    end

    @test SDL3ImageProbe.loaded_sdl3_image_path(
        "libSDL3_image.so.0 => /usr/lib64/libSDL3_image.so.0 (0x01)\n") ==
        "/usr/lib64/libSDL3_image.so.0"
end
