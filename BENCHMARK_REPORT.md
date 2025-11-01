# Benchmark Report: WSL2 vs Documented Results

## Quick Verification Benchmark

**Date**: Sat Nov  1 16:37:12 CET 2025
**System**: Linux IBM650 6.6.87.2-microsoft-standard-WSL2 (WSL2 on Windows)
**Test**: 10,000 requests, small payloads (64-8192 bytes), TCP
**CPU Affinity**: Not set (WSL2 limitation)

### Results - Our WSL2 Environment

| Implementation | Time (10k requests) | Relative |
|---|---:|---:|
| C (httpc) | 0.75s | 1.01x |
| C++ (httpcpp) | 0.74s | 1.00x ⭐ |
| Rust (httprust) | 0.75s | 1.01x |
| Python (httppy) | 0.98s | **1.32x** |

**Key Findings:**
- C/C++/Rust are **identical** (0.74-0.75s) - within measurement noise
- Python is **32% slower** than compiled languages
- All implementations work correctly on WSL2

---

## Comparison to Documented Results

**⚠️ IMPORTANT**: The documented results were from:
- **CPU**: Intel i9-13900HX (24 cores: 8 P-cores + 16 E-cores, mobile processor)
- **Environment**: Bare metal Linux with CPU affinity and performance tuning

**Our hardware**:
- **CPU**: AMD Ryzen 9 9950X (16 cores, 32 threads, desktop processor, Zen 5 architecture)
- **Environment**: WSL2 on Windows 11

**We CANNOT directly compare these results** as they're on completely different hardware. To isolate WSL2 overhead, we need to compare:
- WSL2 vs Windows native (same Ryzen 9 9950X) ← **This is what targeted-benchmark.ps1 will do**
- OR WSL2 vs bare metal Linux (same Ryzen 9 9950X)

### Quick Verification Results (10k requests, for sanity check only)

| Language | WSL2 (10k) | Note |
|---|---:|---|
| C | 0.75s | ✅ Working |
| C++ | 0.74s | ✅ Working |
| Rust | 0.75s | ✅ Working |
| Python | 0.98s | ✅ Working (32% slower) |

### Conclusion from Quick Test

✅ **All implementations work correctly**
✅ **Relative performance patterns are sane**
✅ **C/C++/Rust within 1% of each other**
✅ **Python appropriately slower**

⚠️ **Cannot compare absolute times to i9-13900HX results** - different CPU architecture

---

## Targeted Benchmark Results (Matching Documented Parameters)

**Date**: Sat Nov 1 16:57:53 CET 2025
**Environment**: WSL2 on AMD Ryzen 9 9950X (16 cores, 32 threads, 128GB host RAM)

### Small Payloads (300,000 requests, 64-8192 bytes, TCP)

| Implementation | WSL2 (Ryzen 9 9950X) | i9-13900HX bare metal | Note |
|---|---:|---:|---|
| C (httpc) | 27.29s | 2.681s (vectored) | Different CPU |
| C++ (httpcpp) | 27.02s | 2.740s (safe) | Different CPU |
| Rust (httprust) | 26.42s | 2.673s (unsafe) | Different CPU |
| Python (httppy) | 33.03s | 4.24-4.53s | Different CPU |

### Large Payloads (50,000 requests, 500KB-1MB, TCP)

| Implementation | WSL2 (Ryzen 9 9950X) | i9-13900HX bare metal | Note |
|---|---:|---:|---|
| C (httpc) | 12.77s | 5.954s (vectored) | Different CPU |
| C++ (httpcpp) | 9.07s | 6.164s (safe) | Different CPU |
| Rust (httprust) | 9.50s | 9.350s (safe) | Different CPU |
| Python (httppy) | 20.77s | ~15s (estimated) | Different CPU |

**⚠️ WARNING**: Ratios between these results are **NOT valid** for determining WSL2 overhead because:
- Different CPU architectures (Zen 5 vs Raptor Lake)
- Different core counts and topologies
- Different memory subsystems
- WSL2 vs bare metal AND different hardware

### Critical Findings (Valid - comparing implementations on same WSL2 system)

1. **Performance Inversion on WSL2** 🚨:
   - **Small payloads**: Rust fastest (26.42s), C++ close (27.02s), C slowest (27.29s) - within 3%
   - **Large payloads**: **C++ fastest (9.07s)**, Rust close (9.50s), **C 41% slower (12.77s)**
   - On i9-13900HX bare metal: C vectored was fastest for large payloads
   - **Hypothesis**: C's writev() may interact poorly with WSL2's network stack

2. **Language-Relative Performance**:
   - Small payloads: All compiled languages effectively tied (within 3%)
   - Large payloads: C++ and Rust significantly outperform C on WSL2
   - Python: Consistently slower (25% small, 2.3x large)

3. **Interesting Observation**:
   - Rust safe mode on WSL2 (9.50s) is very close to i9-13900HX bare metal (9.350s)
   - BUT this could be because Ryzen 9 9950X is faster, not because WSL2 is fast
   - Need Windows native or bare Linux on same hardware to confirm

### What We Need to Determine WSL2 Overhead

To actually measure WSL2 impact, we must compare on **identical hardware**:
- ✅ **Option 1**: Run targeted-benchmark.ps1 on Windows native (same Ryzen 9 9950X)
- ✅ **Option 2**: Dual-boot or live USB Linux on same machine
- ❌ **Invalid**: Comparing WSL2 Ryzen 9 9950X to i9-13900HX bare metal

---

## Next Steps

1. ✅ Quick verification complete
2. ✅ Targeted benchmark complete (300k/50k parameters matching docs)
3. 📋 Investigate C's large payload performance degradation on WSL2
4. 📋 Profile implementations to identify bottlenecks
5. 📋 Test Windows native performance for comparison
6. 📋 Implement optimizations based on findings
7. 📋 (Optional) Run on bare metal for final validation
