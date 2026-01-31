# Syncarr Windows Service Uninstaller
# This script removes the Syncarr Windows service
# Run this script as Administrator

param(
    [string]$ServiceName = "Syncarr",
    [string]$NssmPath = "$env:ProgramData\nssm"
)

$ErrorActionPreference = "Stop"

# Colors for output
function Write-Success { param($msg) Write-Host $msg -ForegroundColor Green }
function Write-Info { param($msg) Write-Host $msg -ForegroundColor Cyan }
function Write-Warn { param($msg) Write-Host $msg -ForegroundColor Yellow }
function Write-Err { param($msg) Write-Host $msg -ForegroundColor Red }

Write-Host ""
Write-Host "========================================" -ForegroundColor Magenta
Write-Host "  Syncarr Windows Service Uninstaller  " -ForegroundColor Magenta
Write-Host "========================================" -ForegroundColor Magenta
Write-Host ""

# Check for Administrator privileges
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    Write-Err "ERROR: This script must be run as Administrator!"
    Write-Info "Right-click PowerShell and select 'Run as Administrator', then try again."
    pause
    exit 1
}

# Check if service exists
$service = Get-Service -Name $ServiceName -ErrorAction SilentlyContinue
if (-not $service) {
    Write-Warn "Service '$ServiceName' is not installed."
    pause
    exit 0
}

Write-Info "Found service '$ServiceName' with status: $($service.Status)"

# Confirm removal
$confirm = Read-Host "Are you sure you want to remove the Syncarr service? (Y/N)"
if ($confirm -ne 'Y' -and $confirm -ne 'y') {
    Write-Info "Cancelled."
    pause
    exit 0
}

# Stop the service if running
if ($service.Status -eq 'Running') {
    Write-Info "Stopping service..."
    Stop-Service -Name $ServiceName -Force
    Start-Sleep -Seconds 3
    Write-Success "Service stopped."
}

# Remove the service
Write-Info "Removing service..."

# Find NSSM - check bundled first, then system
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$bundledNssm = Join-Path $ScriptDir "tools\nssm.exe"
$systemNssm = Join-Path $NssmPath "nssm.exe"

if (Test-Path $bundledNssm) {
    $nssmExe = $bundledNssm
}
elseif (Test-Path $systemNssm) {
    $nssmExe = $systemNssm
}
else {
    $nssmExe = $null
}

if ($nssmExe) {
    & $nssmExe remove $ServiceName confirm
}
else {
    # Fallback to sc.exe if nssm not found
    sc.exe delete $ServiceName
}

Start-Sleep -Seconds 2

# Verify removal
$checkService = Get-Service -Name $ServiceName -ErrorAction SilentlyContinue
if ($checkService) {
    Write-Warn "Service may still exist. You may need to restart your computer."
}
else {
    Write-Success "Service '$ServiceName' has been removed successfully!"
}

Write-Host ""
Write-Info "Note: NSSM and log files have not been removed."
Write-Info "To remove NSSM: Delete folder $NssmPath"
Write-Host ""
pause
