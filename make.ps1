<#
.SYNOPSIS
    Standard Windows entry point for Euclid, mirroring the Makefile.

.DESCRIPTION
    A thin, conventional wrapper around the project's real build system:
    configure (toolchain check + Julia dependency install, performed natively by
    this script) and tools/make.jl (the actual build/test/vet driver). It exists
    so that Windows users get the same one-word shortcuts as the Makefile
    provides on Linux/macOS.

.EXAMPLE
    .\make.ps1            # configure (first run) + build
    .\make.ps1 test       # full verification gate (vet + tests)
    .\make.ps1 run        # build and run the application
    .\make.ps1 help       # show the underlying make.jl help
#>
param(
    [Parameter(Position = 0)]
    [string]$Target = "build"
)

$ErrorActionPreference = "Stop"
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
Set-Location $ScriptDir

$ConfigureStamp = Join-Path $ScriptDir ".configure-done"
$JuliaProject = Join-Path $ScriptDir "src\julia"
$AnalysisProject = Join-Path $ScriptDir "tools\analysis"

# Return whether a command is available on PATH, printing the result.
function Test-Dependency ([string]$Name) {
    $found = Get-Command $Name -ErrorAction SilentlyContinue
    if (-not $found) {
        Write-Host "Required dependency missing: $Name" -ForegroundColor Red
        return $false
    }
    Write-Host "Found $Name at: $($found.Source)" -ForegroundColor Green
    return $true
}

# Instantiate one Julia project, exiting when the step fails.
function Install-JuliaProject ([string]$Project, [string]$Label) {
    Write-Host "Installing Julia $Label dependencies..." -ForegroundColor Cyan
    & julia "--project=$Project" -e 'using Pkg; Pkg.instantiate(); Pkg.precompile()'
    if ($LASTEXITCODE -ne 0) {
        Write-Host "Failed to install Julia $Label dependencies." -ForegroundColor Red
        Exit $LASTEXITCODE
    }
}

# Verify the toolchain and install Julia dependencies, then record completion
# so configure is not re-run needlessly.
function Invoke-Configure {
    Write-Host "--- Configuring Project (Windows / PowerShell) ---" -ForegroundColor Cyan

    $ready = $true
    if (-not (Test-Dependency "odin"))  { $ready = $false }
    if (-not (Test-Dependency "julia")) { $ready = $false }

    if (-not $env:VCINSTALLDIR -and -not $env:INCLUDE) {
        Write-Warning "MSVC environment variables not detected. Checking for cl.exe..."
        if (-not (Test-Dependency "cl")) { $ready = $false }
    } else {
        Write-Host "MSVC Environment detected via VCINSTALLDIR." -ForegroundColor Green
    }

    # gendef bridges the toolchain gap: Julia is not built with the toolchain
    # Odin uses to build binaries.
    if (-not (Test-Dependency "gendef")) { $ready = $false }

    if (-not $ready) {
        Write-Host "Configuration failed! Please install the missing tools and add them to your PATH." -ForegroundColor Red
        Exit 1
    }

    # The analysis engine lives in a submodule; fail clearly when it is missing.
    # Analyzer packages must stay isolated to their own project environment.
    if (-not (Test-Path (Join-Path $AnalysisProject "Project.toml"))) {
        Write-Host "Analysis submodule missing at tools/analysis." -ForegroundColor Red
        Write-Host "Run: git submodule update --init --recursive" -ForegroundColor Red
        Exit 1
    }

    Install-JuliaProject $JuliaProject "application"
    Install-JuliaProject $AnalysisProject "analysis"

    Write-Host "Configuration successful! Toolchain and Julia dependencies are ready." -ForegroundColor Green
    New-Item -ItemType File -Path $ConfigureStamp -Force | Out-Null
}

# Ensure configure has run at least once (mirrors the Makefile's stamp logic).
function Ensure-Configured {
    if (-not (Test-Path $ConfigureStamp)) {
        Invoke-Configure
    }
}

# Invoke the make.jl driver with the given arguments, preserving the exit code.
function Invoke-MakeJl {
    param([string[]]$Arguments)
    & julia (Join-Path $ScriptDir "tools\make.jl") @Arguments
    if ($LASTEXITCODE -ne 0) {
        Exit $LASTEXITCODE
    }
}

switch ($Target.ToLowerInvariant()) {
    { $_ -in "build", "all", "" } {
        Ensure-Configured
        Invoke-MakeJl @()
    }
    "run" {
        Ensure-Configured
        Invoke-MakeJl @("--run")
    }
    { $_ -in "test", "check" } {
        Ensure-Configured
        Invoke-MakeJl @("--vet", "--test")
    }
    "vet" {
        Ensure-Configured
        Invoke-MakeJl @("--vet")
    }
    "sysimage" {
        Ensure-Configured
        Invoke-MakeJl @("--sysimage")
    }
    "harness" {
        Ensure-Configured
        Invoke-MakeJl @("--harness")
    }
    "wiki" {
        Ensure-Configured
        Invoke-MakeJl @("--wiki")
    }
    "check-wiki" {
        Ensure-Configured
        Invoke-MakeJl @("--check-wiki")
    }
    "configure" {
        Invoke-Configure
    }
    "clean" {
        Invoke-MakeJl @("--clean")
        if (Test-Path $ConfigureStamp) {
            Remove-Item $ConfigureStamp -Force
        }
    }
    "help" {
        Invoke-MakeJl @("--help")
    }
    default {
        Write-Host "Unknown target: $Target" -ForegroundColor Red
        Write-Host "Valid targets: build, run, test, check, vet, sysimage, harness, wiki, check-wiki, configure, clean, help"
        Exit 2
    }
}
