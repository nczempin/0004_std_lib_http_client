# Targeted benchmark suite for Windows native
# Run in PowerShell from the repository root

param(
    [string]$BuildDir = "build_release"
)

$ErrorActionPreference = "Stop"

$Timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
$ReportFile = "targeted-benchmark-windows-$Timestamp.md"

# Initialize report
"# Targeted Benchmark Report" | Out-File $ReportFile
"" | Out-File $ReportFile -Append
"**Date**: $(Get-Date)" | Out-File $ReportFile -Append
"**System**: Windows $(Get-CimInstance Win32_OperatingSystem | Select-Object -ExpandProperty Caption)" | Out-File $ReportFile -Append
"" | Out-File $ReportFile -Append

# Collect hardware info
"## Hardware Specs" | Out-File $ReportFile -Append
"" | Out-File $ReportFile -Append

# CPU Info
$CPU = Get-CimInstance Win32_Processor
$CPUName = $CPU.Name
$Cores = $CPU.NumberOfCores
$LogicalProcessors = $CPU.NumberOfLogicalProcessors
$ThreadsPerCore = $LogicalProcessors / $Cores
$MaxClockSpeed = $CPU.MaxClockSpeed
$CurrentClockSpeed = $CPU.CurrentClockSpeed

"- **CPU**: $CPUName" | Out-File $ReportFile -Append
"- **CPU Topology**: $Cores cores × $ThreadsPerCore threads = $LogicalProcessors logical CPUs" | Out-File $ReportFile -Append
"- **CPU Frequency**: $CurrentClockSpeed MHz (current), $MaxClockSpeed MHz (max)" | Out-File $ReportFile -Append

# Cache Info
$L1Cache = $CPU.L1CacheSize
$L2Cache = $CPU.L2CacheSize
$L3Cache = $CPU.L3CacheSize

if ($L1Cache) { "- **L1 Cache**: $L1Cache KB" | Out-File $ReportFile -Append }
if ($L2Cache) { "- **L2 Cache**: $L2Cache KB" | Out-File $ReportFile -Append }
if ($L3Cache) { "- **L3 Cache**: $L3Cache KB" | Out-File $ReportFile -Append }

# Memory Info
$RAM = Get-CimInstance Win32_PhysicalMemory | Measure-Object -Property Capacity -Sum
$TotalRAMGB = [math]::Round($RAM.Sum / 1GB, 2)
$FreeRAM = Get-CimInstance Win32_OperatingSystem | Select-Object -ExpandProperty FreePhysicalMemory
$FreeRAMGB = [math]::Round($FreeRAM / 1MB, 2)

"- **RAM**: ${TotalRAMGB}GB total, ${FreeRAMGB}GB free" | Out-File $ReportFile -Append
"- **Environment**: Windows Native" | Out-File $ReportFile -Append
"- **OS Version**: $(Get-CimInstance Win32_OperatingSystem | Select-Object -ExpandProperty Version)" | Out-File $ReportFile -Append
"" | Out-File $ReportFile -Append

"## Test Configuration" | Out-File $ReportFile -Append
"" | Out-File $ReportFile -Append
"- **Small payload test**: 300,000 requests, 64-8192 bytes" | Out-File $ReportFile -Append
"- **Large payload test**: 50,000 requests, 500KB-1MB" | Out-File $ReportFile -Append
"- **Transport**: TCP (localhost)" | Out-File $ReportFile -Append
"- **Implementations**: C, C++, Rust, Python (safe modes only)" | Out-File $ReportFile -Append
"" | Out-File $ReportFile -Append

# Function to run a benchmark test
function Run-Test {
    param(
        [string]$TestName,
        [int]$NumRequests,
        [int]$MinLen,
        [int]$MaxLen,
        [string]$ImplName,
        [string]$Command
    )

    Write-Host "Running: $TestName - $ImplName..."

    # Generate data
    & "$BuildDir\benchmark\data_generator.exe" --num-requests $NumRequests --min-length $MinLen --max-length $MaxLen --output benchmark_data.bin | Out-Null

    # Start server
    $ServerProcess = Start-Process -FilePath "$BuildDir\benchmark\benchmark_server.exe" `
        -ArgumentList "--transport","tcp","--host","127.0.0.1","--port","8080","--verify","false","--num-responses","$NumRequests","--min-length","$MinLen","--max-length","$MaxLen" `
        -NoNewWindow -PassThru
    Start-Sleep -Seconds 2

    # Run client and measure time
    $StartTime = Get-Date
    Invoke-Expression $Command | Out-Null
    $EndTime = Get-Date
    $Elapsed = ($EndTime - $StartTime).TotalSeconds

    # Cleanup server
    Stop-Process -Id $ServerProcess.Id -Force -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 1

    "| $ImplName | ${Elapsed}s |" | Out-File $ReportFile -Append
}

Write-Host "=== Targeted Benchmark Suite (Windows) ==="
Write-Host ""

# Small Payload Tests
"## Test 1: Small Payloads (300,000 requests, 64-8192 bytes)" | Out-File $ReportFile -Append
"" | Out-File $ReportFile -Append
"| Implementation | Time |" | Out-File $ReportFile -Append
"|---|---:|" | Out-File $ReportFile -Append

if (Test-Path "$BuildDir\benchmark\httpc_client.exe") {
    Run-Test -TestName "Small" -NumRequests 300000 -MinLen 64 -MaxLen 8192 -ImplName "C (httpc)" `
        -Command "$BuildDir\benchmark\httpc_client.exe 127.0.0.1 8080 --num-requests 300000 --data-file benchmark_data.bin --no-verify --transport tcp --output-file NUL"
} else {
    Write-Warning "httpc_client.exe not found"
}

if (Test-Path "$BuildDir\benchmark\httpcpp_client.exe") {
    Run-Test -TestName "Small" -NumRequests 300000 -MinLen 64 -MaxLen 8192 -ImplName "C++ (httpcpp)" `
        -Command "$BuildDir\benchmark\httpcpp_client.exe --host 127.0.0.1 --port 8080 --num-requests 300000 --data-file benchmark_data.bin --no-verify --transport tcp --output-file NUL"
} else {
    Write-Warning "httpcpp_client.exe not found"
}

if (Test-Path "$BuildDir\httprust_client.exe") {
    Run-Test -TestName "Small" -NumRequests 300000 -MinLen 64 -MaxLen 8192 -ImplName "Rust (httprust)" `
        -Command "$BuildDir\httprust_client.exe 127.0.0.1 8080 --num-requests 300000 --data-file benchmark_data.bin --no-verify --transport tcp --output-file NUL"
} else {
    Write-Warning "httprust_client.exe not found"
}

"" | Out-File $ReportFile -Append

# Large Payload Tests
"## Test 2: Large Payloads (50,000 requests, 500KB-1MB)" | Out-File $ReportFile -Append
"" | Out-File $ReportFile -Append
"| Implementation | Time |" | Out-File $ReportFile -Append
"|---|---:|" | Out-File $ReportFile -Append

if (Test-Path "$BuildDir\benchmark\httpc_client.exe") {
    Run-Test -TestName "Large" -NumRequests 50000 -MinLen 500000 -MaxLen 1000000 -ImplName "C (httpc)" `
        -Command "$BuildDir\benchmark\httpc_client.exe 127.0.0.1 8080 --num-requests 50000 --data-file benchmark_data.bin --no-verify --transport tcp --output-file NUL"
}

if (Test-Path "$BuildDir\benchmark\httpcpp_client.exe") {
    Run-Test -TestName "Large" -NumRequests 50000 -MinLen 500000 -MaxLen 1000000 -ImplName "C++ (httpcpp)" `
        -Command "$BuildDir\benchmark\httpcpp_client.exe --host 127.0.0.1 --port 8080 --num-requests 50000 --data-file benchmark_data.bin --no-verify --transport tcp --output-file NUL"
}

if (Test-Path "$BuildDir\httprust_client.exe") {
    Run-Test -TestName "Large" -NumRequests 50000 -MinLen 500000 -MaxLen 1000000 -ImplName "Rust (httprust)" `
        -Command "$BuildDir\httprust_client.exe 127.0.0.1 8080 --num-requests 50000 --data-file benchmark_data.bin --no-verify --transport tcp --output-file NUL"
}

"" | Out-File $ReportFile -Append
"---" | Out-File $ReportFile -Append
"" | Out-File $ReportFile -Append
"**Results saved to**: $ReportFile" | Out-File $ReportFile -Append

Write-Host ""
Write-Host "=== Benchmark Complete ===" -ForegroundColor Green
Write-Host "Results saved to: $ReportFile" -ForegroundColor Cyan
Get-Content $ReportFile
