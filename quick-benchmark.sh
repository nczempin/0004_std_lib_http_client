#!/usr/bin/env bash
# Quick verification benchmark - tests one client from each language

set -e

cd build_release

echo "=== Quick Benchmark Verification ==="
echo "Test: 10,000 requests, small payloads (64-8192 bytes), TCP"
echo "Date: $(date)"
echo "System: $(uname -a)"
echo ""

# Generate test data
echo "Generating test data..."
./benchmark/data_generator --num-requests 10000 --min-length 64 --max-length 8192 --output benchmark_data.bin
echo ""

# Function to run a benchmark
run_benchmark() {
    local name=$1
    local cmd=$2

    echo "Testing $name..."

    # Start server
    ./benchmark/benchmark_server --transport tcp --host 127.0.0.1 --port 8080 \
        --verify false --num-responses 10000 --min-length 64 --max-length 8192 \
        > /dev/null 2>&1 &
    local server_pid=$!
    sleep 2

    # Run client and measure time
    /usr/bin/time -p $cmd 2>&1 | tee /tmp/bench_output_$$.txt

    # Extract timing
    local real_time=$(grep "^real" /tmp/bench_output_$$.txt | awk '{print $2}')

    # Cleanup server
    kill $server_pid 2>/dev/null || true
    wait $server_pid 2>/dev/null || true
    sleep 1

    echo "$name: ${real_time}s"
    echo ""
}

# Test each language
run_benchmark "C (httpc)" \
    "./benchmark/httpc_client 127.0.0.1 8080 --num-requests 10000 --data-file benchmark_data.bin --no-verify --transport tcp --output-file /dev/null"

run_benchmark "C++ (httpcpp)" \
    "./benchmark/httpcpp_client --host 127.0.0.1 --port 8080 --num-requests 10000 --data-file benchmark_data.bin --no-verify --transport tcp --output-file /dev/null"

run_benchmark "Rust (httprust)" \
    "./httprust_client 127.0.0.1 8080 --num-requests 10000 --data-file benchmark_data.bin --no-verify --transport tcp --output-file /dev/null"

run_benchmark "Python (httppy)" \
    "../.venv/bin/python3 ../benchmark/clients/python/httppy_client.py 127.0.0.1 8080 --num-requests 10000 --data-file benchmark_data.bin --no-verify --transport tcp --output-file /dev/null"

# Cleanup
rm -f /tmp/bench_output_$$.txt

echo "=== Quick benchmark complete ==="
