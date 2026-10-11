using Test

if !isdefined(Main, :EuclidBuildConfiguration)
    include(joinpath(@__DIR__, "..", "build_config.jl"))
end

@testset "HarfBuzz JLL named foreign import linkage" begin
    if Sys.islinux()
        configuration = Main.EuclidBuildConfiguration
        library_path, _ = configuration.harfbuzz_jll_paths()
        flags = configuration.unix_harfbuzz_jll_linker_flags()
        @test "-L$(dirname(library_path))" in split(flags)
        mktempdir() do directory
            output = joinpath(directory, "harfbuzz-link-probe.so")
            command = Cmd(["clang", "-shared", "-nostdlib", "-Wl,-t",
                "-o", output, split(flags)..., "-lharfbuzz"])
            result = configuration.capture_command(command)
            @test result.exit_code == 0
            @test isfile(output)
            @test count(==(library_path), split(strip(result.output), '\n')) == 2
        end
    end
end
