param(
    [Parameter(ValueFromRemainingArguments = $true)]
    [object[]] $CliArgs
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

if ($null -eq $CliArgs) {
    $CliArgs = @()
}

function Convert-ToCliStringArray([object[]] $rawArgs) {
    $normalized = New-Object System.Collections.Generic.List[string]
    foreach ($rawArg in $rawArgs) {
        if ($null -eq $rawArg) {
            continue
        }

        if ($rawArg -is [System.Collections.IEnumerable] -and -not ($rawArg -is [string])) {
            foreach ($nestedArg in $rawArg) {
                if ($null -ne $nestedArg) {
                    [void]$normalized.Add([string]$nestedArg)
                }
            }
            continue
        }

        [void]$normalized.Add([string]$rawArg)
    }

    return $normalized.ToArray()
}

$CliArgs = Convert-ToCliStringArray -rawArgs $CliArgs

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$runAfterBuild = $false
$doBuild = $true
$doVet = $false
$doAssets = $true

$showHelp = $false
$hasInvalidArg = $false

$requestRun = $false
$requestBuild = $false
$requestVet = $false
$requestNoBuild = $false
$requestAssets = $false
$requestNoAssets = $false
$runArgs = @()

function Stop-Build([string] $message) {
    Write-Error $message
    exit 1
}

function Show-Help() {
        @"
Usage: .\make.ps1 [options]

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
"@
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

function Resolve-DumpbinPath() {
    $vswherePath = Join-Path ${env:ProgramFiles(x86)} "Microsoft Visual Studio/Installer/vswhere.exe"
    if (-not (Test-Path $vswherePath)) {
        return $null
    }

    $dumpbinPath = & $vswherePath -latest -products * -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -find "VC/Tools/MSVC/**/bin/Hostx64/x64/dumpbin.exe" | Select-Object -First 1
    if ([string]::IsNullOrWhiteSpace($dumpbinPath) -or -not (Test-Path $dumpbinPath)) {
        return $null
    }

    return $dumpbinPath
}

function Get-RuntimeDependencies([string] $binaryPath) {
    $dependencies = New-Object System.Collections.Generic.List[string]

    $dumpbinPath = Resolve-DumpbinPath
    if ([string]::IsNullOrWhiteSpace($dumpbinPath)) {
        return $dependencies
    }

    $dumpOutput = & $dumpbinPath /dependents $binaryPath 2>$null
    if ($LASTEXITCODE -ne 0) {
        return $dependencies
    }

    $inDependencies = $false
    foreach ($line in $dumpOutput) {
        if ($line -match "Image has the following dependencies") {
            $inDependencies = $true
            continue
        }

        if (-not $inDependencies) {
            continue
        }

        $trimmed = $line.Trim()
        if ([string]::IsNullOrWhiteSpace($trimmed)) {
            continue
        }

        if ($trimmed -match "^Summary$") {
            break
        }

        if (-not $dependencies.Contains($trimmed)) {
            [void]$dependencies.Add($trimmed)
        }
    }

    return $dependencies
}

function Get-JuliaDirectPackages([string] $projectPath) {
    $packages = New-Object System.Collections.Generic.List[object]

    $output = & julia --project=$projectPath -e 'using Pkg; deps = collect(values(Pkg.dependencies())); direct = filter(d -> d.is_direct_dep, deps); sort!(direct, by = d -> lowercase(d.name)); for d in direct; version = isnothing(d.version) ? "stdlib" : string(d.version); println(d.name, "|", version); end' 2>$null
    if ($LASTEXITCODE -ne 0) {
        return $packages
    }

    $seen = New-Object System.Collections.Generic.HashSet[string]
    foreach ($line in $output) {
        $trimmed = $line.Trim()
        if ([string]::IsNullOrWhiteSpace($trimmed) -or -not $trimmed.Contains("|")) {
            continue
        }

        $parts = $trimmed.Split("|", 2)
        $name = $parts[0].Trim()
        $version = $parts[1].Trim()
        if ([string]::IsNullOrWhiteSpace($name)) {
            continue
        }

        $key = "$name|$version"
        if (-not $seen.Add($key)) {
            continue
        }

        [void]$packages.Add([ordered]@{
            name = $name
            version = $version
        })
    }

    return $packages
}

function Write-RuntimeSbom([string] $binaryPath, [string] $assetsPath, [string] $outputPath, [string] $juliaProjectPath) {
    $timestamp = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
    $serialNumber = "urn:uuid:$([guid]::NewGuid().ToString())"

    $runtimeDependencies = Get-RuntimeDependencies -binaryPath $binaryPath
    $juliaPackages = Get-JuliaDirectPackages -projectPath $juliaProjectPath

    $components = New-Object System.Collections.Generic.List[object]
    [void]$components.Add([ordered]@{
        type = "file"
        "bom-ref" = "file:bin/euclid.exe"
        name = "bin/euclid.exe"
        version = "dev"
        scope = "required"
    })
    [void]$components.Add([ordered]@{
        type = "file"
        "bom-ref" = "file:bin/assets.pkg"
        name = "bin/assets.pkg"
        version = "dev"
        scope = "required"
    })

    foreach ($dependency in $runtimeDependencies) {
        [void]$components.Add([ordered]@{
            type = "library"
            "bom-ref" = "runtime:$dependency"
            name = $dependency
            version = "unknown"
            scope = "required"
        })
    }

    foreach ($package in $juliaPackages) {
        [void]$components.Add([ordered]@{
            type = "library"
            "bom-ref" = "pkg:julia/$($package.name)"
            name = $package.name
            version = $package.version
            scope = "required"
        })
    }

    $dependsOn = New-Object System.Collections.Generic.List[string]
    [void]$dependsOn.Add("file:bin/euclid.exe")
    [void]$dependsOn.Add("file:bin/assets.pkg")
    foreach ($dependency in $runtimeDependencies) {
        [void]$dependsOn.Add("runtime:$dependency")
    }
    foreach ($package in $juliaPackages) {
        [void]$dependsOn.Add("pkg:julia/$($package.name)")
    }

    $bom = [ordered]@{
        '$schema' = "http://cyclonedx.org/schema/bom-1.6.schema.json"
        bomFormat = "CycloneDX"
        specVersion = "1.6"
        serialNumber = $serialNumber
        version = 1
        metadata = [ordered]@{
            timestamp = $timestamp
            component = [ordered]@{
                type = "application"
                "bom-ref" = "app:euclid"
                name = "EuclidApp"
                version = "dev"
            }
        }
        components = $components
        dependencies = @(
            [ordered]@{
                ref = "app:euclid"
                dependsOn = $dependsOn
            }
        )
    }

    $json = $bom | ConvertTo-Json -Depth 12
    $json | Set-Content -Path $outputPath -Encoding ascii
}

function New-ImportLibrary(
    [string] $dllPath,
    [string] $defPath,
    [string] $outLibPath,
    [string] $dllName,
    [string] $libExePath,
    [bool] $stripDataMarkers = $false) {
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

for ($argIndex = 0; $argIndex -lt $CliArgs.Count; $argIndex++) {
    $arg = $CliArgs[$argIndex]

    if ($arg -eq "--") {
        if (($argIndex + 1) -lt $CliArgs.Count) {
            $runArgs = $CliArgs[($argIndex + 1)..($CliArgs.Count - 1)]
        }
        break
    }

    switch -Regex ($arg) {
        '^--run$' {
            $requestRun = $true
            continue
        }
        '^--build$' {
            $requestBuild = $true
            continue
        }
        '^--assets$' {
            $requestAssets = $true
            continue
        }
        '^--vet$' {
            $requestVet = $true
            continue
        }
        '^--no-build$' {
            $requestNoBuild = $true
            continue
        }
        '^--no-assets$' {
            $requestNoAssets = $true
            continue
        }
        '^--help$' {
            $showHelp = $true
            continue
        }
        '^-[^-].*$' {
            $shortFlags = $arg.Substring(1)
            foreach ($shortFlag in $shortFlags.ToCharArray()) {
                switch ($shortFlag) {
                    'r' {
                        $requestRun = $true
                    }
                    'b' {
                        $requestBuild = $true
                    }
                    'a' {
                        $requestAssets = $true
                    }
                    'v' {
                        $requestVet = $true
                    }
                    'n' {
                        $requestNoBuild = $true
                    }
                    'x' {
                        $requestNoAssets = $true
                    }
                    'h' {
                        $showHelp = $true
                    }
                    default {
                        $hasInvalidArg = $true
                    }
                }
            }
            continue
        }
        default {
            if ($requestRun) {
                $runArgs = $CliArgs[$argIndex..($CliArgs.Count - 1)]
                break
            }
            $hasInvalidArg = $true
        }
    }
}

if ($hasInvalidArg) {
    $showHelp = $true
}

if ($showHelp) {
    if ($hasInvalidArg) {
        Write-Error "Unsupported parameter provided."
    }
    Show-Help
    if ($hasInvalidArg) {
        exit 1
    }
    exit 0
}

$runAfterBuild = $requestRun

if ($requestNoBuild) {
    $doBuild = $false
    $doVet = $false
}
elseif ($requestVet) {
    $doBuild = $true
    $doVet = $true
}
elseif ($requestBuild) {
    $doBuild = $true
    $doVet = $false
}

if ($requestNoAssets) {
    $doAssets = $false
}
elseif ($requestAssets) {
    $doAssets = $true
}

if ($requestAssets -and -not $requestBuild -and -not $requestVet -and -not $requestNoBuild) {
    $doBuild = $false
}

$juliaBinDir = $null
if ($doBuild -or $doAssets -or $runAfterBuild) {
    Test-RequiredCommand -commandName "julia" -installHint "Please install Julia to continue."
    $juliaBinDir = (& julia -e "print(Sys.BINDIR)" | Out-String).Trim()
    if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($juliaBinDir)) {
        Stop-Build "Error: Could not resolve Julia Sys.BINDIR."
    }
}

if ($doBuild) {
    Test-RequiredCommand -commandName "odin" -installHint "Please install Odin to continue."
    Test-RequiredCommand -commandName "gendef" -installHint "Install gendef (for example via Strawberry Perl or MSYS2) to generate import libraries."
}

if ($doAssets) {
    Test-RequiredCommand -commandName "tar" -installHint "Please install tar to continue."
}

$juliaLinkerFlags = ""
if ($doBuild) {
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
}

$assetsStagingDir = Join-Path $scriptDir "bin/.assets_staging"
$assetsArchivePath = Join-Path $scriptDir "bin/assets.pkg"

if ($doBuild) {
    Push-Location (Join-Path $scriptDir "src")
    try {
        Write-Host "Building Odin..."
        if ($doVet) {
            & odin build main.odin -file "-out:../bin/euclid.exe" "-extra-linker-flags:$juliaLinkerFlags" -vet -strict-style -disallow-do -warnings-as-errors
            $buildExitCode = $LASTEXITCODE
            Write-Host "Odin build exited $buildExitCode"
            if ($buildExitCode -ne 0) {
                exit $buildExitCode
            }

            Write-Host "Validating Julia..."
            & julia -e 'Meta.parseall(read("julia/script.jl", String))'
            $juliaValidationExitCode = $LASTEXITCODE
            Write-Host "Julia validation exited $juliaValidationExitCode"
            if ($juliaValidationExitCode -ne 0) {
                exit $juliaValidationExitCode
            }
        }
        else {
            & odin build main.odin -file "-out:../bin/euclid.exe" "-extra-linker-flags:$juliaLinkerFlags"
            $buildExitCode = $LASTEXITCODE
            Write-Host "Build exited $buildExitCode"
            if ($buildExitCode -ne 0) {
                exit $buildExitCode
            }
        }
    }
    finally {
        Pop-Location
    }
}

if ($doAssets) {
    Write-Host "Building assets package..."

    & julia --project=(Join-Path $scriptDir "src/julia") -e 'using Pkg; Pkg.instantiate(); Pkg.precompile()'
    $juliaPackagesExitCode = $LASTEXITCODE
    Write-Host "Julia package init exited $juliaPackagesExitCode"
    if ($juliaPackagesExitCode -ne 0) {
        exit $juliaPackagesExitCode
    }

    if (Test-Path $assetsStagingDir) {
        Remove-Item -Recurse -Force $assetsStagingDir
    }

    New-Item -ItemType Directory -Force -Path (Join-Path $assetsStagingDir "julia") | Out-Null
    New-Item -ItemType Directory -Force -Path (Join-Path $assetsStagingDir "shaders") | Out-Null

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
    $assetsExitCode = $LASTEXITCODE
    Write-Host "Assets package build exited $assetsExitCode"
    Remove-Item -Recurse -Force $assetsStagingDir
    if ($LASTEXITCODE -ne 0) {
        Stop-Build "Error: Failed to package assets archive."
    }
    Write-Host "Wrote $assetsArchivePath"

    if ($doBuild) {
        $runtimeSbomPath = Join-Path $scriptDir "bin/runtime-closure.generated.cdx.json"
        Write-RuntimeSbom -binaryPath (Join-Path $scriptDir "bin/euclid.exe") -assetsPath $assetsArchivePath -outputPath $runtimeSbomPath -juliaProjectPath (Join-Path $scriptDir "src/julia")
        Write-Host "Wrote $runtimeSbomPath"
    }
}

if ($runAfterBuild) {
    $windowsBinary = Join-Path $scriptDir "bin/euclid.exe"
    if (-not (Test-Path $windowsBinary)) {
        Stop-Build "Error: Built binary not found in bin/."
    }

    $originalPath = $env:PATH
    $env:PATH = "$juliaBinDir;$originalPath"
    try {
        & $windowsBinary @runArgs
    }
    finally {
        $env:PATH = $originalPath
    }
}
