using Test

@testset "PCRE2_jll named foreign import linkage" begin
    configuration = Main.EuclidBuildConfiguration
    library_path, runtime_dirs = configuration.pcre2_jll_paths()
    @test isfile(library_path)
    @test dirname(library_path) in runtime_dirs
    @test !isempty(configuration.pcre2_jll_linker_flags())
    @test dirname(library_path) in configuration.native_runtime_dirs()
    native_flags = configuration.native_linker_flags()
    if !Sys.iswindows()
        @test occursin(library_path, native_flags)
    end
    packages = Main.collect_julia_packages(joinpath(@__DIR__, "..", "..",
        "src", "julia"))
    @test any(package -> package.name == "PCRE2_jll", packages)
    identity_probe = """
        using PCRE2_jll, Libdl
        println(realpath(Libdl.dlpath(Libdl.dlopen(Base.PCRE.PCRE_LIB))))
        version = zeros(UInt8, 64)
        ccall((:pcre2_config_8, PCRE2_jll.libpcre2_8), Cint,
            (UInt32, Ptr{UInt8}), UInt32(11), version)
        println(unsafe_string(pointer(version)))
        println(Base.DEFAULT_COMPILER_OPTS)
        println(Base.DEFAULT_MATCH_OPTS)
        """
    identity = configuration.capture_command(Cmd([
        Base.julia_cmd().exec...,
        "--project=$(configuration.JULIA_PROJECT)", "-e", identity_probe]))
    @test identity.exit_code == 0
    identity_lines = split(strip(identity.output), '\n')
    @test length(identity_lines) == 4
    @test identity_lines[1] == realpath(library_path)
    provider = only(filter(package -> package.name == "PCRE2_jll", packages))
    engine_version = join(split(first(split(provider.version, '+')), '.')[1:2], '.')
    @test startswith(identity_lines[2], engine_version * " ")
    @test parse(UInt32, identity_lines[3]) == UInt32(0x040a0002)
    @test parse(UInt32, identity_lines[4]) == UInt32(0x40000000)
    @info "Selected Julia/PCRE2 identity" julia=VERSION library_path engine=identity_lines[2]
    withenv("PATH" => "") do
        absolute_path_packages = Main.collect_julia_packages(
            joinpath(@__DIR__, "..", "..", "src", "julia"))
        @test any(package -> package.name == "PCRE2_jll", absolute_path_packages)
    end

    if Sys.islinux()
        flags = configuration.pcre2_jll_linker_flags()
        @test "-L$(dirname(library_path))" in split(flags)
        mktempdir() do directory
            output = joinpath(directory, "pcre2-link-probe.so")
            command = Cmd(["clang", "-shared", "-nostdlib", "-Wl,-t",
                "-o", output, split(flags)..., "-lpcre2-8"])
            result = configuration.capture_command(command)
            @test result.exit_code == 0
            @test isfile(output)
            @test count(==(library_path), split(strip(result.output), '\n')) == 2
        end
    elseif Sys.isapple()
        flags = configuration.pcre2_jll_linker_flags()
        @test startswith(flags, library_path)
        @test all(directory -> "-Wl,-rpath,$directory" in split(flags),
            runtime_dirs)
    elseif Sys.iswindows()
        import_library = joinpath(@__DIR__, "..", "..", "bin",
            ".native_import_libs", "pcre2-8.lib")
        @test occursin("/DEFAULTLIB:pcre2-8.lib",
            configuration.native_linker_flags())
        @test isfile(import_library)
    end
end
