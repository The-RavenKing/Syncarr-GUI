# Syncarr Complete Setup Script
# This script handles everything: Python, dependencies, and Windows service installation

$ErrorActionPreference = "Stop"
$ProgressPreference = 'SilentlyContinue'

# Colors for output
function Write-Success { param($msg) Write-Host $msg -ForegroundColor Green }
function Write-Info { param($msg) Write-Host $msg -ForegroundColor Cyan }
function Write-Warn { param($msg) Write-Host $msg -ForegroundColor Yellow }
function Write-Err { param($msg) Write-Host $msg -ForegroundColor Red }
function Write-Step { param($step, $msg) Write-Host "`n[$step] " -ForegroundColor Magenta -NoNewline; Write-Host $msg -ForegroundColor White }

# Get script directory
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$ServiceName = "Syncarr"
$NssmPath = "$env:ProgramData\nssm"
$PythonMinVersion = [version]"3.8.0"

Clear-Host
Write-Host ""
Write-Host "  ╔═══════════════════════════════════════════════════════════╗" -ForegroundColor Cyan
Write-Host "  ║                                                           ║" -ForegroundColor Cyan
Write-Host "  ║             SYNCARR INSTALLER                             ║" -ForegroundColor Cyan
Write-Host "  ║                                                           ║" -ForegroundColor Cyan
Write-Host "  ║   Automated setup for Syncarr Web GUI                     ║" -ForegroundColor Cyan
Write-Host "  ║   • Installs Python (if needed)                           ║" -ForegroundColor Cyan
Write-Host "  ║   • Installs dependencies                                 ║" -ForegroundColor Cyan
Write-Host "  ║   • Sets up Windows service                               ║" -ForegroundColor Cyan
Write-Host "  ║                                                           ║" -ForegroundColor Cyan
Write-Host "  ╚═══════════════════════════════════════════════════════════╝" -ForegroundColor Cyan
Write-Host ""

# Check for Administrator privileges
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    Write-Err "ERROR: This script must be run as Administrator!"
    Write-Info "Please right-click 'Install-Syncarr.bat' and select 'Run as administrator'"
    Read-Host "Press Enter to exit"
    exit 1
}

Write-Success "Running with Administrator privileges"

#region STEP 1: Check/Install Python
Write-Step "1/4" "Checking Python installation..."

$pythonPath = $null
$pythonVersion = $null

# Try to find Python
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
        try {
            $versionOutput = & $loc --version 2>&1
            if ($versionOutput -match "Python (\d+\.\d+\.\d+)") {
                $currentVersion = [version]$Matches[1]
                if ($currentVersion -ge $PythonMinVersion) {
                    $pythonPath = $loc
                    $pythonVersion = $currentVersion
                    break
                }
            }
        }
        catch { }
    }
}

if ($pythonPath) {
    Write-Success "Found Python $pythonVersion at: $pythonPath"
}
else {
    Write-Warn "Python 3.8+ not found. Installing Python..."
    
    # Download Python installer
    $pythonInstallerUrl = "https://www.python.org/ftp/python/3.12.2/python-3.12.2-amd64.exe"
    $pythonInstallerPath = Join-Path $env:TEMP "python-installer.exe"
    
    try {
        Write-Info "Downloading Python 3.12.2..."
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
        Invoke-WebRequest -Uri $pythonInstallerUrl -OutFile $pythonInstallerPath -UseBasicParsing
        
        Write-Info "Installing Python (this may take a few minutes)..."
        # Silent install with pip, add to PATH
        $installArgs = "/quiet InstallAllUsers=1 PrependPath=1 Include_pip=1"
        Start-Process -FilePath $pythonInstallerPath -ArgumentList $installArgs -Wait -NoNewWindow
        
        # Refresh environment variables
        $env:Path = [System.Environment]::GetEnvironmentVariable("Path", "Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path", "User")
        
        # Find the newly installed Python
        Start-Sleep -Seconds 2
        $pythonPath = (Get-Command python -ErrorAction SilentlyContinue).Source
        
        if (-not $pythonPath) {
            # Try common install location
            $pythonPath = "C:\Program Files\Python312\python.exe"
            if (-not (Test-Path $pythonPath)) {
                $pythonPath = "$env:LOCALAPPDATA\Programs\Python\Python312\python.exe"
            }
        }
        
        if (Test-Path $pythonPath) {
            Write-Success "Python installed successfully!"
        }
        else {
            throw "Python installation completed but python.exe not found"
        }
        
        # Cleanup
        Remove-Item $pythonInstallerPath -Force -ErrorAction SilentlyContinue
    }
    catch {
        Write-Err "ERROR: Failed to install Python: $_"
        Write-Info "Please install Python 3.8+ manually from https://www.python.org/downloads/"
        Write-Info "Make sure to check 'Add Python to PATH' during installation."
        Read-Host "Press Enter to exit"
        exit 1
    }
}
#endregion

#region STEP 2: Install Python Dependencies
Write-Step "2/4" "Installing Python dependencies..."

$requirementsPath = Join-Path $ScriptDir "requirements_gui.txt"
if (-not (Test-Path $requirementsPath)) {
    Write-Err "ERROR: requirements_gui.txt not found!"
    Write-Err "Please ensure you're running this from the Syncarr-GUI folder."
    Read-Host "Press Enter to exit"
    exit 1
}

try {
    # Upgrade pip first
    Write-Info "Upgrading pip..."
    & $pythonPath -m pip install --upgrade pip --quiet 2>&1 | Out-Null
    
    # Install requirements
    Write-Info "Installing required packages..."
    $pipOutput = & $pythonPath -m pip install -r $requirementsPath 2>&1
    
    if ($LASTEXITCODE -ne 0) {
        Write-Warn "pip output: $pipOutput"
        throw "pip install failed"
    }
    
    Write-Success "Dependencies installed successfully!"
}
catch {
    Write-Err "ERROR: Failed to install dependencies: $_"
    Write-Info "Try running manually: pip install -r requirements_gui.txt"
    Read-Host "Press Enter to exit"
    exit 1
}
#endregion

#region STEP 3: Setup NSSM
Write-Step "3/4" "Setting up service manager..."

# Use bundled NSSM from tools folder (no download needed!)
$bundledNssm = Join-Path $ScriptDir "tools\nssm.exe"
$systemNssm = Join-Path $NssmPath "nssm.exe"

if (Test-Path $bundledNssm) {
    # Use the bundled version
    $nssmExe = $bundledNssm
    Write-Success "Using bundled NSSM"
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
    Read-Host "Press Enter to exit"
    exit 1
}
#endregion

#region STEP 4: Install Windows Service
Write-Step "4/4" "Installing Syncarr Windows service..."

# Check if service already exists
$existingService = Get-Service -Name $ServiceName -ErrorAction SilentlyContinue
if ($existingService) {
    Write-Warn "Service '$ServiceName' already exists (Status: $($existingService.Status))"
    $choice = Read-Host "Remove and reinstall? (Y/N)"
    
    if ($choice -eq 'Y' -or $choice -eq 'y') {
        Write-Info "Stopping existing service..."
        if ($existingService.Status -eq 'Running') {
            Stop-Service -Name $ServiceName -Force
            Start-Sleep -Seconds 2
        }
        & $nssmExe remove $ServiceName confirm 2>&1 | Out-Null
        Start-Sleep -Seconds 2
        Write-Info "Existing service removed"
    }
    else {
        Write-Info "Keeping existing service"
        goto SkipServiceInstall
    }
}

try {
    # Install service
    Write-Info "Creating Windows service..."
    & $nssmExe install $ServiceName $pythonPath 2>&1 | Out-Null
    
    # Configure service
    & $nssmExe set $ServiceName AppParameters "web_app.py" 2>&1 | Out-Null
    & $nssmExe set $ServiceName AppDirectory $ScriptDir 2>&1 | Out-Null
    & $nssmExe set $ServiceName DisplayName "Syncarr Web GUI" 2>&1 | Out-Null
    & $nssmExe set $ServiceName Description "Syncarr - Media library synchronization for Radarr and Sonarr" 2>&1 | Out-Null
    & $nssmExe set $ServiceName Start SERVICE_AUTO_START 2>&1 | Out-Null
    
    # Setup logging
    $logsPath = Join-Path $ScriptDir "logs"
    if (-not (Test-Path $logsPath)) {
        New-Item -ItemType Directory -Path $logsPath -Force | Out-Null
    }
    & $nssmExe set $ServiceName AppStdout (Join-Path $logsPath "service_stdout.log") 2>&1 | Out-Null
    & $nssmExe set $ServiceName AppStderr (Join-Path $logsPath "service_stderr.log") 2>&1 | Out-Null
    & $nssmExe set $ServiceName AppRotateFiles 1 2>&1 | Out-Null
    & $nssmExe set $ServiceName AppRotateBytes 1048576 2>&1 | Out-Null
    
    Write-Success "Service installed!"
    
    # Start the service
    Write-Info "Starting Syncarr service..."
    Start-Service -Name $ServiceName
    Start-Sleep -Seconds 3
    
    $service = Get-Service -Name $ServiceName
    if ($service.Status -eq 'Running') {
        Write-Success "Service started successfully!"
    }
    else {
        Write-Warn "Service status: $($service.Status) - Check logs folder for details"
    }
}
catch {
    Write-Err "ERROR: Failed to install service: $_"
    Read-Host "Press Enter to exit"
    exit 1
}

:SkipServiceInstall
#endregion

#region Complete!
Write-Host ""
Write-Host "  ╔═══════════════════════════════════════════════════════════╗" -ForegroundColor Green
Write-Host "  ║                                                           ║" -ForegroundColor Green
Write-Host "  ║             INSTALLATION COMPLETE!                        ║" -ForegroundColor Green
Write-Host "  ║                                                           ║" -ForegroundColor Green
Write-Host "  ╚═══════════════════════════════════════════════════════════╝" -ForegroundColor Green
Write-Host ""

$service = Get-Service -Name $ServiceName -ErrorAction SilentlyContinue
if ($service) {
    Write-Info "Service Status: $($service.Status)"
}

Write-Host ""
Write-Host "  Access Syncarr at: " -NoNewline -ForegroundColor White
Write-Host "http://localhost:8000" -ForegroundColor Yellow
Write-Host ""
Write-Host "  Default Login:" -ForegroundColor White
Write-Host "    Username: admin" -ForegroundColor Gray
Write-Host "    Password: admin" -ForegroundColor Gray
Write-Host ""
Write-Warn "  Remember to change the default password in Settings!"
Write-Host ""
Write-Host "  Manage the service:" -ForegroundColor White
Write-Host "    • Windows Services (services.msc) - look for 'Syncarr Web GUI'" -ForegroundColor Gray
Write-Host "    • PowerShell: Start-Service Syncarr / Stop-Service Syncarr" -ForegroundColor Gray
Write-Host ""

# Try to open browser
$openBrowser = Read-Host "Open Syncarr in your browser now? (Y/N)"
if ($openBrowser -eq 'Y' -or $openBrowser -eq 'y') {
    Start-Process "http://localhost:8000"
}

Read-Host "`nPress Enter to exit"
#endregion
