#!/usr/bin/env bash

set -euo pipefail

scriptDir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

runAfterBuild=false
doBuild=true
doVet=false
doAssets=true

showHelp=false
hasInvalidArg=false

requestRun=false
requestBuild=false
requestVet=false
requestNoBuild=false
requestAssets=false
requestNoAssets=false

require_command() {
    local commandName="$1"
    local installHint="$2"
    if ! command -v "${commandName}" >/dev/null 2>&1; then
        echo "Error: ${commandName} is required but not installed or not on PATH." >&2
        echo "${installHint}" >&2
        exit 1
    fi
}

show_help() {
    cat <<EOF
Usage: ./make.sh [options]

Options:
  --build, -b     Build the project.
  --assets, -a    Build assets.pkg.
  --run, -r       Run bin/euclid after all other requests.
  --vet, -v       Build with validation flags.
  --no-build, -n  Skip any build (overrides --build and --vet).
  --no-assets, -x Skip assets.pkg build (overrides --assets).
  --help, -h      Show this help text.

Notes:
  - If no options are provided, the default is --build --assets.
  - That is, --build and --assets are essentially non-altering flags, included for visibility.
  - Short options can be combined, e.g. -rva or -bnx.
EOF
}

for arg in "$@"; do
    case "$arg" in
        --run)
            requestRun=true
            ;;
        --build)
            requestBuild=true
            ;;
        --assets)
            requestAssets=true
            ;;
        --vet)
            requestVet=true
            ;;
        --no-build)
            requestNoBuild=true
            ;;
        --no-assets)
            requestNoAssets=true
            ;;
        --help)
            showHelp=true
            ;;
        -[!-]*)
            shortFlags="${arg#-}"
            for ((i = 0; i < ${#shortFlags}; i++)); do
                shortFlag="${shortFlags:i:1}"
                case "$shortFlag" in
                    r)
                        requestRun=true
                        ;;
                    b)
                        requestBuild=true
                        ;;
                    a)
                        requestAssets=true
                        ;;
                    v)
                        requestVet=true
                        ;;
                    n)
                        requestNoBuild=true
                        ;;
                    x)
                        requestNoAssets=true
                        ;;
                    h)
                        showHelp=true
                        ;;
                    *)
                        hasInvalidArg=true
                        ;;
                esac
            done
            ;;
        *)
            hasInvalidArg=true
            ;;
    esac
done

if [[ "${hasInvalidArg}" == "true" ]]; then
    showHelp=true
fi

if [[ "${showHelp}" == "true" ]]; then
    if [[ "${hasInvalidArg}" == "true" ]]; then
        echo "Unsupported parameter provided." >&2
    fi
    show_help
    if [[ "${hasInvalidArg}" == "true" ]]; then
        exit 1
    fi
    exit 0
fi

runAfterBuild="${requestRun}"

if [[ "${requestNoBuild}" == "true" ]]; then
    doBuild=false
    doVet=false
elif [[ "${requestVet}" == "true" ]]; then
    doBuild=true
    doVet=true
elif [[ "${requestBuild}" == "true" ]]; then
    doBuild=true
    doVet=false
fi

if [[ "${requestNoAssets}" == "true" ]]; then
    doAssets=false
elif [[ "${requestAssets}" == "true" ]]; then
    doAssets=true
fi

if [[ "${requestAssets}" == "true" && "${requestBuild}" != "true" && "${requestVet}" != "true" && "${requestNoBuild}" != "true" ]]; then
    doBuild=false
fi

if [[ "${doBuild}" == "true" ]]; then
    require_command "julia" "Please install Julia to continue."
    require_command "odin" "Please install Odin to continue."
fi

if [[ "${doAssets}" == "true" ]]; then
    require_command "tar" "Please install tar to continue."
fi

juliaFlags=""
if [[ "${doBuild}" == "true" ]]; then
    juliaConfigPath="$(julia -e 'print(joinpath(Sys.BINDIR, Base.DATAROOTDIR, "julia", "julia-config.jl"))')"
    juliaFlags="$(${juliaConfigPath} --ldflags --ldlibs | tr '\n' ' ')"
fi

assetsStagingDir="${scriptDir}/bin/.assets_staging"
assetsArchivePath="${scriptDir}/bin/assets.pkg"

if [[ "${doBuild}" == "true" ]]; then
    rm -rf "${assetsStagingDir}"
    mkdir -p "${assetsStagingDir}/julia"
    mkdir -p "${assetsStagingDir}/shaders"

    cd "${scriptDir}/src"
    echo "Building Odin..."
    if [[ "${doVet}" == "true" ]]; then
        if odin build main.odin -file \
            -out:../bin/euclid \
            -extra-linker-flags:"${juliaFlags}" \
            -vet -strict-style -disallow-do -warnings-as-errors; then
            buildExitCode=0
        else
            buildExitCode=$?
        fi
        echo "Odin build exited ${buildExitCode}"
        if [[ "${buildExitCode}" -ne 0 ]]; then
            exit "${buildExitCode}"
        fi

        echo "Validating Julia..."
        if julia -e 'Meta.parseall(read("julia/script.jl", String))'; then
            juliaValidationExitCode=0
        else
            juliaValidationExitCode=$?
        fi
        echo "Julia validation exited ${juliaValidationExitCode}"
        if [[ "${juliaValidationExitCode}" -ne 0 ]]; then
            exit "${juliaValidationExitCode}"
        fi
    else
        if odin build main.odin -file \
            -out:../bin/euclid \
            -extra-linker-flags:"${juliaFlags}"; then
            buildExitCode=0
        else
            buildExitCode=$?
        fi
        echo "Build exited ${buildExitCode}"
        if [[ "${buildExitCode}" -ne 0 ]]; then
            exit "${buildExitCode}"
        fi
    fi

fi

if [[ "${doAssets}" == "true" ]]; then
    echo "Building assets package..."
    rm -rf "${assetsStagingDir}"
    mkdir -p "${assetsStagingDir}/julia"
    mkdir -p "${assetsStagingDir}/shaders"

    cp -R "${scriptDir}/src/julia/." "${assetsStagingDir}/julia/"
    cp -R "${scriptDir}/src/view/shaders/." "${assetsStagingDir}/shaders/"
    cp -R "${scriptDir}/assets/." "${assetsStagingDir}/"

    cat > "${assetsStagingDir}/manifest.txt" <<EOF
package=assets.pkg
julia_root=julia
shader_root=shaders
format=tar.gz
EOF

    if tar -C "${assetsStagingDir}" -czf "${assetsArchivePath}" .; then
        assetsExitCode=0
    else
        assetsExitCode=$?
    fi
    echo "Assets package build exited ${assetsExitCode}"
    if [[ "${assetsExitCode}" -ne 0 ]]; then
        exit "${assetsExitCode}"
    fi
    echo "Wrote ${assetsArchivePath}"
    rm -rf "${assetsStagingDir}"
fi

cd "${scriptDir}"

if [[ "${runAfterBuild}" == "true" ]]; then
    cd "${scriptDir}/bin/"
    ./euclid
    cd "${scriptDir}"
fi
