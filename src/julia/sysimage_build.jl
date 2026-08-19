using PackageCompiler

if length(ARGS) != 1
    error("usage: sysimage_build.jl <output-path>")
end

const julia_root = @__DIR__
PackageCompiler.create_sysimage(
    [:Colors, :LaTeXStrings, :Latexify];
    sysimage_path=abspath(ARGS[1]),
    project=julia_root,
    incremental=true,
    script=joinpath(julia_root, "sysimage_core.jl"),
    precompile_execution_file=joinpath(julia_root, "sysimage_workload.jl"),
    import_into_main=false)