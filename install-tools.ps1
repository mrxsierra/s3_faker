# Ensure script is running as an administrator
if (-not([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")) {
    Write-Host "Please run this script as an administrator."
    exit
}

# --- Helper Functions ---
# A general function that checks the registry (HKLM) for a given program name.
# (Note: Some per-user apps may not show here, so for VS Code we use a file existence check.)
function Test-ProgramInstalled($programName) {
    $installed = Get-ItemProperty "HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*" -ErrorAction SilentlyContinue |
        Where-Object { $_.DisplayName -like "*$programName*" }
    return $installed
}

# Function to check if VS Code is installed by verifying its default executable path.
function Test-VSCodeInstalled() {
    $vsCodePath = "$env:LOCALAPPDATA\Programs\Microsoft VS Code\Code.exe"
    return (Test-Path $vsCodePath)
}

# Function to check if Git is installed by trying to run 'git --version'
function Test-GitInstalled() {
    try {
        git --version | Out-Null
        return $true
    }
    catch {
        return $false
    }
}

# --- Installation Section ---

# 1. Visual Studio Code
$installVSCode = Read-Host "Do you want to install Visual Studio Code? (Y/N)"
if ($installVSCode.Trim().ToUpper() -eq "Y") {
    if (-not (Test-VSCodeInstalled)) {
        $vscodeInstallerPath = "$env:LOCALAPPDATA\Programs\Microsoft VS Code\Code.exe"
        $vscodeInstallerUrl = "https://update.code.visualstudio.com/latest/win32-x64-user/stable"
        Write-Host "Downloading Visual Studio Code Installer..."
        Invoke-WebRequest -Uri $vscodeInstallerUrl -OutFile $vscodeInstallerPath
        Write-Host "Installing Visual Studio Code..."
        Start-Process -FilePath $vscodeInstallerPath -ArgumentList "/silent", "/mergetasks=!runcode" -Wait
        Write-Host "Visual Studio Code installed."
    }
    else {
        Write-Host "Visual Studio Code is already installed."
    }
}
else {
    Write-Host "Skipping Visual Studio Code installation."
}

# 2. Docker Desktop
$installDocker = Read-Host "Do you want to install Docker Desktop? (Y/N)"
if ($installDocker.Trim().ToUpper() -eq "Y") {
    if (-not (Test-ProgramInstalled "Docker Desktop")) {
        $dockerInstallerPath = "C:\Temp\DockerDesktopInstaller.exe"
        $dockerInstallerUrl = "https://desktop.docker.com/win/stable/Docker%20Desktop%20Installer.exe"
        if (-not (Test-Path $dockerInstallerPath)) {
            Write-Host "Downloading Docker Desktop Installer..."
            Invoke-WebRequest -Uri $dockerInstallerUrl -OutFile $dockerInstallerPath
        }
        Write-Host "Installing Docker Desktop..."
        Start-Process -FilePath $dockerInstallerPath -ArgumentList "/install", "/quiet" -Wait
        Write-Host "Docker Desktop installed. Please restart your computer if this is the first installation."
    }
    else {
        Write-Host "Docker Desktop is already installed."
    }
    # Optional Docker configuration (e.g. login to Docker Hub)
    $configureDocker = Read-Host "Would you like to log in to Docker Desktop (Docker Hub)? (Y/N)"
    if ($configureDocker.Trim().ToUpper() -eq "Y") {
        Write-Host "Opening Docker login prompt..."
        docker login
    }
    else {
        Write-Host "Skipping Docker Desktop additional configuration."
    }
}
else {
    Write-Host "Skipping Docker Desktop installation."
}

# 3. UV for Project Management
$installUV = Read-Host "Do you want to install UV for project management? (Y/N)"
if ($installUV.Trim().ToUpper() -eq "Y") {
    if (-not (Test-ProgramInstalled "UV")) {
        Write-Host "Installing UV for project management..."
        Invoke-Expression (New-Object System.Net.WebClient).DownloadString('https://astral.sh/uv/install.ps1')
        Write-Host "UV installed."
    }
    else {
        Write-Host "UV is already installed."
    }
}
else {
    Write-Host "Skipping UV installation."
}

# 4. Git
$installGit = Read-Host "Do you want to install Git? (Y/N)"
if ($installGit.Trim().ToUpper() -eq "Y") {
    if (-not (Test-GitInstalled)) {
        $gitInstallerPath = "C:\Temp\GitInstaller.exe"
        Write-Host "Determining latest Git for Windows release..."
        $headers = @{ "User-Agent" = "PowerShellScript" }
        try {
            $gitLatest = Invoke-RestMethod -Uri "https://api.github.com/repos/git-for-windows/git/releases/latest" -Headers $headers
            $asset = $gitLatest.assets | Where-Object { $_.name -match "Git-.*-64-bit\.exe" } | Select-Object -First 1
            if ($null -eq $asset) {
                Write-Host "Could not determine the latest Git installer. Please check manually."
                exit
            }
            $gitInstallerUrl = $asset.browser_download_url
            Write-Host "Latest Git installer URL: $gitInstallerUrl"
        }
        catch {
            Write-Host "Error retrieving Git release information. Please check your internet connection."
            exit
        }
        Write-Host "Downloading Git Installer..."
        Invoke-WebRequest -Uri $gitInstallerUrl -OutFile $gitInstallerPath
        Write-Host "Installing Git..."
        Start-Process -FilePath $gitInstallerPath -ArgumentList "/VERYSILENT", "/NORESTART" -Wait
        Write-Host "Git installed."
    }
    else {
        Write-Host "Git is already installed."
    }
    # Additional Git configuration: global username/email.
    $configureGit = Read-Host "Would you like to configure Git global settings (username & email)? (Y/N)"
    if ($configureGit.Trim().ToUpper() -eq "Y") {
        $gitUserName = Read-Host "Enter your Git user.name"
        $gitUserEmail = Read-Host "Enter your Git user.email"
        git config --global user.name "$gitUserName"
        git config --global user.email "$gitUserEmail"
        Write-Host "Git global configuration updated."
    }
    else {
        Write-Host "Skipping Git global configuration."
    }
    # Additional SSH Key Configuration for Git repositories.
    $configureSSH = Read-Host "Would you like to generate and configure SSH keys for Git? (Y/N)"
    if ($configureSSH.Trim().ToUpper() -eq "Y") {
        $sshKeyPath = "$env:USERPROFILE\.ssh\id_rsa"
        if (-not (Test-Path $sshKeyPath)) {
            $emailForKey = Read-Host "Enter the email for your SSH key"
            Write-Host "Generating new SSH key..."
            ssh-keygen -t rsa -b 4096 -C $emailForKey -f $sshKeyPath -N ""
        }
        else {
            Write-Host "SSH key already exists at $sshKeyPath."
        }
        Write-Host "Starting the SSH agent..."
        # Start the ssh-agent (works in PowerShell 5.1+ if OpenSSH is installed)
        Start-Process ssh-agent -ArgumentList "-s" -NoNewWindow -Wait
        Write-Host "Adding your SSH key to the agent..."
        ssh-add $sshKeyPath
        Write-Host "Copying your public SSH key to clipboard..."
        if (Test-Path "$env:USERPROFILE\.ssh\id_rsa.pub") {
            Get-Content "$env:USERPROFILE\.ssh\id_rsa.pub" | clip
            Write-Host "Your public SSH key has been copied to the clipboard."
            Write-Host "Please add it to your Git hosting provider (e.g. GitHub under 'SSH and GPG keys')."
        }
        else {
            Write-Host "Public key not found. Please check your SSH key generation."
        }
    }
    else {
        Write-Host "Skipping SSH key configuration."
    }
}
else {
    Write-Host "Skipping Git installation."
}

# 5. Set Up LocalStack (Docker) with Optional Auth Token
$setupLocalStack = Read-Host "Do you want to set up LocalStack (Docker container)? (Y/N)"
if ($setupLocalStack.Trim().ToUpper() -eq "Y") {
    # Prompt for an optional LocalStack Auth Token
    $localstackToken = Read-Host "Enter your LocalStack Auth Token (leave blank if not applicable)"
    Write-Host "Pulling the latest LocalStack Docker image..."
    docker pull localstack/localstack:latest
    Write-Host "Starting LocalStack Docker container..."
    if ([string]::IsNullOrEmpty($localstackToken)) {
        docker run -d -p 4566:4566 -p 4571:4571 localstack/localstack:latest
    }
    else {
        docker run -d -p 4566:4566 -p 4571:4571 -e LOCALSTACK_AUTH_TOKEN=$localstackToken localstack/localstack:latest
    }
    Write-Host "LocalStack is up and running. For Docker Compose usage, include LOCALSTACK_AUTH_TOKEN in your docker-compose.yml file."
}
else {
    Write-Host "Skipping LocalStack setup."
}
