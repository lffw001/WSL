<#
.SYNOPSIS
    Sets up the development environment for building WSL.
.DESCRIPTION
    Installs all prerequisites: enables Developer Mode, installs CMake
    via WinGet Configuration, and ensures Visual Studio 2022 has the
    required workloads/components from .vsconfig.

    If VS 2022 is already installed (any edition), the script adds
    missing components to the existing installation. If no VS 2022 is
    found, it installs Community edition.
.EXAMPLE
    .\tools\setup-dev-env.ps1
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$repoRoot = (Resolve-Path "$PSScriptRoot\..").Path
$vsConfigPath = Join-Path $repoRoot ".vsconfig"
$wingetConfigPath = Join-Path $repoRoot ".config\configuration.winget"

# ── Developer Mode + CMake via WinGet Configuration ─────────────────
Write-Host ""
Write-Host "Installing prerequisites via WinGet Configuration..." -ForegroundColor Cyan
Write-Host ""

winget configure -f $wingetConfigPath --accept-configuration-agreements
if ($LASTEXITCODE -ne 0)
{
    Write-Host "WinGet configuration failed." -ForegroundColor Red
    exit 1
}

# ── Visual Studio 2022 ──────────────────────────────────────────────
Write-Host ""
Write-Host "Checking Visual Studio 2022..." -ForegroundColor Cyan
Write-Host ""

$vswhere = "${env:ProgramFiles(x86)}\Microsoft Visual Studio\Installer\vswhere.exe"

$vsInstallPath = $null
$vsProductId = $null
if (Test-Path $vswhere)
{
    $vsInstallPath = (& $vswhere -version "[17.0,18.0)" -products * -latest -property installationPath 2>$null |
        Select-Object -First 1)
    $vsProductId = (& $vswhere -version "[17.0,18.0)" -products * -latest -property productId 2>$null |
        Select-Object -First 1)

    if ($vsInstallPath) { $vsInstallPath = $vsInstallPath.Trim() }
    if ($vsProductId) { $vsProductId = $vsProductId.Trim() }
}

if ($vsInstallPath)
{
    Write-Host "  Found $vsProductId at $vsInstallPath" -ForegroundColor Green
    Write-Host "  Installing required components from .vsconfig..." -ForegroundColor White

    # setup.exe modify doesn't support --config; parse .vsconfig and pass --add for each component.
    $vsConfig = Get-Content $vsConfigPath -Raw | ConvertFrom-Json
    $addArgs = @("modify", "--installPath", $vsInstallPath, "--quiet", "--wait")
    foreach ($component in $vsConfig.components)
    {
        $addArgs += "--add"
        $addArgs += $component
    }

    $setup = "${env:ProgramFiles(x86)}\Microsoft Visual Studio\Installer\setup.exe"
    & $setup @addArgs
    if ($LASTEXITCODE -ne 0)
    {
        Write-Host "  VS component installation failed (exit code $LASTEXITCODE)." -ForegroundColor Red
        exit 1
    }

    Write-Host "  VS components installed." -ForegroundColor Green
}
else
{
    Write-Host "  No VS 2022 installation found. Installing Community edition..." -ForegroundColor Yellow
    winget install Microsoft.VisualStudio.2022.Community --accept-package-agreements --accept-source-agreements --override "--wait --quiet --config `"$vsConfigPath`""
    if ($LASTEXITCODE -ne 0)
    {
        Write-Host "  VS installation failed." -ForegroundColor Red
        exit 1
    }

    Write-Host "  VS 2022 Community installed with required components." -ForegroundColor Green
}

# ── Done ────────────────────────────────────────────────────────────
Write-Host ""
Write-Host "All prerequisites installed. Ready to build!" -ForegroundColor Green
Write-Host ""
Write-Host "  cmake ."
Write-Host "  cmake --build . -- -m"
Write-Host ""
