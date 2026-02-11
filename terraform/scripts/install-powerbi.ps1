# Install Power BI Desktop using winget
# This script runs as part of VM provisioning

$LogFile = "C:\WindowsAzure\Logs\powerbi-install.log"

function Write-Log {
    param([string]$Message)
    $Timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    "$Timestamp - $Message" | Out-File -Append -FilePath $LogFile
    Write-Host $Message
}

Write-Log "Starting Power BI Desktop installation..."

try {
    # Wait for Windows to fully initialize
    Start-Sleep -Seconds 30

    # Install winget if not present (Windows 11 should have it)
    Write-Log "Checking for winget..."

    $winget = Get-Command winget -ErrorAction SilentlyContinue
    if (-not $winget) {
        Write-Log "winget not found, installing via App Installer..."

        # Download and install App Installer (contains winget)
        $appInstallerUrl = "https://aka.ms/getwinget"
        $appInstallerPath = "$env:TEMP\Microsoft.DesktopAppInstaller.msixbundle"

        Invoke-WebRequest -Uri $appInstallerUrl -OutFile $appInstallerPath -UseBasicParsing
        Add-AppxPackage -Path $appInstallerPath

        # Refresh PATH
        $env:Path = [System.Environment]::GetEnvironmentVariable("Path","Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path","User")
    }

    Write-Log "Installing Power BI Desktop via winget..."

    # Install Power BI Desktop
    winget install --id Microsoft.PowerBI --silent --accept-package-agreements --accept-source-agreements

    if ($LASTEXITCODE -eq 0) {
        Write-Log "Power BI Desktop installed successfully!"
    } else {
        Write-Log "winget returned exit code: $LASTEXITCODE"

        # Fallback: Direct download from Microsoft
        Write-Log "Trying direct download method..."

        $pbiUrl = "https://download.microsoft.com/download/8/8/0/880BCA75-79DD-466A-927D-1ABF1F5454B0/PBIDesktopSetup_x64.exe"
        $pbiInstaller = "$env:TEMP\PBIDesktopSetup_x64.exe"

        Write-Log "Downloading Power BI Desktop..."
        Invoke-WebRequest -Uri $pbiUrl -OutFile $pbiInstaller -UseBasicParsing

        Write-Log "Running installer..."
        Start-Process -FilePath $pbiInstaller -ArgumentList "-quiet", "-norestart", "ACCEPT_EULA=1" -Wait

        Write-Log "Direct installation completed."
    }

    Write-Log "Installation process finished."

} catch {
    Write-Log "ERROR: $($_.Exception.Message)"
    Write-Log $_.ScriptStackTrace
    exit 1
}
