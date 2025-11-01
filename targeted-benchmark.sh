#!/usr/bin/env bash
# Targeted benchmark suite for WSL2 vs Windows comparison
# Focus: Quick but meaningful test to measure environment overhead

set -e

cd build_release

TIMESTAMP=$(date +%Y%m%d_%H%M%S)
REPORT_FILE="../targeted-benchmark-${TIMESTAMP}.md"

echo "# Targeted Benchmark Report" > "$REPORT_FILE"
echo "" >> "$REPORT_FILE"
echo "**Date**: $(date)" >> "$REPORT_FILE"
echo "**System**: $(uname -a)" >> "$REPORT_FILE"
echo "" >> "$REPORT_FILE"

# Get hardware info
echo "## Hardware Specs" >> "$REPORT_FILE"
echo "" >> "$REPORT_FILE"

# CPU Info
CPU_MODEL=$(grep "model name" /proc/cpuinfo | head -1 | cut -d: -f2 | xargs)
CPU_COUNT=$(lscpu | grep "^CPU(s):" | awk '{print $2}')
CORES_PER_SOCKET=$(lscpu | grep "Core(s) per socket" | awk '{print $4}')
THREADS_PER_CORE=$(lscpu | grep "Thread(s) per core" | awk '{print $4}')
CPU_MHZ=$(grep "cpu MHz" /proc/cpuinfo | head -1 | awk '{print $4}')

echo "- **CPU**: $CPU_MODEL" >> "$REPORT_FILE"
echo "- **CPU Topology**: $CORES_PER_SOCKET cores × $THREADS_PER_CORE threads = $CPU_COUNT logical CPUs" >> "$REPORT_FILE"
echo "- **CPU Frequency**: ${CPU_MHZ} MHz (at measurement time)" >> "$REPORT_FILE"

# Cache Info
L1D=$(lscpu | grep "L1d cache" | awk '{print $3, $4}')
L1I=$(lscpu | grep "L1i cache" | awk '{print $3, $4}')
L2=$(lscpu | grep "L2 cache" | awk '{print $3, $4}')
L3=$(lscpu | grep "L3 cache" | awk '{print $3, $4}')

echo "- **L1d Cache**: $L1D" >> "$REPORT_FILE"
echo "- **L1i Cache**: $L1I" >> "$REPORT_FILE"
echo "- **L2 Cache**: $L2" >> "$REPORT_FILE"
echo "- **L3 Cache**: $L3" >> "$REPORT_FILE"

# Memory Info
TOTAL_RAM=$(free -h | grep Mem | awk '{print $2}')
AVAILABLE_RAM=$(free -h | grep Mem | awk '{print $7}')

echo "- **RAM (VM)**: $TOTAL_RAM total, $AVAILABLE_RAM available" >> "$REPORT_FILE"

# Check if in WSL2
if grep -qi microsoft /proc/version; then
    echo "- **Environment**: WSL2 (Windows Subsystem for Linux)" >> "$REPORT_FILE"
    WSL_VERSION=$(grep -oP 'WSL2' /proc/version || echo "WSL")
    KERNEL_VERSION=$(uname -r)
    echo "- **Kernel**: $KERNEL_VERSION" >> "$REPORT_FILE"

    # Try to get Windows host RAM
    if command -v powershell.exe >/dev/null 2>&1; then
        HOST_RAM=$(powershell.exe "(Get-CimInstance Win32_PhysicalMemory | Measure-Object -Property capacity -Sum).sum / 1gb" 2>/dev/null | tr -d '\r' | xargs)
        if [ -n "$HOST_RAM" ]; then
            echo "- **Host RAM**: ${HOST_RAM}GB (Windows host)" >> "$REPORT_FILE"
        fi
    fi
else
    echo "- **Environment**: Native Linux" >> "$REPORT_FILE"
    echo "- **Kernel**: $(uname -r)" >> "$REPORT_FILE"
fi

echo "- **OS**: $(lsb_release -d 2>/dev/null | cut -f2 || cat /etc/os-release | grep PRETTY_NAME | cut -d'"' -f2)" >> "$REPORT_FILE"
echo "" >> "$REPORT_FILE"

echo "## Test Configuration" >> "$REPORT_FILE"
echo "" >> "$REPORT_FILE"
echo "- **Small payload test**: 300,000 requests, 64-8192 bytes" >> "$REPORT_FILE"
echo "- **Large payload test**: 50,000 requests, 500KB-1MB" >> "$REPORT_FILE"
echo "- **Transport**: TCP (localhost)" >> "$REPORT_FILE"
echo "- **Implementations**: C, C++, Rust, Python (safe modes only)" >> "$REPORT_FILE"
echo "" >> "$REPORT_FILE"

# Function to run benchmark and capture results
run_test() {
    local test_name=$1
    local num_requests=$2
    local min_len=$3
    local max_len=$4
    local impl_name=$5
    local cmd=$6

    echo "Running: $test_name - $impl_name..."

    # Generate data
    ./benchmark/data_generator --num-requests "$num_requests" --min-length "$min_len" --max-length "$max_len" --output benchmark_data.bin > /dev/null 2>&1

    # Start server
    ./benchmark/benchmark_server --transport tcp --host 127.0.0.1 --port 8080 \
        --verify false --num-responses "$num_requests" --min-length "$min_len" --max-length "$max_len" \
        > /dev/null 2>&1 &
    local server_pid=$!
    sleep 2

    # Run client with timing
    local start_time=$(date +%s.%N)
    eval "$cmd" > /dev/null 2>&1
    local end_time=$(date +%s.%N)

    # Calculate elapsed time
    local elapsed=$(echo "$end_time - $start_time" | bc)

    # Cleanup
    kill $server_pid 2>/dev/null || true
    wait $server_pid 2>/dev/null || true
    sleep 1

    echo "| $impl_name | ${elapsed}s |" >> "$REPORT_FILE"
}

echo "=== Targeted Benchmark Suite ==="
echo ""

# Small Payload Tests
echo "## Test 1: Small Payloads (300,000 requests, 64-8192 bytes)" >> "$REPORT_FILE"
echo "" >> "$REPORT_FILE"
echo "| Implementation | Time |" >> "$REPORT_FILE"
echo "|---|---:|" >> "$REPORT_FILE"

run_test "Small" 300000 64 8192 "C (httpc)" \
    "./benchmark/httpc_client 127.0.0.1 8080 --num-requests 300000 --data-file benchmark_data.bin --no-verify --transport tcp --output-file /dev/null"

run_test "Small" 300000 64 8192 "C++ (httpcpp)" \
    "./benchmark/httpcpp_client --host 127.0.0.1 --port 8080 --num-requests 300000 --data-file benchmark_data.bin --no-verify --transport tcp --output-file /dev/null"

run_test "Small" 300000 64 8192 "Rust (httprust)" \
    "./httprust_client 127.0.0.1 8080 --num-requests 300000 --data-file benchmark_data.bin --no-verify --transport tcp --output-file /dev/null"

run_test "Small" 300000 64 8192 "Python (httppy)" \
    "../.venv/bin/python3 ../benchmark/clients/python/httppy_client.py 127.0.0.1 8080 --num-requests 300000 --data-file benchmark_data.bin --no-verify --transport tcp --output-file /dev/null"

echo "" >> "$REPORT_FILE"

# Large Payload Tests
echo "## Test 2: Large Payloads (50,000 requests, 500KB-1MB)" >> "$REPORT_FILE"
echo "" >> "$REPORT_FILE"
echo "| Implementation | Time |" >> "$REPORT_FILE"
echo "|---|---:|" >> "$REPORT_FILE"

run_test "Large" 50000 500000 1000000 "C (httpc)" \
    "./benchmark/httpc_client 127.0.0.1 8080 --num-requests 50000 --data-file benchmark_data.bin --no-verify --transport tcp --output-file /dev/null"

run_test "Large" 50000 500000 1000000 "C++ (httpcpp)" \
    "./benchmark/httpcpp_client --host 127.0.0.1 --port 8080 --num-requests 50000 --data-file benchmark_data.bin --no-verify --transport tcp --output-file /dev/null"

run_test "Large" 50000 500000 1000000 "Rust (httprust)" \
    "./httprust_client 127.0.0.1 8080 --num-requests 50000 --data-file benchmark_data.bin --no-verify --transport tcp --output-file /dev/null"

run_test "Large" 50000 500000 1000000 "Python (httppy)" \
    "../.venv/bin/python3 ../benchmark/clients/python/httppy_client.py 127.0.0.1 8080 --num-requests 50000 --data-file benchmark_data.bin --no-verify --transport tcp --output-file /dev/null"

echo "" >> "$REPORT_FILE"
echo "---" >> "$REPORT_FILE"
echo "" >> "$REPORT_FILE"
echo "**Results saved to**: $REPORT_FILE" >> "$REPORT_FILE"

echo ""
echo "=== Benchmark Complete ==="
echo "Results saved to: $REPORT_FILE"
cat "$REPORT_FILE"
