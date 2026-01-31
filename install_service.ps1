# Syncarr Windows Service Installer
# This script installs Syncarr as a Windows service using NSSM (Non-Sucking Service Manager)
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
Write-Host "   Syncarr Windows Service Installer   " -ForegroundColor Magenta
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

# Get the directory where this script is located (Syncarr-GUI folder)
$SourcePath = Split-Path -Parent $MyInvocation.MyCommand.Path
$LocalInstallPath = "C:\ProgramData\Syncarr"

# Check if running from a network path (UNC)
$isNetworkPath = $SourcePath -match "^\\\\" -or $SourcePath -match "^//"

if ($isNetworkPath) {
    Write-Warn "Detected network path: $SourcePath"
    Write-Warn "Windows services cannot run from network shares by default."
    Write-Host ""
    Write-Info "Syncarr will be copied to: $LocalInstallPath"
    Write-Info "(This is how Radarr and Sonarr work - they run from local folders)"
    Write-Host ""
    
    $proceed = Read-Host "Copy files and install locally? (Y/N)"
    if ($proceed -ne 'Y' -and $proceed -ne 'y') {
        Write-Info "Installation cancelled."
        pause
        exit 0
    }
    
    # Copy files to local path
    Write-Info "Copying Syncarr to $LocalInstallPath..."
    try {
        if (Test-Path $LocalInstallPath) {
            Write-Warn "Existing installation found. Removing old files..."
            # Keep config files
            $configBackup = $null
            $jobsBackup = $null
            if (Test-Path "$LocalInstallPath\gui_config.json") {
                $configBackup = Get-Content "$LocalInstallPath\gui_config.json" -Raw
            }
            if (Test-Path "$LocalInstallPath\jobs.json") {
                $jobsBackup = Get-Content "$LocalInstallPath\jobs.json" -Raw
            }
            Remove-Item $LocalInstallPath -Recurse -Force
        }
        
        # Create destination folder first
        New-Item -ItemType Directory -Path $LocalInstallPath -Force | Out-Null
        
        # Copy all contents (files and folders) into the destination
        Get-ChildItem -Path $SourcePath | ForEach-Object {
            Copy-Item -Path $_.FullName -Destination $LocalInstallPath -Recurse -Force
        }
        
        # Ensure logs folder exists
        $logsPath = Join-Path $LocalInstallPath "logs"
        if (-not (Test-Path $logsPath)) {
            New-Item -ItemType Directory -Path $logsPath -Force | Out-Null
        }
        
        # Restore config files if they existed
        if ($configBackup) {
            $configBackup | Set-Content "$LocalInstallPath\gui_config.json" -Force
            Write-Info "Restored gui_config.json"
        }
        if ($jobsBackup) {
            $jobsBackup | Set-Content "$LocalInstallPath\jobs.json" -Force
            Write-Info "Restored jobs.json"
        }
        
        Write-Success "Files copied successfully!"
        $SyncarrPath = $LocalInstallPath
    }
    catch {
        Write-Err "ERROR: Failed to copy files: $_"
        pause
        exit 1
    }
}
else {
    $SyncarrPath = $SourcePath
}

Write-Info "Syncarr directory: $SyncarrPath"

# Find Python executable
Write-Info "Detecting Python installation..."
$pythonPath = $null

# Try common Python locations
$pythonLocations = @(
    (Get-Command python -ErrorAction SilentlyContinue).Source,
    (Get-Command python3 -ErrorAction SilentlyContinue).Source,
    "$env:LOCALAPPDATA\Programs\Python\Python312\python.exe",
    "$env:LOCALAPPDATA\Programs\Python\Python311\python.exe",
    "$env:LOCALAPPDATA\Programs\Python\Python310\python.exe",
    "C:\Python312\python.exe",
    "C:\Python311\python.exe",
    "C:\Python310\python.exe"
)

foreach ($loc in $pythonLocations) {
    if ($loc -and (Test-Path $loc -ErrorAction SilentlyContinue)) {
        $pythonPath = $loc
        break
    }
}

if (-not $pythonPath) {
    Write-Err "ERROR: Python not found! Please install Python and try again."
    pause
    exit 1
}

Write-Success "Found Python at: $pythonPath"

# Install Python dependencies
Write-Info "Installing Python dependencies..."
$requirementsPath = Join-Path $SyncarrPath "requirements_gui.txt"
if (Test-Path $requirementsPath) {
    try {
        & $pythonPath -m pip install --upgrade pip --quiet 2>&1 | Out-Null
        $pipOutput = & $pythonPath -m pip install -r $requirementsPath 2>&1
        if ($LASTEXITCODE -eq 0) {
            Write-Success "Dependencies installed successfully!"
        }
        else {
            Write-Warn "pip warning: $pipOutput"
        }
    }
    catch {
        Write-Warn "Warning: Could not install dependencies: $_"
        Write-Info "You may need to run: pip install -r requirements_gui.txt"
    }
}
else {
    Write-Warn "requirements_gui.txt not found, skipping dependency installation"
}

# Verify web_app.py exists
$webAppPath = Join-Path $SyncarrPath "web_app.py"
if (-not (Test-Path $webAppPath)) {
    Write-Err "ERROR: web_app.py not found at $webAppPath"
    Write-Err "Please run this script from the Syncarr-GUI directory."
    pause
    exit 1
}

# Check if service already exists
$existingService = Get-Service -Name $ServiceName -ErrorAction SilentlyContinue
if ($existingService) {
    Write-Warn "Service '$ServiceName' already exists. Status: $($existingService.Status)"
    $choice = Read-Host "Do you want to remove and reinstall it? (Y/N)"
    if ($choice -eq 'Y' -or $choice -eq 'y') {
        Write-Info "Stopping and removing existing service..."
        if ($existingService.Status -eq 'Running') {
            Stop-Service -Name $ServiceName -Force
            Start-Sleep -Seconds 2
        }
        
        # Find nssm to remove the service properly
        $nssmExe = Join-Path $NssmPath "nssm.exe"
        if (Test-Path $nssmExe) {
            & $nssmExe remove $ServiceName confirm
        }
        else {
            sc.exe delete $ServiceName
        }
        Start-Sleep -Seconds 2
        Write-Success "Existing service removed."
    }
    else {
        Write-Info "Installation cancelled."
        pause
        exit 0
    }
}

# Use bundled NSSM from tools folder (no download needed!)
$bundledNssm = Join-Path $SyncarrPath "tools\nssm.exe"
$systemNssm = Join-Path $NssmPath "nssm.exe"

if (Test-Path $bundledNssm) {
    # Use the bundled version
    $nssmExe = $bundledNssm
    Write-Success "Using bundled NSSM from: $nssmExe"
}
elseif (Test-Path $systemNssm) {
    # Fall back to system-installed version
    $nssmExe = $systemNssm
    Write-Info "Using system NSSM at: $nssmExe"
}
else {
    Write-Err "ERROR: NSSM not found!"
    Write-Err "Expected at: $bundledNssm"
    Write-Info "Please ensure the tools folder contains nssm.exe"
    pause
    exit 1
}

# Install the service
Write-Info "Installing Syncarr service..."

try {
    # Install service with nssm
    & $nssmExe install $ServiceName $pythonPath
    
    # Configure the service
    & $nssmExe set $ServiceName AppParameters "web_app.py"
    & $nssmExe set $ServiceName AppDirectory $SyncarrPath
    & $nssmExe set $ServiceName DisplayName "Syncarr Web GUI"
    & $nssmExe set $ServiceName Description "Syncarr - Media library synchronization service for Radarr and Sonarr"
    & $nssmExe set $ServiceName Start SERVICE_AUTO_START
    & $nssmExe set $ServiceName AppStdout (Join-Path $SyncarrPath "logs\service_stdout.log")
    & $nssmExe set $ServiceName AppStderr (Join-Path $SyncarrPath "logs\service_stderr.log")
    & $nssmExe set $ServiceName AppRotateFiles 1
    & $nssmExe set $ServiceName AppRotateBytes 1048576
    
    # Create logs directory if it doesn't exist
    $logsPath = Join-Path $SyncarrPath "logs"
    if (-not (Test-Path $logsPath)) {
        New-Item -ItemType Directory -Path $logsPath -Force | Out-Null
    }
    
    Write-Success "Service installed successfully!"
}
catch {
    Write-Err "ERROR: Failed to install service: $_"
    pause
    exit 1
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
        Write-Warn "Check the logs at: $logsPath"
    }
}
catch {
    Write-Err "ERROR: Failed to start service: $_"
    Write-Info "Try starting manually: Start-Service -Name $ServiceName"
}

# Display summary
Write-Host ""
Write-Host "========================================" -ForegroundColor Magenta
Write-Host "         Installation Complete!        " -ForegroundColor Magenta
Write-Host "========================================" -ForegroundColor Magenta
Write-Host ""
Write-Info "Service Name:    $ServiceName"
Write-Info "Status:          $((Get-Service -Name $ServiceName).Status)"
Write-Info "Startup Type:    Automatic"
Write-Info "Log Files:       $logsPath"
Write-Host ""
Write-Info "Manage the service with these commands:"
Write-Host "  Start:    " -NoNewline; Write-Host "Start-Service $ServiceName" -ForegroundColor White
Write-Host "  Stop:     " -NoNewline; Write-Host "Stop-Service $ServiceName" -ForegroundColor White
Write-Host "  Restart:  " -NoNewline; Write-Host "Restart-Service $ServiceName" -ForegroundColor White
Write-Host "  Status:   " -NoNewline; Write-Host "Get-Service $ServiceName" -ForegroundColor White
Write-Host ""
Write-Info "Or use Windows Services (services.msc) to manage the service."
Write-Host ""
Write-Success "Syncarr should now be accessible at: http://localhost:8000"
Write-Host ""
pause
