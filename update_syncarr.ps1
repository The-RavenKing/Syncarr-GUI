# Syncarr Update Script
# This script updates an existing Syncarr installation from the source (git repo or network share)
# Run this script as Administrator

param(
    [string]$ServiceName = "Syncarr",
    [switch]$FromGit,
    [switch]$Force
)

$ErrorActionPreference = "Stop"

# Colors for output
function Write-Success { param($msg) Write-Host $msg -ForegroundColor Green }
function Write-Info { param($msg) Write-Host $msg -ForegroundColor Cyan }
function Write-Warn { param($msg) Write-Host $msg -ForegroundColor Yellow }
function Write-Err { param($msg) Write-Host $msg -ForegroundColor Red }

Write-Host ""
Write-Host "========================================" -ForegroundColor Magenta
Write-Host "        Syncarr Update Script          " -ForegroundColor Magenta
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

# Paths
$SourcePath = Split-Path -Parent $MyInvocation.MyCommand.Path
$LocalInstallPath = "C:\ProgramData\Syncarr"

# Check if local installation exists
if (-not (Test-Path $LocalInstallPath)) {
    Write-Err "ERROR: Syncarr is not installed at $LocalInstallPath"
    Write-Info "Please run install_service.ps1 first."
    pause
    exit 1
}

# Check if service exists
$service = Get-Service -Name $ServiceName -ErrorAction SilentlyContinue
if (-not $service) {
    Write-Err "ERROR: Service '$ServiceName' not found."
    Write-Info "Please run install_service.ps1 first."
    pause
    exit 1
}

Write-Info "Source Path: $SourcePath"
Write-Info "Install Path: $LocalInstallPath"
Write-Info "Service Status: $($service.Status)"
Write-Host ""

# Option to pull from git first (if running from git repo)
if ($FromGit) {
    $gitDir = Join-Path $SourcePath ".git"
    if (Test-Path $gitDir) {
        Write-Info "Pulling latest changes from git..."
        try {
            Push-Location $SourcePath
            $gitOutput = git pull 2>&1
            Write-Host $gitOutput
            Pop-Location
            Write-Success "Git pull completed!"
        }
        catch {
            Write-Warn "Git pull failed: $_"
            Pop-Location
        }
    }
    else {
        Write-Warn "Not a git repository, skipping git pull."
    }
}

# Confirm update
if (-not $Force) {
    Write-Warn "This will update Syncarr and restart the service."
    Write-Info "Your configuration (gui_config.json, jobs.json) will be preserved."
    Write-Host ""
    $confirm = Read-Host "Continue? (Y/N)"
    if ($confirm -ne 'Y' -and $confirm -ne 'y') {
        Write-Info "Update cancelled."
        pause
        exit 0
    }
}

# Stop the service
Write-Info "Stopping Syncarr service..."
try {
    if ($service.Status -eq 'Running') {
        Stop-Service -Name $ServiceName -Force
        Start-Sleep -Seconds 2
        Write-Success "Service stopped."
    }
    else {
        Write-Info "Service was not running."
    }
}
catch {
    Write-Warn "Could not stop service: $_"
}

# Backup config files
Write-Info "Backing up configuration..."
$configBackup = $null
$jobsBackup = $null

if (Test-Path "$LocalInstallPath\gui_config.json") {
    $configBackup = Get-Content "$LocalInstallPath\gui_config.json" -Raw
    Write-Info "  - gui_config.json backed up"
}
if (Test-Path "$LocalInstallPath\jobs.json") {
    $jobsBackup = Get-Content "$LocalInstallPath\jobs.json" -Raw
    Write-Info "  - jobs.json backed up"
}

# Copy updated files
Write-Info "Copying updated files..."

# List of directories/files to update (excluding config files)
$itemsToUpdate = @(
    "syncarr_source",
    "static",
    "routers",
    "tools",
    "scheduler.py",
    "web_app.py",
    "requirements_gui.txt"
)

try {
    foreach ($item in $itemsToUpdate) {
        $sourcePath = Join-Path $SourcePath $item
        $destPath = Join-Path $LocalInstallPath $item
        
        if (Test-Path $sourcePath) {
            if ((Get-Item $sourcePath).PSIsContainer) {
                # It's a directory - remove old and copy new
                if (Test-Path $destPath) {
                    Remove-Item $destPath -Recurse -Force
                }
                Copy-Item $sourcePath $destPath -Recurse -Force
                Write-Info "  - Updated: $item/"
            }
            else {
                # It's a file
                Copy-Item $sourcePath $destPath -Force
                Write-Info "  - Updated: $item"
            }
        }
    }
    Write-Success "Files updated successfully!"
}
catch {
    Write-Err "ERROR: Failed to copy files: $_"
    pause
    exit 1
}

# Restore config files
Write-Info "Restoring configuration..."
if ($configBackup) {
    $configBackup | Set-Content "$LocalInstallPath\gui_config.json" -Force
    Write-Info "  - gui_config.json restored"
}
if ($jobsBackup) {
    $jobsBackup | Set-Content "$LocalInstallPath\jobs.json" -Force
    Write-Info "  - jobs.json restored"
}

# Install any new dependencies
Write-Info "Checking for new dependencies..."
$pythonPath = (Get-Command python -ErrorAction SilentlyContinue).Source
if ($pythonPath) {
    $requirementsPath = Join-Path $LocalInstallPath "requirements_gui.txt"
    if (Test-Path $requirementsPath) {
        try {
            & $pythonPath -m pip install -r $requirementsPath --quiet 2>&1 | Out-Null
            Write-Success "Dependencies up to date!"
        }
        catch {
            Write-Warn "Could not update dependencies: $_"
        }
    }
}

# Start the service
Write-Info "Starting Syncarr service..."
try {
    Start-Service -Name $ServiceName
    Start-Sleep -Seconds 3
    
    $service = Get-Service -Name $ServiceName
    if ($service.Status -eq 'Running') {
        Write-Success "Service started successfully!"
    }
    else {
        Write-Warn "Service status: $($service.Status)"
        Write-Warn "Check the logs at: $LocalInstallPath\logs"
    }
}
catch {
    Write-Err "ERROR: Failed to start service: $_"
    Write-Info "Try starting manually: Start-Service -Name $ServiceName"
}

# Display summary
Write-Host ""
Write-Host "========================================" -ForegroundColor Magenta
Write-Host "          Update Complete!             " -ForegroundColor Magenta
Write-Host "========================================" -ForegroundColor Magenta
Write-Host ""
Write-Info "Service Status: $((Get-Service -Name $ServiceName).Status)"
Write-Info "Syncarr URL: http://localhost:8000"
Write-Host ""
Write-Success "Don't forget to hard-refresh your browser (Ctrl+F5) to see UI changes!"
Write-Host ""
pause
