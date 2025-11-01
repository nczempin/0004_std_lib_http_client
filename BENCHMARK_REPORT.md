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

## Targeted Benchmark Results (Matching Documented Parameters)

**Date**: Sat Nov 1 16:57:53 CET 2025
**Environment**: WSL2 on AMD Ryzen 9 9950X (16 cores, 32 threads, 128GB host RAM)

### Small Payloads (300,000 requests, 64-8192 bytes, TCP)

| Implementation | WSL2 Time | Documented (bare metal) | Ratio |
|---|---:|---:|---:|
| C (httpc) | 27.29s | 2.681s (vectored) | **10.2x** |
| C++ (httpcpp) | 27.02s | 2.740s (safe) | **9.9x** |
| Rust (httprust) | 26.42s | 2.673s (unsafe) | **9.9x** |
| Python (httppy) | 33.03s | 4.24-4.53s | **7.3-7.8x** |

### Large Payloads (50,000 requests, 500KB-1MB, TCP)

| Implementation | WSL2 Time | Documented (bare metal) | Ratio |
|---|---:|---:|---:|
| C (httpc) | 12.77s | 5.954s (vectored) | **2.1x** |
| C++ (httpcpp) | 9.07s | 6.164s (safe) | **1.5x** |
| Rust (httprust) | 9.50s | 9.350s (safe) | **1.0x** |
| Python (httppy) | 20.77s | ~15s (estimated) | **~1.4x** |

### Critical Findings

1. **WSL2 Overhead is Workload-Dependent**:
   - Small payloads: **~10x slower** on WSL2
   - Large payloads: **1-2x slower** on WSL2
   - Python overhead is less on WSL2 (relatively)

2. **Performance Inversion on WSL2**:
   - **Small payloads**: Rust fastest (26.42s), C++ close (27.02s), C slowest (27.29s) - within 3%
   - **Large payloads**: **C++ fastest (9.07s)**, Rust close (9.50s), **C 41% slower (12.77s)**
   - This is INVERTED from bare metal where C vectored was fastest for large payloads!

3. **WSL2 Interacts Differently with I/O Patterns**:
   - Large payload overhead is much lower (1-2x vs 10x)
   - C's performance degrades more on WSL2 for large payloads
   - C++ and Rust maintain better relative performance

4. **Rust Performance is Consistent**:
   - Rust safe mode: 9.50s (WSL2) vs 9.350s (bare metal) - virtually identical!
   - Suggests Rust's I/O implementation is less affected by WSL2's network stack

### Analysis

The dramatic difference in overhead between small (10x) and large (1-2x) payloads suggests:
- Small requests hit WSL2's syscall/context switch overhead repeatedly
- Large requests are bottlenecked by throughput, where WSL2 has less overhead
- Different I/O patterns (many small vs few large syscalls) interact differently with WSL2

The performance inversion (C being slowest for large payloads on WSL2) needs investigation:
- Is C's writev() implementation hitting a WSL2 inefficiency?
- Are C++ and Rust using different buffering strategies?
- Does WSL2's network stack favor certain I/O patterns?

---

## Next Steps

1. ✅ Quick verification complete
2. ✅ Targeted benchmark complete (300k/50k parameters matching docs)
3. 📋 Investigate C's large payload performance degradation on WSL2
4. 📋 Profile implementations to identify bottlenecks
5. 📋 Test Windows native performance for comparison
6. 📋 Implement optimizations based on findings
7. 📋 (Optional) Run on bare metal for final validation
