<#
.SYNOPSIS
    Builds the MemDroid Windows release bundle and compiles the Inno Setup 6 installer.

.DESCRIPTION
    Convenience wrapper for local, off-CI reproduction of the installer that the
    release workflow produces. It:

      1. Resolves the version (from -Version, else from pubspec.yaml).
      2. Runs `flutter build windows --release` (skip with -SkipFlutterBuild).
      3. Locates ISCC.exe (Inno Setup 6.3+).
      4. Compiles installers\windows\memdroid.iss with the right /D defines.

    The installer lands in build\windows\installer\.

.EXAMPLE
    .\installers\windows\build_installer.ps1

.EXAMPLE
    .\installers\windows\build_installer.ps1 -Version 1.0.4 -SkipFlutterBuild
#>
[CmdletBinding()]
param(
    # Version stamped into the installer. Defaults to pubspec.yaml's version
    # with any +build suffix stripped. A leading "v" is accepted.
    [string] $Version,

    # Publisher string shown in Add/Remove Programs.
    [string] $Publisher = 'com.memai',

    # Reuse an existing build\windows\x64\runner\Release bundle.
    [switch] $SkipFlutterBuild,

    # Explicit path to ISCC.exe if it is not on PATH or in the usual places.
    [string] $Iscc
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$repoRoot  = (Resolve-Path (Join-Path $scriptDir '..\..')).Path
$issPath   = Join-Path $scriptDir 'memdroid.iss'
$buildDir  = Join-Path $repoRoot 'build\windows\x64\runner\Release'
$outputDir = Join-Path $repoRoot 'build\windows\installer'

if (-not (Test-Path $issPath)) {
    throw "Inno Setup script not found: $issPath"
}

# --- 1. Version -------------------------------------------------------------
if (-not $Version) {
    $pubspec = Join-Path $repoRoot 'pubspec.yaml'
    $line = Select-String -Path $pubspec -Pattern '^version:\s*(.+)$' | Select-Object -First 1
    if (-not $line) { throw "Could not read 'version:' from $pubspec" }
    $Version = $line.Matches[0].Groups[1].Value.Trim()
}
$Version = $Version.TrimStart('v', 'V')
# Drop any +build suffix; the .iss handles this too, but keep the log honest.
$Version = ($Version -split '\+')[0]
Write-Host "Version: $Version"

# --- 2. Flutter build -------------------------------------------------------
if ($SkipFlutterBuild) {
    Write-Host 'Skipping flutter build (-SkipFlutterBuild).'
} else {
    Write-Host 'Running: flutter build windows --release'
    Push-Location $repoRoot
    try {
        & flutter build windows --release
        if ($LASTEXITCODE -ne 0) { throw "flutter build windows --release failed (exit $LASTEXITCODE)" }
    } finally {
        Pop-Location
    }
}

# --- 3. Sanity-check the bundle --------------------------------------------
# The .iss re-checks all of this at compile time; failing here first just gives
# a friendlier message. MemDroid.exe is the name set by BINARY_NAME in
# windows/CMakeLists.txt.
foreach ($required in @(
    (Join-Path $buildDir 'MemDroid.exe'),
    (Join-Path $buildDir 'flutter_windows.dll'),
    (Join-Path $buildDir 'data\icudtl.dat'),
    (Join-Path $buildDir 'data\app.so'),
    (Join-Path $buildDir 'data\flutter_assets')
)) {
    if (-not (Test-Path $required)) {
        throw "Missing from the release bundle: $required`nRun without -SkipFlutterBuild."
    }
}

# --- 4. Locate ISCC ---------------------------------------------------------
if (-not $Iscc) {
    $roots = @(${env:ProgramFiles(x86)}, $env:ProgramFiles) | Where-Object { $_ }
    $candidates = @(
        (Get-Command 'iscc.exe' -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Source -ErrorAction SilentlyContinue)
    ) + ($roots | ForEach-Object { Join-Path $_ 'Inno Setup 6\ISCC.exe' })
    $candidates = $candidates | Where-Object { $_ -and (Test-Path $_) }
    $Iscc = $candidates | Select-Object -First 1
}
if (-not $Iscc) {
    throw @'
ISCC.exe (Inno Setup 6.3+) was not found.
Install it, e.g.:
  winget install --id JRSoftware.InnoSetup --exact
then re-run, or pass -Iscc "C:\path\to\ISCC.exe".
'@
}
Write-Host "ISCC: $Iscc"

# --- 5. Compile -------------------------------------------------------------
New-Item -ItemType Directory -Force -Path $outputDir | Out-Null

$isccArgs = @(
    "/DAppVersion=$Version",
    "/DAppPublisher=$Publisher",
    "/DBuildDir=$buildDir",
    "/DOutputDir=$outputDir",
    $issPath
)
Write-Host "Running: $Iscc $($isccArgs -join ' ')"
& $Iscc @isccArgs
if ($LASTEXITCODE -ne 0) { throw "ISCC failed (exit $LASTEXITCODE)" }

$installer = Get-ChildItem -Path $outputDir -Filter '*.exe' |
    Sort-Object LastWriteTime -Descending | Select-Object -First 1
Write-Host ''
Write-Host "Installer: $($installer.FullName)"
Write-Host ("Size: {0:N1} MB" -f ($installer.Length / 1MB))
