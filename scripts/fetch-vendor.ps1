# Fetch the vendored `libidevice_ffi.a` static library and verify its SHA-256.
#
# Windows / PowerShell version of scripts/fetch-vendor.sh. The library is
# ~54.4 MB and arm64/iOS-only, so it is not checked into git. It is taken
# verbatim from StikDebug at the pinned upstream commit (the StikDebug build
# contains the idevice revision with the iOS 26 Remote Pairing changes; the
# engine code itself is still ported from TLocation):
#
#   https://github.com/StikDebug/StikDebug/commit/7a80dfce28eeb501faca6498d1746949ac921e74
#
# Usage:
#   pwsh -File scripts/fetch-vendor.ps1
#   pwsh -File scripts/fetch-vendor.ps1 -Force
#
[CmdletBinding()]
param(
    [switch]$Force
)

$ErrorActionPreference = "Stop"

$RootDir = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
$Dest = Join-Path $RootDir "Vendor\idevice\libidevice_ffi.a"
$Url = "https://raw.githubusercontent.com/StikDebug/StikDebug/7a80dfce28eeb501faca6498d1746949ac921e74/StikDebug/idevice/libidevice_ffi.a"
$Sha256 = "4DB23FE1D342927B9480BB9A8577F219994365621DC28AA0018E23EA1990ECC8"

function Get-Sha256([string]$Path) {
    return (Get-FileHash -Algorithm SHA256 -Path $Path).Hash.ToUpperInvariant()
}

if ((Test-Path $Dest) -and (-not $Force)) {
    $current = Get-Sha256 $Dest
    if ($current -eq $Sha256) {
        Write-Host "libidevice_ffi.a already present and verified ($Sha256)."
        exit 0
    }
    Write-Warning "Existing libidevice_ffi.a has the wrong SHA-256; re-downloading."
}

$destDir = Split-Path -Parent $Dest
if (-not (Test-Path $destDir)) {
    New-Item -ItemType Directory -Force -Path $destDir | Out-Null
}

$tmp = "$Dest.tmp"
if (Test-Path $tmp) { Remove-Item -Force $tmp }

Write-Host "Downloading libidevice_ffi.a (about 54.4 MB)..."
Invoke-WebRequest -Uri $Url -OutFile $tmp -UseBasicParsing

$actual = Get-Sha256 $tmp
if ($actual -ne $Sha256) {
    Remove-Item -Force $tmp
    throw "SHA-256 mismatch for libidevice_ffi.a`n  expected: $Sha256`n  actual:   $actual"
}

Move-Item -Force $tmp $Dest
Write-Host "Verified and installed: $Dest"
