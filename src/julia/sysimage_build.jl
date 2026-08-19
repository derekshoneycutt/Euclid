using PackageCompiler

if length(ARGS) != 1
    error("usage: sysimage_build.jl <output-path>")
end

const JuliaRoot = @__DIR__
PackageCompiler.create_sysimage(
    [:Colors, :LaTeXStrings, :Latexify];
    sysimage_path=abspath(ARGS[1]),
    project=JuliaRoot,
    incremental=true,
    script=joinpath(JuliaRoot, "sysimage_core.jl"),
    precompile_execution_file=joinpath(JuliaRoot, "sysimage_workload.jl"),
    import_into_main=false)