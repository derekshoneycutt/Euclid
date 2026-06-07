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

if [[ "${1-}" == "--run" ]]; then
    runAfterBuild=true
elif [[ -n "${1-}" ]]; then
    echo "Usage: ./make.sh [--run]" >&2
    exit 1
fi

mkdir -p "${scriptDir}/bin/julia/"
mkdir -p "${scriptDir}/bin/shaders/"

cd "${scriptDir}/src"
odin build main.odin -file \
    -out:../bin/euclid \
    -extra-linker-flags:"${juliaFlags}"
cd julia
cp ./*.jl ../../bin/julia/
cd ../view/shaders
cp ./* ../../../bin/shaders/
cd "${scriptDir}"

if [[ "${runAfterBuild}" == "true" ]]; then
    cd "${scriptDir}/bin/"
    ./euclid
    cd "${scriptDir}"
fi
