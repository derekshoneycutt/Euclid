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
runArgs=()

require_command() {
    local commandName="$1"
    local installHint="$2"
    if ! command -v "${commandName}" >/dev/null 2>&1; then
        echo "Error: ${commandName} is required but not installed or not on PATH." >&2
        echo "${installHint}" >&2
        exit 1
    fi
}

json_escape() {
    local input="$1"
    input="${input//\\/\\\\}"
    input="${input//\"/\\\"}"
    input="${input//$'\n'/ }"
    input="${input//$'\r'/ }"
    printf '%s' "$input"
}

collect_runtime_libs() {
    local binaryPath="$1"
    local osName
    osName="$(uname -s)"

    if [[ "$osName" == "Linux" ]]; then
        if ! command -v ldd >/dev/null 2>&1; then
            return
        fi

        while IFS= read -r line; do
            line="${line#"${line%%[![:space:]]*}"}"
            [[ -z "$line" ]] && continue
            libName="${line%% *}"
            [[ -z "$libName" || "$libName" == "statically" ]] && continue
            printf '%s\n' "$libName"
        done < <(ldd "$binaryPath" 2>/dev/null || true)
        return
    fi

    if [[ "$osName" == "Darwin" ]]; then
        if ! command -v otool >/dev/null 2>&1; then
            return
        fi

        while IFS= read -r line; do
            line="${line#"${line%%[![:space:]]*}"}"
            [[ -z "$line" ]] && continue
            libPath="${line%% *}"
            [[ -z "$libPath" ]] && continue
            printf '%s\n' "$libPath"
        done < <(otool -L "$binaryPath" 2>/dev/null | tail -n +2)
    fi
}

collect_julia_packages() {
    local juliaProjectDir="$1"

    if ! command -v julia >/dev/null 2>&1; then
        return
    fi

    julia --project="${juliaProjectDir}" -e '
        using Pkg
        deps = collect(values(Pkg.dependencies()))
        direct = filter(d -> d.is_direct_dep, deps)
        sort!(direct, by = d -> lowercase(d.name))
        for d in direct
            version = isnothing(d.version) ? "stdlib" : string(d.version)
            println(d.name, "|", version)
        end
    ' 2>/dev/null || true
}

write_runtime_sbom() {
    local binaryPath="$1"
    local assetsPath="$2"
    local outputPath="$3"
    local juliaProjectDir="$4"

    local timestamp
    timestamp="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"

    local serialUuid
    serialUuid="$(julia -e 'using UUIDs; print(uuid4())' 2>/dev/null || true)"
    if [[ -z "$serialUuid" ]]; then
        serialUuid="00000000-0000-0000-0000-000000000000"
    fi

    mapfile -t runtimeLibs < <(collect_runtime_libs "$binaryPath")
    mapfile -t juliaPackages < <(collect_julia_packages "$juliaProjectDir")

    declare -A seenLibs=()
    runtimeLibsUnique=()
    for lib in "${runtimeLibs[@]}"; do
        [[ -z "$lib" ]] && continue
        if [[ -n "${seenLibs[$lib]+x}" ]]; then
            continue
        fi
        seenLibs["$lib"]=1
        runtimeLibsUnique+=("$lib")
    done

    declare -A seenJuliaPackages=()
    juliaPackagesUnique=()
    for pkgLine in "${juliaPackages[@]}"; do
        [[ -z "$pkgLine" || "$pkgLine" != *"|"* ]] && continue
        pkgName="${pkgLine%%|*}"
        pkgVersion="${pkgLine#*|}"
        [[ -z "$pkgName" ]] && continue
        pkgKey="${pkgName}|${pkgVersion}"
        if [[ -n "${seenJuliaPackages[$pkgKey]+x}" ]]; then
            continue
        fi
        seenJuliaPackages["$pkgKey"]=1
        juliaPackagesUnique+=("$pkgKey")
    done

    {
        printf '{\n'
        printf '  "$schema": "http://cyclonedx.org/schema/bom-1.6.schema.json",\n'
        printf '  "bomFormat": "CycloneDX",\n'
        printf '  "specVersion": "1.6",\n'
        printf '  "serialNumber": "urn:uuid:%s",\n' "$(json_escape "$serialUuid")"
        printf '  "version": 1,\n'
        printf '  "metadata": {\n'
        printf '    "timestamp": "%s",\n' "$(json_escape "$timestamp")"
        printf '    "component": {\n'
        printf '      "type": "application",\n'
        printf '      "bom-ref": "app:euclid",\n'
        printf '      "name": "EuclidApp",\n'
        printf '      "version": "dev"\n'
        printf '    }\n'
        printf '  },\n'
        printf '  "components": [\n'
        printf '    {\n'
        printf '      "type": "file",\n'
        printf '      "bom-ref": "file:bin/euclid",\n'
        printf '      "name": "bin/euclid",\n'
        printf '      "version": "dev",\n'
        printf '      "scope": "required"\n'
        printf '    },\n'
        printf '    {\n'
        printf '      "type": "file",\n'
        printf '      "bom-ref": "file:bin/assets.pkg",\n'
        printf '      "name": "bin/assets.pkg",\n'
        printf '      "version": "dev",\n'
        printf '      "scope": "required"\n'
        printf '    }'

        for lib in "${runtimeLibsUnique[@]}"; do
            printf ',\n'
            printf '    {\n'
            printf '      "type": "library",\n'
            printf '      "bom-ref": "runtime:%s",\n' "$(json_escape "$lib")"
            printf '      "name": "%s",\n' "$(json_escape "$lib")"
            printf '      "version": "unknown",\n'
            printf '      "scope": "required"\n'
            printf '    }'
        done

        for pkg in "${juliaPackagesUnique[@]}"; do
            pkgName="${pkg%%|*}"
            pkgVersion="${pkg#*|}"
            printf ',\n'
            printf '    {\n'
            printf '      "type": "library",\n'
            printf '      "bom-ref": "pkg:julia/%s",\n' "$(json_escape "$pkgName")"
            printf '      "name": "%s",\n' "$(json_escape "$pkgName")"
            printf '      "version": "%s",\n' "$(json_escape "$pkgVersion")"
            printf '      "scope": "required"\n'
            printf '    }'
        done

        printf '\n  ],\n'
        printf '  "dependencies": [\n'
        printf '    {\n'
        printf '      "ref": "app:euclid",\n'
        printf '      "dependsOn": [\n'
        printf '        "file:bin/euclid",\n'
        printf '        "file:bin/assets.pkg"'

        for lib in "${runtimeLibsUnique[@]}"; do
            printf ',\n'
            printf '        "runtime:%s"' "$(json_escape "$lib")"
        done

        for pkg in "${juliaPackagesUnique[@]}"; do
            pkgName="${pkg%%|*}"
            printf ',\n'
            printf '        "pkg:julia/%s"' "$(json_escape "$pkgName")"
        done

        printf '\n      ]\n'
        printf '    }\n'
        printf '  ]\n'
        printf '}\n'
    } > "$outputPath"
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
  --              Pass all remaining args directly to bin/euclid (only with --run).
  --help, -h      Show this help text.

Notes:
  - If no options are provided, the default is --build --assets.
  - That is, --build and --assets are essentially non-altering flags, included for visibility.
  - Short options can be combined, e.g. -rva or -bnx.
EOF
}

argIndex=0
argsCount=$#
while [[ ${argIndex} -lt ${argsCount} ]]; do
    arg="${@:$((argIndex + 1)):1}"

    case "$arg" in
        --)
            shiftCount=$((argIndex + 1))
            if [[ ${shiftCount} -lt $# ]]; then
                runArgs=("${@:$((shiftCount + 1))}")
            fi
            break
            ;;
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

    argIndex=$((argIndex + 1))
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
    require_command "julia" "Please install Julia to continue."
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

    if julia --project="${scriptDir}/src/julia" -e 'using Pkg; Pkg.instantiate(); Pkg.precompile()'; then
        juliaPackagesExitCode=0
    else
        juliaPackagesExitCode=$?
    fi
    echo "Julia package init exited ${juliaPackagesExitCode}"
    if [[ "${juliaPackagesExitCode}" -ne 0 ]]; then
        exit "${juliaPackagesExitCode}"
    fi

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
    rm -rf "${assetsStagingDir}"
    if [[ "${assetsExitCode}" -ne 0 ]]; then
        exit "${assetsExitCode}"
    fi
    echo "Wrote ${assetsArchivePath}"

    if [[ "${doBuild}" == "true" ]]; then
        runtimeSbomPath="${scriptDir}/bin/runtime-closure.generated.cdx.json"
        write_runtime_sbom "${scriptDir}/bin/euclid" "${assetsArchivePath}" "${runtimeSbomPath}" "${scriptDir}/src/julia"
        echo "Wrote ${runtimeSbomPath}"
    fi
fi

cd "${scriptDir}"

if [[ "${runAfterBuild}" == "true" ]]; then
    cd "${scriptDir}/bin/"
    ./euclid "${runArgs[@]}"
    cd "${scriptDir}"
fi
