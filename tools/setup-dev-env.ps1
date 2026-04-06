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
    $cmakeVersion = [version]((cmake --version | Select-Object -First 1) -replace '[^0-9.]', '')
    $cmakeOk = $cmakeVersion -ge [version]"3.25"
}
Check "CMake >= 3.25$(if ($cmakeVersion) { " (found $cmakeVersion)" })" $cmakeOk "winget install Kitware.CMake"

# --- Visual Studio ---
$vswhere = "${env:ProgramFiles(x86)}\Microsoft Visual Studio\Installer\vswhere.exe"
$vsInstall = $null
if (Test-Path $vswhere)
{
    $vsInstall = & $vswhere -latest -property installationPath 2>$null
}
Check "Visual Studio 2022+" ($null -ne $vsInstall) "Install Visual Studio 2022: https://visualstudio.microsoft.com/"

# --- VS Components (only check if VS is found) ---
if ($vsInstall)
{
    Write-Host ""
    Write-Host "Visual Studio Components:" -ForegroundColor White

    $installedComponents = @(& $vswhere -latest -property catalog_productLineVersion 2>$null)
    $vsComponents = & $vswhere -latest -format json 2>$null | ConvertFrom-Json

    # Check for specific required components via their markers
    $clangPath = Join-Path $vsInstall "VC\Tools\Llvm\x64\bin\clang-format.exe"
    Check "C++ Clang Compiler for Windows" (Test-Path $clangPath) "VS Installer -> Modify -> Individual Components -> C++ Clang Compiler for Windows"

    $atlPath = Get-ChildItem -Path (Join-Path $vsInstall "VC\Tools\MSVC") -Filter "atlbase.h" -Recurse -ErrorAction SilentlyContinue | Select-Object -First 1
    Check "C++ ATL for latest v143 tools" ($null -ne $atlPath) "VS Installer -> Modify -> Individual Components -> C++ ATL for latest v143 build tools"

    $msbuild = Get-Command "msbuild" -ErrorAction SilentlyContinue
    if (-not $msbuild)
    {
        $msbuild = Get-ChildItem -Path $vsInstall -Filter "MSBuild.exe" -Recurse -ErrorAction SilentlyContinue | Select-Object -First 1
    }
    Check "MSBuild" ($null -ne $msbuild) "VS Installer -> Modify -> Individual Components -> MSBuild"
}

# --- Windows SDK ---
Write-Host ""
Write-Host "Windows SDK:" -ForegroundColor White
$sdkPath = "${env:ProgramFiles(x86)}\Windows Kits\10\Include\10.0.26100.0"
Check "Windows SDK 26100" (Test-Path $sdkPath) "VS Installer -> Modify -> Individual Components -> Windows 11 SDK (10.0.26100.0)"

# --- NuGet Credential Provider (Azure DevOps feed) ---
Write-Host ""
Write-Host "NuGet:" -ForegroundColor White
$credProviderFound = $false
if ($env:NUGET_PLUGIN_PATHS)
{
    # If NUGET_PLUGIN_PATHS is set, NuGet will look there instead of the default location.
    $credProviderFound = Test-Path $env:NUGET_PLUGIN_PATHS
}
else
{
    $credProviderFound = (Test-Path "${env:USERPROFILE}\.nuget\plugins\netfx\CredentialProvider.Microsoft\CredentialProvider.Microsoft.exe") -or
        (Test-Path "${env:USERPROFILE}\.nuget\plugins\netcore\CredentialProvider.Microsoft\CredentialProvider.Microsoft.dll")
}
Check "Azure Artifacts Credential Provider" $credProviderFound "iex ""& { `$(irm https://aka.ms/install-artifacts-credprovider.ps1) } -AddNetfx"""

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
