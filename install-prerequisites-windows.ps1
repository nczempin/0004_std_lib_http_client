# Install prerequisites for building HTTP client library on Windows
# Run this in PowerShell as Administrator

# Check if running as Administrator
if (-NOT ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator"))
{
    Write-Warning "Please run this script as Administrator!"
    Exit 1
}

Write-Host "Installing prerequisites for Windows via Chocolatey..." -ForegroundColor Green

# Install Chocolatey if not present
if (!(Get-Command choco -ErrorAction SilentlyContinue)) {
    Write-Host "Installing Chocolatey..." -ForegroundColor Yellow
    Set-ExecutionPolicy Bypass -Scope Process -Force
    [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor 3072
    Invoke-Expression ((New-Object System.Net.WebClient).DownloadString('https://community.chocolatey.org/install.ps1'))
}

Write-Host "Installing build tools..." -ForegroundColor Yellow

# Install build essentials
choco install -y cmake --installargs 'ADD_CMAKE_TO_PATH=System'
choco install -y visualstudio2022buildtools --package-parameters "--add Microsoft.VisualStudio.Workload.VCTools --includeRecommended"
choco install -y python312
choco install -y git

# Install Rust via rustup
if (!(Get-Command rustc -ErrorAction SilentlyContinue)) {
    Write-Host "Installing Rust via rustup..." -ForegroundColor Yellow
    Invoke-WebRequest -Uri https://win.rustup.rs/x86_64 -OutFile "$env:TEMP\rustup-init.exe"
    & "$env:TEMP\rustup-init.exe" -y --default-toolchain stable
    Remove-Item "$env:TEMP\rustup-init.exe"

    # Add Rust to PATH for current session
    $env:Path += ";$env:USERPROFILE\.cargo\bin"
}

Write-Host ""
Write-Host "Refreshing environment..." -ForegroundColor Yellow
refreshenv

Write-Host ""
Write-Host "Verifying installations..." -ForegroundColor Green
Write-Host "CMake version:" -NoNewline
cmake --version | Select-String "cmake version"

Write-Host "Python version:" -NoNewline
python --version

Write-Host "Rust version:" -NoNewline
& "$env:USERPROFILE\.cargo\bin\rustc" --version

Write-Host ""
Write-Host "Prerequisites installed successfully!" -ForegroundColor Green
Write-Host "Note: You may need to restart your terminal/PowerShell for PATH changes to take effect." -ForegroundColor Yellow
Write-Host ""
Write-Host "Next steps:" -ForegroundColor Cyan
Write-Host "1. Clone the repository: git clone <repo-url>" -ForegroundColor White
Write-Host "2. Checkout the branch: git checkout feature/3-perf-explore-optimizations" -ForegroundColor White
Write-Host "3. Run setup: .\setup-windows.ps1" -ForegroundColor White
