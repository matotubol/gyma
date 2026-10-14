#requires -Version 7.0
[CmdletBinding()]
param(
    [ValidateSet('baseline', 'cpd-booleans', 'authkit-user-agent', 'cpd-metadata', 'windows-native-anisette', 'windows-native-identity')]
    [string]$Experiment = 'baseline',
    [string]$Executable = (Join-Path $PSScriptRoot '../../build/iloader-watch-local/cache/cargo-target/x86_64-pc-windows-msvc/release/iloader.exe'),
    [string]$NativeHelper = (Join-Path $PSScriptRoot '../../build/iloader-auth-native/native-anisette-helper-x86.exe')
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$executablePath = [IO.Path]::GetFullPath($Executable)
if (-not (Test-Path -LiteralPath $executablePath -PathType Leaf)) {
    throw "Build the custom iLoader locally first. Executable missing: $executablePath"
}
$nativeHelperPath = $null
if ($Experiment -in @('windows-native-anisette', 'windows-native-identity')) {
    $nativeHelperPath = [IO.Path]::GetFullPath($NativeHelper)
    if (-not (Test-Path -LiteralPath $nativeHelperPath -PathType Leaf)) {
        throw 'Build the standalone native helper with build-native-anisette-helper.ps1 before this comparison.'
    }
}

$diagnosticRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../build/iloader-auth-diagnostics'))
$diagnosticPrefix = $diagnosticRoot.TrimEnd([IO.Path]::DirectorySeparatorChar) + [IO.Path]::DirectorySeparatorChar
$existing = @(Get-Process -Name iloader -ErrorAction SilentlyContinue)
foreach ($process in $existing) {
    $processPath = $process.Path
    if ([string]::IsNullOrEmpty($processPath) -or
        (-not $processPath.Equals($executablePath, [StringComparison]::OrdinalIgnoreCase) -and
         -not $processPath.StartsWith($diagnosticPrefix, [StringComparison]::OrdinalIgnoreCase))) {
        throw 'Another iLoader installation is running. Close it before starting the diagnostic copy.'
    }
}
foreach ($process in $existing) {
    if (-not $process.CloseMainWindow() -or -not $process.WaitForExit(5000)) {
        throw 'iLoader has not closed gracefully. Finish or dismiss its current operation before retrying.'
    }
}

$sessionName = [DateTime]::UtcNow.ToString('yyyyMMdd-HHmmss') + '-' + $Experiment + '-' + [Guid]::NewGuid().ToString('N').Substring(0, 8)
$sessionDirectory = Join-Path $diagnosticRoot $sessionName
$null = New-Item -ItemType Directory -Path $sessionDirectory -Force
$sessionExecutable = Join-Path $sessionDirectory 'iloader.exe'
$diagnosticPath = Join-Path $sessionDirectory 'auth.jsonl'
# Run a copy so the normal Cargo cache is available to subsequent local builds.
Copy-Item -LiteralPath $executablePath -Destination $sessionExecutable
$sessionHelper = $null
if ($nativeHelperPath) {
    $sessionHelper = Join-Path $sessionDirectory 'native-anisette-helper-x86.exe'
    Copy-Item -LiteralPath $nativeHelperPath -Destination $sessionHelper
}
@{
    experiment = $Experiment
    createdUtc = [DateTime]::UtcNow.ToString('o')
    sourceExecutable = $executablePath
    sha256 = (Get-FileHash -LiteralPath $sessionExecutable -Algorithm SHA256).Hash.ToLowerInvariant()
    nativeHelperSha256 = $(if ($sessionHelper) { (Get-FileHash -LiteralPath $sessionHelper -Algorithm SHA256).Hash.ToLowerInvariant() } else { $null })
} | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $sessionDirectory 'session.json') -Encoding utf8

$previousDiagnosticPath = [Environment]::GetEnvironmentVariable('GYMA_AUTH_DIAGNOSTICS_PATH', 'Process')
$previousExperiment = [Environment]::GetEnvironmentVariable('GYMA_AUTH_EXPERIMENT', 'Process')
$previousNativeHelper = [Environment]::GetEnvironmentVariable('GYMA_NATIVE_ANISETTE_HELPER', 'Process')
try {
    [Environment]::SetEnvironmentVariable('GYMA_AUTH_DIAGNOSTICS_PATH', $diagnosticPath, 'Process')
    [Environment]::SetEnvironmentVariable('GYMA_AUTH_EXPERIMENT', $Experiment, 'Process')
    [Environment]::SetEnvironmentVariable('GYMA_NATIVE_ANISETTE_HELPER', $sessionHelper, 'Process')
    $launched = Start-Process -FilePath $sessionExecutable -WorkingDirectory $sessionDirectory -PassThru
    $null = $launched.WaitForInputIdle(5000)
    $launched.Refresh()
    [pscustomobject]@{
        ProcessId = $launched.Id
        Experiment = $Experiment
        Diagnostics = $diagnosticPath
        Executable = $sessionExecutable
    }
} finally {
    [Environment]::SetEnvironmentVariable('GYMA_AUTH_DIAGNOSTICS_PATH', $previousDiagnosticPath, 'Process')
    [Environment]::SetEnvironmentVariable('GYMA_AUTH_EXPERIMENT', $previousExperiment, 'Process')
    [Environment]::SetEnvironmentVariable('GYMA_NATIVE_ANISETTE_HELPER', $previousNativeHelper, 'Process')
}
