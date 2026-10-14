#requires -Version 7.0
<#
Build the patched Windows installer locally. This script never installs build
tools, touches an existing source checkout, or removes build/source directories.
#>
[CmdletBinding()]
param(
    [string]$BuildRoot = (Join-Path $PSScriptRoot '../../.local/iloader'),
    [string[]]$ToolDirectories = @(),
    [Alias('Preflight')][switch]$CheckPrerequisites,
    [switch]$SelfTest,
    [string]$ArtifactsRoot
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $false
$TargetTriple = 'x86_64-pc-windows-msvc'

function Assert-ChildPath([string]$Parent, [string]$Child) {
    $parentPath = [IO.Path]::GetFullPath($Parent).TrimEnd([IO.Path]::DirectorySeparatorChar, [IO.Path]::AltDirectorySeparatorChar)
    $childPath = [IO.Path]::GetFullPath($Child)
    $prefix = $parentPath + [IO.Path]::DirectorySeparatorChar
    if (-not $childPath.StartsWith($prefix, [StringComparison]::OrdinalIgnoreCase)) {
        throw "Expected a path strictly inside '$parentPath', got '$childPath'."
    }
    return $childPath
}

function Resolve-ArtifactsRoot([string]$BuildDirectory, [string]$ArtifactsDirectory, [bool]$CustomBuildRoot) {
    if (-not [string]::IsNullOrWhiteSpace($ArtifactsDirectory)) {
        return [IO.Path]::GetFullPath($ArtifactsDirectory)
    }
    if ($CustomBuildRoot) {
        # Keep explicit -BuildRoot runs self-contained, as before relocation.
        return [IO.Path]::GetFullPath((Join-Path $BuildDirectory 'artifacts'))
    }
    return [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../build/iloader'))
}

function Invoke-Native([string]$File, [string[]]$Arguments) {
    & $File @Arguments
    if ($LASTEXITCODE -ne 0) {
        throw "$File failed (exit $LASTEXITCODE): $($Arguments -join ' ')"
    }
}

function Get-NativeOutput([string]$File, [string[]]$Arguments) {
    $output = & $File @Arguments
    if ($LASTEXITCODE -ne 0) {
        throw "$File failed (exit $LASTEXITCODE): $($Arguments -join ' ')"
    }
    return ($output -join "`n")
}

function Find-Application([string]$Name) {
    $command = Get-Command $Name -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($null -ne $command) { return $command.Source }
    return $null
}

function Add-ExistingToolDirectory([string]$Directory) {
    if (Test-Path -LiteralPath $Directory -PathType Container) {
        # Append so MSVC's link.exe keeps priority over Unix tools with that name.
        $env:PATH = $env:PATH + [IO.Path]::PathSeparator + $Directory
    }
}

function Enable-InstalledMSVC {
    if ($env:VSCMD_ARG_TGT_ARCH -eq 'x64' -and (Find-Application 'cl.exe') -and (Find-Application 'rc.exe')) {
        return
    }
    $vswhere = Find-Application 'vswhere.exe'
    if (-not $vswhere -and ${env:ProgramFiles(x86)}) {
        $candidate = Join-Path ${env:ProgramFiles(x86)} 'Microsoft Visual Studio/Installer/vswhere.exe'
        if (Test-Path -LiteralPath $candidate -PathType Leaf) { $vswhere = $candidate }
    }
    if (-not $vswhere) {
        throw 'Visual Studio Installer/vswhere.exe was not found. Install Visual Studio Build Tools with Desktop development with C++, MSVC x64/x86 tools, and a Windows 10/11 SDK; then retry.'
    }
    $installation = Get-NativeOutput $vswhere @('-latest', '-products', '*', '-requires', 'Microsoft.VisualStudio.Component.VC.Tools.x86.x64', '-property', 'installationPath')
    if ([string]::IsNullOrWhiteSpace($installation)) {
        throw 'No installed MSVC x64/x86 toolset was found. In Visual Studio Installer, add Desktop development with C++, MSVC x64/x86 tools, and a Windows 10/11 SDK.'
    }
    $developerCommand = Join-Path $installation.Trim() 'Common7/Tools/VsDevCmd.bat'
    if (-not (Test-Path -LiteralPath $developerCommand -PathType Leaf)) {
        throw "MSVC environment script is missing: $developerCommand. Repair that Visual Studio Build Tools installation."
    }
    if ($developerCommand -match '["\r\n]') { throw 'Invalid Visual Studio installation path.' }
    $commandLine = '"{0}" -no_logo -arch=x64 -host_arch=x64 >nul && set' -f $developerCommand
    $environmentText = Get-NativeOutput $env:ComSpec @('/d', '/s', '/c', $commandLine)
    foreach ($line in ($environmentText -split "`n")) {
        if ($line -match '^([^=]+)=(.*)$') {
            [Environment]::SetEnvironmentVariable($Matches[1], $Matches[2].TrimEnd("`r"), 'Process')
        }
    }
}

function Get-Prerequisites {
    $problems = [Collections.Generic.List[string]]::new()
    $tools = @{}
    if (-not $IsWindows) { throw 'Run this helper in PowerShell 7 on Windows.' }
    if (-not [Environment]::Is64BitProcess) { throw 'Use 64-bit PowerShell 7 for this x64 installer build.' }
    try { Enable-InstalledMSVC } catch { $problems.Add($_.Exception.Message) }

    foreach ($directory in $ToolDirectories) {
        if (-not (Test-Path -LiteralPath $directory -PathType Container)) {
            $problems.Add("Tool directory does not exist: $directory")
        } else {
            Add-ExistingToolDirectory ([IO.Path]::GetFullPath($directory))
        }
    }

    # Reuse the project's portable Strawberry Perl cache when available.
    Add-ExistingToolDirectory (Join-Path $PSScriptRoot '../../.local/device-tools/strawberry-perl/perl/bin')
    Add-ExistingToolDirectory (Join-Path $PSScriptRoot '../../.local/device-tools/strawberry-perl/c/bin')
    # Discover existing Strawberry Perl installations, without installing anything.
    if ($env:SystemDrive) {
        Add-ExistingToolDirectory (Join-Path $env:SystemDrive 'Strawberry/perl/bin')
        Add-ExistingToolDirectory (Join-Path $env:SystemDrive 'Strawberry/c/bin')
    }
    $requirements = [ordered]@{
        'git.exe' = 'Install Git for Windows and add Git to PATH.'
        'cargo.exe' = 'Install current Rust through rustup with the MSVC toolchain, then reopen PowerShell.'
        'rustc.exe' = 'Install current Rust through rustup with the MSVC toolchain, then reopen PowerShell.'
        'bun.exe' = 'Install Bun and add its bin directory to PATH.'
        'cl.exe' = 'Add the MSVC x64/x86 tools in Visual Studio Installer.'
        'link.exe' = 'Add the MSVC x64/x86 tools in Visual Studio Installer.'
        'rc.exe' = 'Add a Windows 10/11 SDK in Visual Studio Installer.'
        'perl.exe' = 'Install Strawberry Perl, or add your existing Perl bin directory to PATH.'
        'make.exe' = 'Install GNU make, or add an existing make.exe to PATH (Strawberry Perl may include it).'
    }
    foreach ($entry in $requirements.GetEnumerator()) {
        $tool = Find-Application $entry.Key
        if ($tool) { $tools[$entry.Key] = $tool }
        else { $problems.Add("Missing $($entry.Key). $($entry.Value)") }
    }
    if ($tools.ContainsKey('cl.exe') -and ([string]::IsNullOrWhiteSpace($env:INCLUDE) -or [string]::IsNullOrWhiteSpace($env:LIB))) {
        $problems.Add('MSVC headers/libraries are not configured. Repair the C++ workload and Windows SDK, or run from an x64 Developer PowerShell.')
    }
    if ($tools.ContainsKey('rustc.exe')) {
        try {
            $libDirectory = Get-NativeOutput $tools['rustc.exe'] @('--print', 'target-libdir', '--target', $TargetTriple)
            if (-not (Test-Path -LiteralPath $libDirectory.Trim() -PathType Container)) {
                $problems.Add("Rust standard library for $TargetTriple is missing. Run: rustup target add $TargetTriple")
            }
        } catch { $problems.Add($_.Exception.Message) }
    }
    if ($tools.ContainsKey('make.exe')) {
        try {
            if ((Get-NativeOutput $tools['make.exe'] @('--version')) -notmatch 'GNU Make') {
                $problems.Add('make.exe is not GNU Make. Put a GNU make installation on PATH.')
            }
        } catch { $problems.Add($_.Exception.Message) }
    }
    if ($problems.Count -gt 0) {
        throw ("Local build prerequisites are incomplete; no build was started:`n - " + ($problems -join "`n - "))
    }
    return $tools
}

function Assert-Dependencies($Metadata, [string]$ExpectedBackendManifest) {
    $backends = @($Metadata.packages | Where-Object name -eq 'isideload')
    if ($backends.Count -ne 1 -or $null -ne $backends[0].source) {
        throw 'Expected exactly one local isideload backend.'
    }
    if (-not [IO.Path]::GetFullPath($backends[0].manifest_path).Equals([IO.Path]::GetFullPath($ExpectedBackendManifest), [StringComparison]::OrdinalIgnoreCase)) {
        throw 'Cargo resolved an unexpected isideload checkout.'
    }
    if (@($Metadata.packages | Where-Object name -eq 'idevice').Count -ne 1) {
        throw 'Expected exactly one idevice version in the dependency graph.'
    }
}

function New-PinnedCheckout([string]$Git, [string]$Destination, [string]$Repository, [string]$Revision, [string]$Patch) {
    if (Test-Path -LiteralPath $Destination) { throw "Refusing to overwrite existing source directory: $Destination" }
    Invoke-Native $Git @('init', '--quiet', $Destination)
    Invoke-Native $Git @('-C', $Destination, 'remote', 'add', 'origin', $Repository)
    Invoke-Native $Git @('-C', $Destination, 'fetch', '--quiet', '--depth', '1', 'origin', $Revision)
    Invoke-Native $Git @('-C', $Destination, 'checkout', '--quiet', '--detach', 'FETCH_HEAD')
    $actual = Get-NativeOutput $Git @('-C', $Destination, 'rev-parse', 'HEAD')
    if ($actual.Trim() -ne $Revision) { throw "Unexpected upstream revision in $Destination" }
    Invoke-Native $Git @('-C', $Destination, 'apply', '--check', $Patch)
    Invoke-Native $Git @('-C', $Destination, 'apply', $Patch)
}

function Test-HelperLogic {
    $parentPath = [IO.Path]::GetFullPath((Join-Path ([IO.Path]::GetTempPath()) 'iloader-helper-check'))
    $childPath = Join-Path $parentPath 'sources/run-one'
    if ((Assert-ChildPath $parentPath $childPath) -ne [IO.Path]::GetFullPath($childPath)) { throw 'Child path test failed.' }
    foreach ($badPath in @($parentPath, ($parentPath + '-other'), (Join-Path $parentPath '../outside'))) {
        $rejected = $false
        try { $null = Assert-ChildPath $parentPath $badPath } catch { $rejected = $true }
        if (-not $rejected) { throw "Unsafe path was accepted: $badPath" }
    }
    $defaultArtifacts = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../build/iloader'))
    if ((Resolve-ArtifactsRoot $parentPath '' $false) -ne $defaultArtifacts) { throw 'Default artifacts path test failed.' }
    if ((Resolve-ArtifactsRoot $parentPath '' $true) -ne (Join-Path $parentPath 'artifacts')) { throw 'Custom build root compatibility test failed.' }
    $customArtifacts = Join-Path $parentPath 'separate-output'
    foreach ($customBuild in @($false, $true)) {
        if ((Resolve-ArtifactsRoot $parentPath $customArtifacts $customBuild) -ne $customArtifacts) { throw 'Explicit artifacts path test failed.' }
    }
    $manifest = Join-Path $parentPath 'isideload/isideload/Cargo.toml'
    $metadata = [pscustomobject]@{ packages = @(
        [pscustomobject]@{ name = 'isideload'; source = $null; manifest_path = $manifest },
        [pscustomobject]@{ name = 'idevice'; source = 'registry'; manifest_path = 'unused' }
    ) }
    Assert-Dependencies $metadata $manifest
    $metadata.packages[0].source = 'registry'
    $rejected = $false
    try { Assert-Dependencies $metadata $manifest } catch { $rejected = $true }
    if (-not $rejected) { throw 'Registry backend was accepted.' }
    $metadata.packages[0].source = $null
    $metadata.packages += $metadata.packages[1]
    $rejected = $false
    try { Assert-Dependencies $metadata $manifest } catch { $rejected = $true }
    if (-not $rejected) { throw 'Duplicate idevice packages were accepted.' }
    Write-Host 'Helper logic checks passed. No sources, dependencies or compiler were invoked.'
}

if ($SelfTest) { Test-HelperLogic; return }

$savedEnvironment = [Environment]::GetEnvironmentVariables('Process')
$originalLocation = Get-Location
$buildLock = $null
$runDirectory = $null
try {
    $tools = Get-Prerequisites
    foreach ($name in ($tools.Keys | Sort-Object)) { Write-Host "$name`: $($tools[$name])" }
    if ($CheckPrerequisites) {
        Write-Host 'Local build prerequisites are ready. No build was started.'
        return
    }

    $ArtifactsRoot = Resolve-ArtifactsRoot $BuildRoot $ArtifactsRoot ($PSBoundParameters.ContainsKey('BuildRoot'))
    $BuildRoot = [IO.Path]::GetFullPath($BuildRoot)
    $cache = Assert-ChildPath $BuildRoot (Join-Path $BuildRoot 'cache')
    $null = New-Item -ItemType Directory -Force -Path $cache
    try {
        $buildLock = [IO.File]::Open((Join-Path $cache 'build.lock'), [IO.FileMode]::OpenOrCreate, [IO.FileAccess]::ReadWrite, [IO.FileShare]::None)
    } catch { throw "Another local build is using '$BuildRoot', or its cache is not writable. Wait for it to finish or choose another -BuildRoot." }

    $runID = (Get-Date -Format 'yyyyMMdd-HHmmss') + '-' + [Guid]::NewGuid().ToString('N').Substring(0, 8)
    $runDirectory = Assert-ChildPath $BuildRoot (Join-Path $BuildRoot "sources/$runID")
    $outputDirectory = Assert-ChildPath $ArtifactsRoot (Join-Path $ArtifactsRoot $runID)
    if ((Test-Path -LiteralPath $runDirectory) -or (Test-Path -LiteralPath $outputDirectory)) { throw 'Build run directory already exists; refusing to overwrite it.' }
    $null = New-Item -ItemType Directory -Path $runDirectory
    $inputs = Join-Path $runDirectory 'build-inputs'
    $null = New-Item -ItemType Directory -Path $inputs
    foreach ($name in @('iloader.patch', 'isideload.patch', 'README.md', 'build-local.ps1')) {
        Copy-Item -LiteralPath (Join-Path $PSScriptRoot $name) -Destination (Join-Path $inputs $name)
    }

    $env:CARGO_TARGET_DIR = Join-Path $cache 'cargo-target'
    $env:BUN_INSTALL_CACHE_DIR = Join-Path $cache 'bun'
    $env:CARGO_BUILD_TARGET = $TargetTriple
    # CARGO_HOME remains unchanged: existing Cargo registry/git downloads are reused.
    $iloaderRevision = 'dc396af059fd46982062cd8fc90252d7e27085e9'
    $backendRevision = 'c23db688c7f6079413bf82dad4e4f19e5ddf4ce7'
    $frontend = Join-Path $runDirectory 'iloader'
    $backend = Join-Path $runDirectory 'isideload'
    New-PinnedCheckout $tools['git.exe'] $frontend 'https://github.com/nab138/iloader.git' $iloaderRevision (Join-Path $inputs 'iloader.patch')
    New-PinnedCheckout $tools['git.exe'] $backend 'https://github.com/nab138/isideload.git' $backendRevision (Join-Path $inputs 'isideload.patch')

    Set-Location (Join-Path $frontend 'src-tauri')
    $metadata = (Get-NativeOutput $tools['cargo.exe'] @('metadata', '--locked', '--format-version', '1')) | ConvertFrom-Json
    Assert-Dependencies $metadata (Join-Path $backend 'isideload/Cargo.toml')
    Invoke-Native $tools['cargo.exe'] @('test', '--locked', '--release', '--target', $TargetTriple, '-p', 'isideload', '--lib')
    Set-Location $frontend
    Invoke-Native $tools['bun.exe'] @('install', '--frozen-lockfile')
    $bundleStarted = [DateTime]::UtcNow
    Invoke-Native $tools['bun.exe'] @('run', 'tauri', 'build', '--target', $TargetTriple, '--bundles', 'nsis', '--config', 'src-tauri/ci.conf.json', '--', '--locked')

    $nsisDirectory = Join-Path $env:CARGO_TARGET_DIR "$TargetTriple/release/bundle/nsis"
    $installers = @(Get-ChildItem -LiteralPath $nsisDirectory -Filter '*.exe' -File | Where-Object { $_.LastWriteTimeUtc -ge $bundleStarted.AddSeconds(-2) })
    if ($installers.Count -ne 1) { throw "Expected one newly generated NSIS installer in '$nsisDirectory'; found $($installers.Count). Old cached installers will not be packaged." }
    $null = New-Item -ItemType Directory -Path $outputDirectory
    Copy-Item -LiteralPath $installers[0].FullName -Destination (Join-Path $outputDirectory 'iloader-2.3.6-watch-windows-x64.exe')
    foreach ($inputFile in (Get-ChildItem -LiteralPath $inputs -File)) { Copy-Item -LiteralPath $inputFile.FullName -Destination $outputDirectory }
    Copy-Item -LiteralPath (Join-Path $frontend 'LICENSE') -Destination (Join-Path $outputDirectory 'LICENSE-iloader.txt')
    Copy-Item -LiteralPath (Join-Path $frontend 'LICENSE-BRANDING') -Destination (Join-Path $outputDirectory 'LICENSE-BRANDING-iloader.txt')
    Copy-Item -LiteralPath (Join-Path $backend 'LICENSE') -Destination (Join-Path $outputDirectory 'LICENSE-isideload.txt')
    Copy-Item -LiteralPath (Join-Path $frontend 'src-tauri/Cargo.lock') -Destination (Join-Path $outputDirectory 'Cargo.lock')
    Copy-Item -LiteralPath (Join-Path $frontend 'bun.lock') -Destination (Join-Path $outputDirectory 'bun.lock')
    $repoRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../..'))
    $repoRevision = Get-NativeOutput $tools['git.exe'] @('-C', $repoRoot, 'rev-parse', 'HEAD')
    @(
        "Local Windows build: $runID"
        "Completed UTC: $([DateTime]::UtcNow.ToString('o'))"
        "Gyma checkout revision: $repoRevision (actual patch contents are included and hashed)"
        "iLoader: https://github.com/nab138/iloader/commit/$iloaderRevision"
        "isideload: https://github.com/nab138/isideload/commit/$backendRevision"
        'Watch reference: https://github.com/Rzbck/isideload/commit/f7b9f3da570edd6824c29680545e710846d07df5'
        "Rust: $(Get-NativeOutput $tools['rustc.exe'] @('--version'))"
        "Cargo: $(Get-NativeOutput $tools['cargo.exe'] @('--version'))"
        "Bun: $(Get-NativeOutput $tools['bun.exe'] @('--version'))"
        "MSVC: $($tools['cl.exe'])"
        "Target: $TargetTriple"
        "Sources: $runDirectory"
        "Cargo target cache: $env:CARGO_TARGET_DIR"
        'Validation: cargo test --locked --release --target x86_64-pc-windows-msvc -p isideload --lib'
        'Frontend dependencies: bun install --frozen-lockfile'
        'Installer: bun run tauri build --target x86_64-pc-windows-msvc --bundles nsis --config src-tauri/ci.conf.json -- --locked'
    ) | Set-Content -LiteralPath (Join-Path $outputDirectory 'BUILD.txt') -Encoding utf8
    Get-ChildItem -LiteralPath $outputDirectory -File | Sort-Object Name | ForEach-Object {
        "$((Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash.ToLowerInvariant())  $($_.Name)"
    } | Set-Content -LiteralPath (Join-Path $outputDirectory 'SHA256SUMS.txt') -Encoding utf8
    Write-Host "Installer and provenance: $outputDirectory"
    Write-Host "Sources retained: $runDirectory"
} catch {
    if ($runDirectory) { Write-Warning "Build failed. Sources are preserved for inspection at: $runDirectory" }
    throw
} finally {
    if ($null -ne $buildLock) { $buildLock.Dispose() }
    Set-Location $originalLocation
    foreach ($name in @([Environment]::GetEnvironmentVariables('Process').Keys)) {
        if (-not $savedEnvironment.Contains($name)) { [Environment]::SetEnvironmentVariable($name, $null, 'Process') }
    }
    foreach ($name in $savedEnvironment.Keys) { [Environment]::SetEnvironmentVariable($name, $savedEnvironment[$name], 'Process') }
}
