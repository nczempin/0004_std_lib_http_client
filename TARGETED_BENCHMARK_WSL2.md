# Targeted Benchmark Report - WSL2

**Date**: Sat Nov  1 16:57:53 CET 2025
**System**: Linux IBM650 6.6.87.2-microsoft-standard-WSL2 #1 SMP PREEMPT_DYNAMIC Thu Jun  5 18:30:46 UTC 2025 x86_64 x86_64 x86_64 GNU/Linux

**⚠️ CONTEXT**: This benchmark was run on **AMD Ryzen 9 9950X** (Zen 5, 16c/32t). The documented benchmark results in the repository were from **Intel i9-13900HX** (Raptor Lake, 24 cores: 8P+16E) on bare metal Linux. **Direct time comparisons are invalid** due to different hardware. To measure WSL2 overhead, we need Windows native results on the same Ryzen 9 9950X.

## Hardware Specs

- **CPU**: AMD Ryzen 9 9950X 16-Core Processor
- **CPU Topology**: 16 cores × 2 threads = 32 logical CPUs
- **CPU Frequency**: 4291.864 MHz (at measurement time)
- **L1d Cache**: 768 KiB
- **L1i Cache**: 512 KiB
- **L2 Cache**: 16 MiB
- **L3 Cache**: 32 MiB
- **RAM (VM)**: 61Gi total, 58Gi available
- **Environment**: WSL2 (Windows Subsystem for Linux)
- **Kernel**: 6.6.87.2-microsoft-standard-WSL2
- **Host RAM**: 128GB (Windows host)
- **OS**: Ubuntu 24.04.3 LTS

## Test Configuration

- **Small payload test**: 300,000 requests, 64-8192 bytes
- **Large payload test**: 50,000 requests, 500KB-1MB
- **Transport**: TCP (localhost)
- **Implementations**: C, C++, Rust, Python (safe modes only)

## Test 1: Small Payloads (300,000 requests, 64-8192 bytes)

| Implementation | Time |
|---|---:|
| C (httpc) | 27.285140323s |
| C++ (httpcpp) | 27.018520047s |
| Rust (httprust) | 26.415042310s |
| Python (httppy) | 33.034949083s |

## Test 2: Large Payloads (50,000 requests, 500KB-1MB)

| Implementation | Time |
|---|---:|
| C (httpc) | 12.766685075s |
| C++ (httpcpp) | 9.068302259s |
| Rust (httprust) | 9.504672841s |
| Python (httppy) | 20.770729193s |

---

**Results saved to**: ../targeted-benchmark-20251101_165753.md
