#requires -Version 7.0
<#
Compile the standalone x86 native anisette helper. This script never launches the
helper, loads Apple DLLs, installs tools, or changes Apple provisioning state.
The resulting executable is for a parent application's private anonymous pipe;
its output must not be displayed, logged, or redirected to a plaintext file.
#>
[CmdletBinding()]
param(
    [string]$OutputDirectory = (Join-Path $PSScriptRoot '../../.local/iloader/native')
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $false
if (-not $IsWindows) { throw 'Run this build script with PowerShell 7 on Windows.' }

function Get-NativeOutput([string]$File, [string[]]$Arguments) {
    $output = & $File @Arguments
    if ($LASTEXITCODE -ne 0) { throw "Build prerequisite command failed (exit $LASTEXITCODE)." }
    return ($output -join "`n")
}

$vswhere = Get-Command 'vswhere.exe' -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1 -ExpandProperty Source
if (-not $vswhere) {
    $vswhere = Join-Path ${env:ProgramFiles(x86)} 'Microsoft Visual Studio/Installer/vswhere.exe'
}
if (-not (Test-Path -LiteralPath $vswhere -PathType Leaf)) {
    throw 'An existing Visual Studio installation with the MSVC x86 tools is required.'
}
$installation = Get-NativeOutput $vswhere @('-latest', '-products', '*', '-requires', 'Microsoft.VisualStudio.Component.VC.Tools.x86.x64', '-property', 'installationPath')
if ([string]::IsNullOrWhiteSpace($installation)) { throw 'No installed MSVC x86 toolset was found.' }
$developerCommand = Join-Path $installation.Trim() 'Common7/Tools/VsDevCmd.bat'
if (-not (Test-Path -LiteralPath $developerCommand -PathType Leaf)) { throw 'Visual Studio developer environment script was not found.' }
if ($developerCommand -match '["\r\n]') { throw 'Invalid Visual Studio installation path.' }
$commandLine = '"{0}" -no_logo -arch=x86 -host_arch=x64 >nul && set' -f $developerCommand
$environmentText = Get-NativeOutput $env:ComSpec @('/d', '/s', '/c', $commandLine)
foreach ($line in ($environmentText -split "`n")) {
    if ($line -match '^([^=]+)=(.*)$') {
        [Environment]::SetEnvironmentVariable($Matches[1], $Matches[2].TrimEnd("`r"), 'Process')
    }
}
if ($env:VSCMD_ARG_TGT_ARCH -ne 'x86') { throw 'MSVC did not configure the x86 target.' }
$compiler = Get-Command 'cl.exe' -CommandType Application -ErrorAction Stop | Select-Object -First 1 -ExpandProperty Source
$source = Join-Path $PSScriptRoot 'native-anisette-helper.cpp'
$outputPath = [IO.Path]::GetFullPath($OutputDirectory)
New-Item -ItemType Directory -Path $outputPath -Force | Out-Null
$executable = Join-Path $outputPath 'native-anisette-helper-x86.exe'
$objectFile = Join-Path $outputPath 'native-anisette-helper-x86.obj'
$arguments = @(
    '/nologo', '/std:c++17', '/EHsc', '/W4', '/O2', '/MT', '/utf-8',
    '/D_WIN32_WINNT=0x0602', "/Fo$objectFile", "/Fe$executable", $source,
    '/link', '/MACHINE:X86', '/SUBSYSTEM:CONSOLE', '/DYNAMICBASE', '/NXCOMPAT',
    'shell32.lib', 'ole32.lib', 'bcrypt.lib'
)
& $compiler @arguments
if ($LASTEXITCODE -ne 0) { throw "Native helper compilation failed (exit $LASTEXITCODE)." }

# Inspect the generated PE header without running it.
$bytes = [IO.File]::ReadAllBytes($executable)
$peOffset = [BitConverter]::ToInt32($bytes, 0x3C)
if ([BitConverter]::ToUInt16($bytes, $peOffset + 4) -ne 0x014C) {
    throw 'The generated helper is not an x86 executable.'
}
[PSCustomObject]@{
    Executable = $executable
    Architecture = 'x86'
    SHA256 = (Get-FileHash -LiteralPath $executable -Algorithm SHA256).Hash
    Executed = $false
}
