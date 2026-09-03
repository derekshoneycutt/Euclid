module EuclidBuildConfiguration

export native_linker_flags

"""Query one pkg-config package and return normalized linker flags."""
function pkg_config_linker_flags(arguments::Vector{String})
    output = IOBuffer()
    process = run(pipeline(
        ignorestatus(Cmd(["pkg-config"; arguments])),
        stdout=output,
        stderr=devnull))
    process.exitcode == 0 || error(
        "Could not resolve system HarfBuzz through pkg-config.")
    return String.(split(String(take!(output))))
end

"""Return the HarfBuzz pkg-config query for one supported host kernel."""
function harfbuzz_pkg_config_arguments(kernel::Symbol=Sys.KERNEL)
    kernel == :Linux && return ["--libs", "--static", "harfbuzz"]
    kernel == :Darwin && return ["--libs", "harfbuzz"]
    error("System HarfBuzz linkage is unsupported on $kernel.")
end

"""Apply the Linux PCRE2 runtime workaround to static HarfBuzz flags."""
function linux_harfbuzz_linker_flags(flags::Vector{String})
    pcre2_libdir = readchomp(`pkg-config --variable=libdir libpcre2-8`)
    pcre2_library = joinpath(pcre2_libdir, "libpcre2-8.so")
    isfile(pcre2_library) || error("Missing system PCRE2 library at $pcre2_library")
    replace!(flags, "-lpcre2-8" => pcre2_library)
    pushfirst!(flags, "-Wl,-rpath,$pcre2_libdir")
    return join(flags, " ")
end

"""Query mandatory platform HarfBuzz linker and runtime flags."""
function system_harfbuzz_linker_flags()
    flags = pkg_config_linker_flags(harfbuzz_pkg_config_arguments())
    if Sys.islinux()
        return linux_harfbuzz_linker_flags(flags)
    elseif Sys.isapple()
        return join(flags, " ")
    end
    error("System HarfBuzz linkage is unsupported on $(Sys.KERNEL).")
end

"""Query complete linker flags from the active Julia installation."""
function julia_linker_flags()
    (Sys.islinux() || Sys.isapple()) ||
        error("Julia linker flag discovery is unsupported on $(Sys.KERNEL).")
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

"""Resolve complete mandatory native linker flags for Unix builds."""
function native_linker_flags()
    return "$(system_harfbuzz_linker_flags()) $(julia_linker_flags())"
end

end