module EuclidBuildConfiguration

export native_linker_flags

"""Query mandatory Linux HarfBuzz linker and runtime flags."""
function system_harfbuzz_linker_flags()
    Sys.islinux() || error("Euclid currently requires Linux HarfBuzz.")
    output = IOBuffer()
    process = run(pipeline(
        ignorestatus(`pkg-config --libs --static harfbuzz`),
        stdout=output,
        stderr=devnull))
    process.exitcode == 0 || error(
        "Could not resolve system HarfBuzz through pkg-config.")
    flags = split(String(take!(output)))
    pcre2_libdir = readchomp(`pkg-config --variable=libdir libpcre2-8`)
    pcre2_library = joinpath(pcre2_libdir, "libpcre2-8.so")
    isfile(pcre2_library) || error("Missing system PCRE2 library at $pcre2_library")
    replace!(flags, "-lpcre2-8" => pcre2_library)
    pushfirst!(flags, "-Wl,-rpath,$pcre2_libdir")
    return join(flags, " ")
end

"""Query complete linker flags from the active Julia installation."""
function julia_linker_flags()
    Sys.islinux() || error("Euclid currently requires Linux.")
    julia_config_path = joinpath(
        Sys.BINDIR, Base.DATAROOTDIR, "julia", "julia-config.jl")
    isfile(julia_config_path) || error("Could not resolve julia-config.jl path.")
    command = Cmd([
        Base.julia_cmd().exec...,
        julia_config_path,
        "--ldflags",
        "--ldlibs",
    ])
    output = IOBuffer()
    process = run(pipeline(ignorestatus(command), stdout=output, stderr=devnull))
    process.exitcode == 0 || error("Failed to query Julia linker flags.")
    flags = join(split(String(take!(output))), " ")
    any(flag == "-ljulia" for flag in split(flags)) ||
        error("Julia linker flags do not contain -ljulia.")
    return flags
end

"""Resolve complete mandatory native linker flags for Linux builds."""
function native_linker_flags()
    return "$(system_harfbuzz_linker_flags()) $(julia_linker_flags())"
end

end