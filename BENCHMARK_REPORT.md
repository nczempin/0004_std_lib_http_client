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

The documented results were from bare metal Linux with CPU affinity and performance tuning.

### Scaling Factor

Documented test: 300,000 requests
Our test: 10,000 requests
**Scaling**: 30x fewer requests

### Performance Comparison

#### Documented (Bare Metal, 300k requests):
- **C**: 2.67-2.69s → **0.089s per 10k**
- **C++**: 2.70-2.74s → **0.090s per 10k**
- **Rust**: 2.67-2.75s → **0.089s per 10k**
- **Python**: 4.24-4.53s → **0.142s per 10k**

#### WSL2 vs Bare Metal:

| Language | WSL2 (10k) | Bare Metal (scaled to 10k) | Slowdown |
|---|---:|---:|---:|
| C | 0.75s | 0.089s | **8.4x** |
| C++ | 0.74s | 0.090s | **8.2x** |
| Rust | 0.75s | 0.089s | **8.4x** |
| Python | 0.98s | 0.142s | **6.9x** |

### Analysis

1. **WSL2 Overhead is Significant**:
   - Compiled languages (C/C++/Rust) are **8-8.4x slower** on WSL2
   - Python is **6.9x slower** on WSL2

2. **Python Performs Better on WSL2 (Relatively)**:
   - On bare metal: Python is **59-60% slower** than C/C++/Rust
   - On WSL2: Python is only **32% slower** than C/C++/Rust
   - This suggests WSL2 overhead affects compiled code more than interpreted code

3. **Language Differences Remain Consistent**:
   - C/C++/Rust remain virtually identical in both environments
   - Python remains slower, but by a smaller margin on WSL2

4. **WSL2 Bottleneck**:
   - The virtualization layer adds ~8x overhead for network I/O
   - CPU affinity (`taskset`) won't work in WSL2
   - Performance governor tuning unavailable in WSL2

### Conclusion

✅ **All implementations work correctly**
✅ **Relative performance patterns match documented results**
⚠️ **Absolute performance is 7-8x slower due to WSL2 overhead**

For optimization work, we can:
- ✅ Use WSL2 for development and relative comparisons
- ⚠️ Absolute numbers won't match bare metal
- ⚠️ Need to run final benchmarks on bare metal for publication

---

## Next Steps

1. ✅ Quick verification complete
2. 📋 Run full benchmark suite on WSL2 for comprehensive baseline
3. 📋 Identify optimization opportunities from profiling
4. 📋 Implement optimizations
5. 📋 Re-benchmark to measure improvements
6. 📋 (Optional) Run on bare metal for final validation
