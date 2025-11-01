# Setup script for Windows
# Run this after install-prerequisites-windows.ps1

$ErrorActionPreference = "Stop"

Write-Host "=== Windows Setup Script ===" -ForegroundColor Green
Write-Host ""

# Check prerequisites
Write-Host "Checking prerequisites..." -ForegroundColor Yellow

$missing = @()
if (!(Get-Command cmake -ErrorAction SilentlyContinue)) { $missing += "cmake" }
if (!(Get-Command python -ErrorAction SilentlyContinue)) { $missing += "python" }
if (!(Get-Command rustc -ErrorAction SilentlyContinue)) { $missing += "rustc" }

if ($missing.Count -gt 0) {
    Write-Error "Missing prerequisites: $($missing -join ', '). Please run install-prerequisites-windows.ps1 first and restart your terminal."
    Exit 1
}

Write-Host "Prerequisites found!" -ForegroundColor Green
Write-Host ""

# Create Python virtual environment
Write-Host "Setting up Python virtual environment..." -ForegroundColor Yellow
if (!(Test-Path ".venv")) {
    python -m venv .venv
    Write-Host "Virtual environment created" -ForegroundColor Green
} else {
    Write-Host "Virtual environment already exists" -ForegroundColor Cyan
}

# Activate venv and install packages
Write-Host "Installing Python packages..." -ForegroundColor Yellow
& .venv\Scripts\python.exe -m pip install --upgrade pip
& .venv\Scripts\python.exe -m pip install build

# Install Python source requirements if they exist
if (Test-Path "src\python\requirements.txt") {
    & .venv\Scripts\python.exe -m pip install -r src\python\requirements.txt
}

Write-Host ""

# Build Debug configuration
Write-Host "Building Debug configuration..." -ForegroundColor Yellow
if (!(Test-Path "build_debug")) {
    cmake -S . -B build_debug -DCMAKE_BUILD_TYPE=Debug
}
cmake --build build_debug --config Debug

Write-Host ""

# Build Release configuration
Write-Host "Building Release configuration..." -ForegroundColor Yellow
if (!(Test-Path "build_release")) {
    cmake -S . -B build_release -DCMAKE_BUILD_TYPE=Release
}
cmake --build build_release --config Release

Write-Host ""
Write-Host "=== Setup Complete ===" -ForegroundColor Green
Write-Host ""
Write-Host "Next steps:" -ForegroundColor Cyan
Write-Host "1. Run benchmarks: .\targeted-benchmark.ps1" -ForegroundColor White
Write-Host "2. Or run tests: cd build_debug; ctest --output-on-failure" -ForegroundColor White
Write-Host ""
