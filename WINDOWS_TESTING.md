# Windows Native Performance Testing

This guide explains how to run benchmarks on Windows native (not WSL2) to compare performance.

## Purpose

The documented benchmark results were from an **Intel i9-13900HX** (mobile processor, 24 cores: 8 P-cores + 16 E-cores) on bare metal Linux. Our system has an **AMD Ryzen 9 9950X** (desktop processor, 16 cores, 32 threads, Zen 5 architecture).

**We cannot determine WSL2 overhead by comparing different CPUs.** To properly measure WSL2's impact, we need to test:
- WSL2 vs Windows native (same Ryzen 9 9950X) ← **This is the goal**
- OR WSL2 vs bare metal Linux (same Ryzen 9 9950X)

## Hardware Specs

- **CPU**: AMD Ryzen 9 9950X 16-Core Processor (Zen 5)
- **Cores**: 16 cores / 32 threads
- **RAM**: 62 GB
- **L3 Cache**: 32 MB

## Prerequisites Installation

### Option 1: PowerShell Script (Recommended)

Run PowerShell as Administrator, then:

```powershell
.\install-prerequisites-windows.ps1
```

This installs via Chocolatey:
- CMake
- Visual Studio 2022 Build Tools (C/C++ compiler)
- Python 3.12
- Rust (via rustup)
- Git

### Option 2: Manual Installation

If the script fails or you prefer manual installation:

1. Install [Chocolatey](https://chocolatey.org/install)
2. Open PowerShell as Administrator
3. Run:
   ```powershell
   choco install -y cmake visualstudio2022buildtools python312 git
   ```
4. Install Rust from [rustup.rs](https://rustup.rs/)

## Building (Windows Native)

The project currently uses CMake which should work on Windows with MSVC, but may need adjustments. The build system was primarily designed for Linux/Unix.

### Expected Challenges

1. **CMake configuration** - May need Windows-specific paths
2. **Unix sockets** - Not available on Windows (skip those tests)
3. **Rust integration** - Corrosion should work but may need tweaks
4. **Python venv** - Use `python -m venv` instead of `python3`

### Build Steps (To Be Validated)

```powershell
# Create Python venv
python -m venv .venv
.venv\Scripts\activate
python -m pip install --upgrade pip
python -m pip install build

# Build with CMake
cmake -S . -B build_release -DCMAKE_BUILD_TYPE=Release
cmake --build build_release --config Release
```

**Note**: The build process may require modifications for Windows. We'll document issues as we encounter them.

## Running Targeted Benchmark

Once built (if possible on Windows), the targeted benchmark can be adapted to PowerShell or run via Git Bash:

```bash
chmod +x targeted-benchmark.sh
./targeted-benchmark.sh
```

## Expected Results

### Hypothesis 1: Windows Native ≈ WSL2
If Windows shows similar overhead, the issue is likely:
- Network stack inefficiency
- Windows TCP/IP overhead
- OS-level virtualization/abstraction

### Hypothesis 2: Windows Native performs differently
If Windows performs significantly better or worse, this indicates:
- WSL2's virtualization layer impact
- WSL2's network translation (vEthernet) overhead
- Platform-specific I/O characteristics

## Comparison Table Template

After testing, fill in:

| Environment | Small Payload (300k req) | Large Payload (50k req) | Notes |
|---|---:|---:|---|
| Linux Bare Metal (documented) | 2.67-2.75s | 5.95-9.35s | From repo docs (no hardware specs) |
| WSL2 (this machine) | TBD | TBD | To measure |
| Windows Native (this machine) | TBD | TBD | To measure |

## Alternative: Linux Bare Metal Test

If Windows native proves too difficult to build, consider:
- Dual-boot Linux on this machine
- Run from a Linux live USB
- Use a bare-metal Linux VM (not WSL2)

## Reporting Results

After testing, update:
1. `BENCHMARK_REPORT.md` with Windows results
2. Issue #3 with findings
3. This file with any build issues/solutions encountered

## Questions to Answer

1. Can the project build on Windows with MSVC?
2. If yes, what's the performance vs WSL2?
3. If no, what needs to be fixed?
4. Is WSL2's overhead acceptable for development?
