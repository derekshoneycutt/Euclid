param(
    [Parameter(ValueFromRemainingArguments = $true)]
    [string[]] $CliArgs
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

if ($null -eq $CliArgs) {
    $CliArgs = @()
}

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$runAfterBuild = $false
$doBuild = $true

function Stop-Build([string] $message) {
    Write-Error $message
    exit 1
}

function Test-RequiredCommand([string] $commandName, [string] $installHint) {
    if (-not (Get-Command $commandName -ErrorAction SilentlyContinue)) {
        Stop-Build "Error: $commandName is required but not installed or not on PATH.`n$installHint"
    }
}

function Resolve-LibExePath() {
    $vswherePath = Join-Path ${env:ProgramFiles(x86)} "Microsoft Visual Studio/Installer/vswhere.exe"
    if (-not (Test-Path $vswherePath)) {
        Stop-Build "Error: Could not locate vswhere.exe. Install Visual Studio Build Tools."
    }

    $libExePath = & $vswherePath -latest -products * -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -find "VC/Tools/MSVC/**/bin/Hostx64/x64/lib.exe" | Select-Object -First 1
    if ([string]::IsNullOrWhiteSpace($libExePath) -or -not (Test-Path $libExePath)) {
        Stop-Build "Error: Could not locate MSVC lib.exe. Install the C++ Build Tools workload."
    }

    return $libExePath
}

function New-ImportLibrary(
    [string] $dllPath,
    [string] $defPath,
    [string] $outLibPath,
    [string] $dllName,
    [string] $libExePath,
    [bool] $stripDataMarkers = $false
) {
    $needsRebuild = -not (Test-Path $outLibPath)
    if (-not $needsRebuild) {
        $dllTime = (Get-Item $dllPath).LastWriteTimeUtc
        $libTime = (Get-Item $outLibPath).LastWriteTimeUtc
        if ($dllTime -gt $libTime) {
            $needsRebuild = $true
        }
    }

    if (-not $needsRebuild) {
        return
    }

    Push-Location (Split-Path -Parent $defPath)
    try {
        $oldErrorActionPreference = $ErrorActionPreference
        $ErrorActionPreference = "Continue"

        $nativePrefVar = Get-Variable -Name PSNativeCommandUseErrorActionPreference -ErrorAction SilentlyContinue
        if ($null -ne $nativePrefVar) {
            $oldNativeErrorPreference = $PSNativeCommandUseErrorActionPreference
            $PSNativeCommandUseErrorActionPreference = $false
        }

        $gendefCommand = "gendef `"$dllPath`" >NUL 2>NUL"
        cmd /c $gendefCommand | Out-Null
        $gendefExitCode = $LASTEXITCODE
        if ($gendefExitCode -ne 0 -or -not (Test-Path $defPath)) {
            Stop-Build "Error: Failed to generate DEF file for $dllName"
        }

        if ($stripDataMarkers) {
            (Get-Content $defPath) -replace " DATA$", "" | Set-Content -Path $defPath -Encoding ascii
        }

        $libCommand = "`"$libExePath`" /def:`"$defPath`" /machine:x64 /name:$dllName /out:`"$outLibPath`" >NUL"
        cmd /c $libCommand | Out-Null
        $libExitCode = $LASTEXITCODE
        if ($libExitCode -ne 0 -or -not (Test-Path $outLibPath)) {
            Stop-Build "Error: Failed to generate import library for $dllName"
        }
    }
    finally {
        $ErrorActionPreference = $oldErrorActionPreference
        if ($null -ne $nativePrefVar) {
            $PSNativeCommandUseErrorActionPreference = $oldNativeErrorPreference
        }
        Pop-Location
    }
}

if ($CliArgs.Count -gt 1) {
    Stop-Build "Usage: .\\make.ps1 [--run|--run-only|--clean]"
}

if ($CliArgs.Count -eq 1) {
    switch ($CliArgs[0]) {
        "--run" {
            $runAfterBuild = $true
        }
        "--run-only" {
            $runAfterBuild = $true
            $doBuild = $false
        }
        "--clean" {
            $binPath = Join-Path $scriptDir "bin"
            if (Test-Path $binPath) {
                Remove-Item -Recurse -Force $binPath
            }
            exit 0
        }
        default {
            Stop-Build "Usage: .\\make.ps1 [--run|--run-only|--clean]"
        }
    }
}

Test-RequiredCommand -commandName "julia" -installHint "Please install Julia to continue."
Test-RequiredCommand -commandName "odin" -installHint "Please install Odin to continue."
Test-RequiredCommand -commandName "tar" -installHint "Please install tar to continue."
Test-RequiredCommand -commandName "gendef" -installHint "Install gendef (for example via Strawberry Perl or MSYS2) to generate import libraries."

$juliaBinDir = (& julia -e "print(Sys.BINDIR)" | Out-String).Trim()
if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($juliaBinDir)) {
    Stop-Build "Error: Could not resolve Julia Sys.BINDIR."
}

$libjuliaDll = Join-Path $juliaBinDir "libjulia.dll"
$libopenlibmDll = Join-Path $juliaBinDir "libopenlibm.dll"
if (-not (Test-Path $libjuliaDll)) {
    Stop-Build "Error: Missing Julia runtime DLL at $libjuliaDll"
}
if (-not (Test-Path $libopenlibmDll)) {
    Stop-Build "Error: Missing Julia runtime DLL at $libopenlibmDll"
}

$importLibDir = Join-Path $scriptDir "bin/.julia_import_libs"
New-Item -ItemType Directory -Force -Path $importLibDir | Out-Null

$libExePath = Resolve-LibExePath
New-ImportLibrary -dllPath $libjuliaDll -defPath (Join-Path $importLibDir "libjulia.def") -outLibPath (Join-Path $importLibDir "julia.lib") -dllName "libjulia.dll" -libExePath $libExePath -stripDataMarkers $true
New-ImportLibrary -dllPath $libopenlibmDll -defPath (Join-Path $importLibDir "libopenlibm.def") -outLibPath (Join-Path $importLibDir "openlibm.lib") -dllName "libopenlibm.dll" -libExePath $libExePath

$juliaLinkerFlags = "/LIBPATH:$importLibDir /DEFAULTLIB:julia.lib /DEFAULTLIB:openlibm.lib"

$assetsStagingDir = Join-Path $scriptDir "bin/.assets_staging"
$assetsArchivePath = Join-Path $scriptDir "bin/assets.pkg"

if ($doBuild) {
    if (Test-Path $assetsStagingDir) {
        Remove-Item -Recurse -Force $assetsStagingDir
    }

    New-Item -ItemType Directory -Force -Path (Join-Path $assetsStagingDir "julia") | Out-Null
    New-Item -ItemType Directory -Force -Path (Join-Path $assetsStagingDir "shaders") | Out-Null

    Push-Location (Join-Path $scriptDir "src")
    try {
        Write-Host "Building Odin..."
        & odin build main.odin -file "-out:../bin/euclid.exe" "-extra-linker-flags:$juliaLinkerFlags"
        $buildExitCode = $LASTEXITCODE
        Write-Host "Build exited $buildExitCode"
        if ($buildExitCode -ne 0) {
            exit $buildExitCode
        }
    }
    finally {
        Pop-Location
    }

    Copy-Item -Path (Join-Path $scriptDir "src/julia/*") -Destination (Join-Path $assetsStagingDir "julia") -Recurse -Force
    Copy-Item -Path (Join-Path $scriptDir "src/view/shaders/*") -Destination (Join-Path $assetsStagingDir "shaders") -Recurse -Force
    Copy-Item -Path (Join-Path $scriptDir "assets/*") -Destination $assetsStagingDir -Recurse -Force

    @"
package=assets.pkg
julia_root=julia
shader_root=shaders
format=tar.gz
"@ | Set-Content -Path (Join-Path $assetsStagingDir "manifest.txt") -Encoding ascii

    & tar -C $assetsStagingDir -czf $assetsArchivePath .
    if ($LASTEXITCODE -ne 0) {
        Stop-Build "Error: Failed to package assets archive."
    }

    Remove-Item -Recurse -Force $assetsStagingDir
}

if ($runAfterBuild) {
    $windowsBinary = Join-Path $scriptDir "bin/euclid.exe"
    if (-not (Test-Path $windowsBinary)) {
        Stop-Build "Error: Built binary not found in bin/."
    }

    $originalPath = $env:PATH
    $env:PATH = "$juliaBinDir;$originalPath"
    try {
        & $windowsBinary
    }
    finally {
        $env:PATH = $originalPath
    }
}
