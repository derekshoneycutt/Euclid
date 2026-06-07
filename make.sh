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

runAfterBuild=false

if [[ "${1-}" == "--run" ]]; then
    runAfterBuild=true
elif [[ -n "${1-}" ]]; then
    echo "Usage: ./make.sh [--run]" >&2
    exit 1
fi

mkdir -p ./bin/julia/

cd src
odin build main.odin -file \
    -out:../bin/euclid \
    -extra-linker-flags:"${juliaFlags}"
cd julia
cp ./*.jl ../../bin/julia/
cd ../..

if [[ "${runAfterBuild}" == "true" ]]; then
    cd ./bin/
    ./euclid
    cd ..
fi
