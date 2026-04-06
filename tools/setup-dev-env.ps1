<#
.SYNOPSIS
    Checks that all prerequisites for building WSL are installed.
.DESCRIPTION
    Validates the development environment and reports missing tools
    with installation instructions. Run this before your first build.
.EXAMPLE
    .\tools\setup-dev-env.ps1
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$script:Errors = 0
$script:RepoRoot = (Resolve-Path "$PSScriptRoot\..").Path
$script:VsConfigPath = Join-Path $script:RepoRoot ".vsconfig"
$script:VsInstallFix = "Import .vsconfig via VS Installer -> More -> Import configuration, or: winget install Microsoft.VisualStudio.2022.Community --override ""--wait --quiet --config '$script:VsConfigPath'"""

function Check($Name, $Result, $Fix, [switch]$Optional)
{
    if ($Result)
    {
        Write-Host "  [OK] $Name" -ForegroundColor Green
    }
    elseif ($Optional)
    {
        Write-Host "  [OPTIONAL] $Name" -ForegroundColor DarkYellow
        Write-Host "    -> $Fix" -ForegroundColor Yellow
    }
    else
    {
        Write-Host "  [MISSING] $Name" -ForegroundColor Red
        Write-Host "    -> $Fix" -ForegroundColor Yellow
        $script:Errors++
    }
}

Write-Host ""
Write-Host "WSL Development Environment Check" -ForegroundColor Cyan
Write-Host "==================================" -ForegroundColor Cyan
Write-Host ""

# --- CMake ---
Write-Host "Build Tools:" -ForegroundColor White
$cmake = Get-Command "cmake" -ErrorAction SilentlyContinue
$cmakeVersion = $null
$cmakeOk = $false
if ($cmake)
{
    try
    {
        $cmakeVersion = [version]((cmake --version | Select-Object -First 1) -replace '[^0-9.]', '')
        $cmakeOk = $cmakeVersion -ge [version]"3.25"
    }
    catch
    {
        $cmakeVersion = $null
        $cmakeOk = $false
    }
}
Check "CMake >= 3.25$(if ($cmakeVersion) { " (found $cmakeVersion)" })" $cmakeOk "winget install Kitware.CMake"

# --- Visual Studio ---
# Mirror CMakeLists.txt: prefer VS2022 [17.0,18.0) to keep clang-format
# aligned with pipeline expectations. Fall back to VS2026 [18.0,19.0) with a warning.
$vswhere = "${env:ProgramFiles(x86)}\Microsoft Visual Studio\Installer\vswhere.exe"
$vsInstall = $null
$vsVersion = $null
$vsOk = $false
$vsWarning = $null
if (Test-Path $vswhere)
{
    # Try VS2022 first
    $vsInstall = (& $vswhere -version "[17.0,18.0)" -products * -latest -property installationPath -prerelease 2>$null | Select-Object -First 1)
    $vsVersionText = (& $vswhere -version "[17.0,18.0)" -products * -latest -property installationVersion -prerelease 2>$null | Select-Object -First 1)

    if (-not $vsInstall)
    {
        # Fall back to VS2026
        $vsInstall = (& $vswhere -version "[18.0,19.0)" -products * -latest -property installationPath -prerelease 2>$null | Select-Object -First 1)
        $vsVersionText = (& $vswhere -version "[18.0,19.0)" -products * -latest -property installationVersion -prerelease 2>$null | Select-Object -First 1)
        if ($vsInstall) { $vsWarning = "VS 2022 not found; using VS 2026. clang-format output may differ from pipeline expectations." }
    }

    if ($vsInstall) { $vsInstall = $vsInstall.Trim() }
    if ($vsVersionText)
    {
        try
        {
            $vsVersion = [version]$vsVersionText.Trim()
            $vsOk = -not [string]::IsNullOrWhiteSpace($vsInstall)
        }
        catch {}
    }
}
Check "Visual Studio 2022+$(if ($vsVersion) { " (found $vsVersion)" })" $vsOk $script:VsInstallFix
if ($vsWarning)
{
    Write-Host "    WARNING: $vsWarning" -ForegroundColor DarkYellow
}

# --- VS Components (only check if VS 2022+ is found) ---
if ($vsOk)
{
    Write-Host ""
    Write-Host "Visual Studio Components:" -ForegroundColor White

    # Check for specific required components via their markers
    $clangPath = Join-Path $vsInstall "VC\Tools\Llvm\*\bin\clang-format.exe"
    Check "C++ Clang Compiler for Windows" (Test-Path $clangPath) $script:VsInstallFix

    $atlPath = Join-Path $vsInstall "VC\Tools\MSVC\*\atlmfc\include\atlbase.h"
    Check "C++ ATL for latest v143 tools" (Test-Path $atlPath) $script:VsInstallFix

    $msbuild = Get-Command "msbuild" -ErrorAction SilentlyContinue
    if (-not $msbuild)
    {
        $msbuildPath = Join-Path $vsInstall "MSBuild\Current\Bin\MSBuild.exe"
        $msbuildAmd64 = Join-Path $vsInstall "MSBuild\Current\Bin\amd64\MSBuild.exe"
        $msbuild = (Test-Path $msbuildPath) -or (Test-Path $msbuildAmd64)
    }
    Check "MSBuild" ($null -ne $msbuild -and $msbuild) $script:VsInstallFix
}

# --- Windows SDK ---
Write-Host ""
Write-Host "Windows SDK:" -ForegroundColor White
$sdkPath = "${env:ProgramFiles(x86)}\Windows Kits\10\Include\10.0.26100.0"
Check "Windows SDK 26100" (Test-Path $sdkPath) $script:VsInstallFix

# --- NuGet Credential Provider (Azure DevOps feed) ---
# nuget.exe resolves credential provider plugins using a priority chain:
#   1. NUGET_NETFX_PLUGIN_PATHS  (highest priority for standalone nuget.exe)
#   2. NUGET_PLUGIN_PATHS         (general override)
#   3. %USERPROFILE%\.nuget\plugins\netfx\...  (default)
# If a higher-priority env var is set but points to a missing file, nuget.exe
# fails even when the provider is installed at the default location.
Write-Host ""
Write-Host "NuGet:" -ForegroundColor White

$defaultNetfx = "${env:USERPROFILE}\.nuget\plugins\netfx\CredentialProvider.Microsoft\CredentialProvider.Microsoft.exe"

# Walk the priority chain to find the path nuget.exe will actually use.
$effectivePath = $null
$effectiveSource = $null
foreach ($entry in @(
    @{ Var = "NUGET_NETFX_PLUGIN_PATHS"; Val = $env:NUGET_NETFX_PLUGIN_PATHS },
    @{ Var = "NUGET_PLUGIN_PATHS";       Val = $env:NUGET_PLUGIN_PATHS }
))
{
    if ($entry.Val)
    {
        $effectivePath = $entry.Val
        $effectiveSource = $entry.Var
        break
    }
}
if (-not $effectivePath)
{
    $effectivePath = $defaultNetfx
    $effectiveSource = "default"
}

$providerFound = Test-Path $effectivePath
$label = "Azure Artifacts Credential Provider"
if ($effectiveSource -ne "default")
{
    $label += " (via $effectiveSource)"
}

if ($providerFound)
{
    Check $label $true ""
}
elseif ($effectiveSource -ne "default" -and (Test-Path $defaultNetfx))
{
    # Provider is installed at the default location but an env var redirects
    # nuget.exe to a different path where it doesn't exist.
    $targetDir = Split-Path $effectivePath -Parent
    $sourceDir = Split-Path $defaultNetfx -Parent
    Check $label $false "New-Item -ItemType Directory -Force -Path '$targetDir' | Out-Null; Copy-Item '$sourceDir\*' '$targetDir' -Recurse -Force"
}
else
{
    Check $label $false "See https://github.com/microsoft/artifacts-credprovider#installation"
}

# --- Developer Mode / Symlinks ---
Write-Host ""
Write-Host "System Configuration:" -ForegroundColor White

$devMode = $false
try
{
    $devModeReg = Get-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\AppModelUnlock" -Name "AllowDevelopmentWithoutDevLicense" -ErrorAction SilentlyContinue
    $devMode = $devModeReg -and $devModeReg.AllowDevelopmentWithoutDevLicense -eq 1
}
catch {}

$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
Check "Developer Mode or Admin$(if ($devMode) { ' (Developer Mode)' } elseif ($isAdmin) { ' (Administrator)' })" ($devMode -or $isAdmin) "Settings -> System -> For developers -> Developer Mode"

# --- Optional tools ---
Write-Host ""
Write-Host "Optional Tools:" -ForegroundColor White

$windbg = Get-Command "WinDbgX.exe" -ErrorAction SilentlyContinue
Check "WinDbg (for /attachdebugger)" ($null -ne $windbg) "winget install Microsoft.WinDbg" -Optional

$python = Get-Command "python3" -ErrorAction SilentlyContinue
if (-not $python) { $python = Get-Command "python" -ErrorAction SilentlyContinue }
Check "Python 3 (for validation scripts)" ($null -ne $python) "winget install Python.Python.3.13" -Optional

# --- Summary ---
Write-Host ""
if ($script:Errors -eq 0)
{
    Write-Host "All prerequisites found. Ready to build!" -ForegroundColor Green
    Write-Host ""
    Write-Host "  cmake ."
    Write-Host "  cmake --build . -- -m"
    Write-Host ""
}
else
{
    Write-Host "$($script:Errors) prerequisite(s) missing. Install them and re-run this script." -ForegroundColor Red
    Write-Host ""
    exit 1
}
