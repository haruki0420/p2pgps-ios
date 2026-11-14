# Fetch the vendored `libidevice_ffi.a` static library and verify its SHA-256.
#
# Windows / PowerShell version of scripts/fetch-vendor.sh. The library is
# ~92.6 MB and arm64/iOS-only, so it is not checked into git. It is taken
# verbatim from TLocation at the pinned upstream commit:
#
#   https://github.com/truongkma/t-location/commit/5e57f815e5958f133dfbaae8252473054adeccf0
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
$Url = "https://raw.githubusercontent.com/truongkma/t-location/5e57f815e5958f133dfbaae8252473054adeccf0/TLocation/idevice/libidevice_ffi.a"
$Sha256 = "6524066D54EF23E00D46445C04DFC694E180196D54119D718F68434FA225BE35"

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

Write-Host "Downloading libidevice_ffi.a (about 92.6 MB)..."
Invoke-WebRequest -Uri $Url -OutFile $tmp -UseBasicParsing

$actual = Get-Sha256 $tmp
if ($actual -ne $Sha256) {
    Remove-Item -Force $tmp
    throw "SHA-256 mismatch for libidevice_ffi.a`n  expected: $Sha256`n  actual:   $actual"
}

Move-Item -Force $tmp $Dest
Write-Host "Verified and installed: $Dest"
