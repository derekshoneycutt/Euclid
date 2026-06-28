#!/usr/bin/env bash

set -euo pipefail

if ! command -v julia >/dev/null 2>&1; then
    echo "Error: Julia is required but not installed or not on PATH." >&2
    echo "Please install Julia to continue." >&2
    exit 1
fi

if ! command -v odin >/dev/null 2>&1; then
    echo "Error: Odin is required but not installed or not on PATH." >&2
    echo "Please install Odin to continue." >&2
    exit 1
fi

juliaConfigPath="$(julia -e 'print(joinpath(Sys.BINDIR, Base.DATAROOTDIR, "julia", "julia-config.jl"))')"
juliaFlags="$(${juliaConfigPath} --ldflags --ldlibs | tr '\n' ' ')"
scriptDir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

runAfterBuild=false
doBuild=true

if [[ "${1-}" == "--run" ]]; then
    runAfterBuild=true
elif [[ "${1-}" == "--run-only" ]]; then
    runAfterBuild=true
    doBuild=false
elif [[ "${1-}" == "--clean" ]]; then
    rm -rf "${scriptDir}/bin/"
    exit 0
elif [[ -n "${1-}" ]]; then
    echo "Usage: ./make.sh [--run]" >&2
    exit 1
fi

assetsStagingDir="${scriptDir}/bin/.assets_staging"
assetsArchivePath="${scriptDir}/bin/assets.pkg"

if [[ "${doBuild}" == "true" ]]; then
    rm -rf "${assetsStagingDir}"
    mkdir -p "${assetsStagingDir}/julia"
    mkdir -p "${assetsStagingDir}/shaders"

    cd "${scriptDir}/src"
    echo "Building Odin..."
    odin build main.odin -file \
        -out:../bin/euclid \
        -extra-linker-flags:"${juliaFlags}"
    echo "Build exited $?"

    cp -R "${scriptDir}/src/julia/." "${assetsStagingDir}/julia/"
    cp -R "${scriptDir}/src/view/shaders/." "${assetsStagingDir}/shaders/"

    cat > "${assetsStagingDir}/manifest.txt" <<EOF
package=assets.pkg
julia_root=julia
shader_root=shaders
format=tar.gz
EOF

    tar -C "${assetsStagingDir}" -czf "${assetsArchivePath}" .
    rm -rf "${assetsStagingDir}"
fi

cd "${scriptDir}"

if [[ "${runAfterBuild}" == "true" ]]; then
    cd "${scriptDir}/bin/"
    ./euclid
    cd "${scriptDir}"
fi
