<#
.SYNOPSIS
    Standard Windows entry point for Euclid, mirroring the Makefile.

.DESCRIPTION
    A thin, conventional wrapper around the project's real build system: the
    `configure` script (toolchain check + Julia dependency install) and
    `make.jl` (the actual build/test/vet driver). It exists so that Windows
    users get the same one-word shortcuts as the Makefile provides on
    Linux/macOS. All real logic lives in `configure` and `make.jl`.

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

# Run the configure script and record completion so it is not re-run needlessly.
function Invoke-Configure {
    & (Join-Path $ScriptDir "configure")
    if ($LASTEXITCODE -ne 0) {
        Write-Host "configure failed." -ForegroundColor Red
        Exit $LASTEXITCODE
    }
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
