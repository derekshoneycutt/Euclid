#!/bin/sh
# Verify the required toolchain and install the project's Julia dependencies.
# Broad POSIX sh for Linux and macOS; on Windows, make.ps1 performs the same
# steps natively in PowerShell. Safe to re-run; existing packages are left alone.
#
# Invoked by the Makefile; nobody needs to call this directly.
set -u

printf "\033[36m--- Configuring Project (sh) ---\033[0m\n"

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
JULIA_PROJECT="$SCRIPT_DIR/src/julia"
ANALYSIS_PROJECT="$SCRIPT_DIR/tools/analysis"

success=0

test_command() {
    if ! command -v "$1" >/dev/null 2>&1; then
        printf "\033[31mRequired dependency missing: %s\033[0m\n" "$1" >&2
        return 1
    fi
    printf "\033[32mFound %s at: %s\033[0m\n" "$1" "$(command -v "$1")"
    return 0
}

# Verify the core build tools are on PATH.
test_command "odin" || success=1
test_command "julia" || success=1
test_command "pkg-config" || success=1

if [ "$success" -ne 0 ]; then
    printf "\033[31mConfiguration failed! Please install the missing tools.\033[0m\n" >&2
    exit 1
fi

if ! pkg-config --exists harfbuzz; then
    printf "\033[31mRequired HarfBuzz development package was not found.\033[0m\n" >&2
    printf "\033[31mInstall harfbuzz-devel (Fedora) or libharfbuzz-dev (Debian/Ubuntu).\033[0m\n" >&2
    exit 1
fi

# Fail clearly when the analysis submodule is missing. Analyzer packages must
# stay isolated to their own project environment, never the default environment.
if [ ! -f "$ANALYSIS_PROJECT/Project.toml" ]; then
    printf "\033[31mAnalysis submodule missing at tools/analysis.\033[0m\n" >&2
    printf "\033[31mRun: git submodule update --init --recursive\033[0m\n" >&2
    exit 1
fi

# Install the application Julia project dependencies (src/julia/Project.toml).
printf "\033[36mInstalling Julia application dependencies...\033[0m\n"
if ! julia --project="$JULIA_PROJECT" -e 'using Pkg; Pkg.instantiate(); Pkg.precompile()'; then
    printf "\033[31mFailed to install Julia application dependencies.\033[0m\n" >&2
    exit 1
fi

# Install the analysis engine's Julia dependencies (tools/analysis/Project.toml).
printf "\033[36mInstalling Julia analysis dependencies...\033[0m\n"
if ! julia --project="$ANALYSIS_PROJECT" -e 'using Pkg; Pkg.instantiate(); Pkg.precompile()'; then
    printf "\033[31mFailed to install Julia analysis dependencies.\033[0m\n" >&2
    exit 1
fi

printf "\033[32mConfiguration successful! Toolchain and Julia dependencies are ready.\033[0m\n"
exit 0
