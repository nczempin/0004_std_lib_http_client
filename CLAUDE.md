# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

This is a polyglot HTTP/1.1 client library implementation from first principles, designed to demonstrate high-performance network programming across C, C++, Rust, and Python. The project is both a comprehensive technical guide (the README is 350KB+) and a working implementation with extensive benchmarks comparing performance characteristics across languages.

The library implements a three-layer architecture:
1. **Client API Layer**: User-facing interface (`httpc.h`, `httpcpp.hpp`, `httprust.rs`, `httppy.py`)
2. **Protocol Layer**: HTTP/1.1 implementation (`http1_protocol.*`)
3. **Transport Layer**: TCP and Unix Domain Socket transports (`tcp_transport.*`, `unix_transport.*`)

## Build System

The project uses CMake as the primary build system with language-specific tools integrated:
- **C/C++**: CMake with C23 and C++23 standards
- **Rust**: Integrated via Corrosion (Cargo.toml in `src/rust/`)
- **Python**: Built as a wheel via setuptools (pyproject.toml in `src/python/`)

### Initial Setup
```bash
./setup.sh
```
This creates a Python virtual environment (`.venv/`), builds both Debug and Release configurations.

### Build Commands
```bash
# Rebuild Debug
cmake --build build_debug

# Rebuild Release
cmake --build build_release

# Build specific component
cmake --build build_debug --target httpc_lib
cmake --build build_release --target httpcpp_lib

# Build Rust components
cd src/rust && cargo build --release

# Build Python wheel
cd src/python && python -m build --wheel
```

## Testing

### Running All Tests
```bash
# C/C++ tests (uses GoogleTest)
cd build_debug
ctest --output-on-failure

# Rust tests
cd src/rust
cargo test

# Python tests (uses pytest)
source .venv/bin/activate
cd src/python
python -m pip install --editable .[test]
pytest -sv tests
```

### Running Specific Tests
```bash
# Specific C/C++ test
cd build_debug
./tests/test_tcp_transport

# Specific Rust test
cd src/rust
cargo test tcp_transport

# Specific Python test
cd src/python
pytest tests/test_tcp_transport.py -v
```

### Coverage Reports
```bash
./run-coverage.sh
```
Generates coverage reports for all languages:
- C/C++: `build_debug/coverage_html/index.html`
- Rust: `src/rust/target/llvm-cov/html/index.html`
- Python: `src/python/htmlcov/index.html`

## Benchmarking

The benchmark suite runs comprehensive performance comparisons across:
- All four language implementations
- Both TCP and Unix domain sockets
- Multiple workload patterns (throughput, latency, mixed)
- Different payload sizes and request patterns

### Running Benchmarks
```bash
./run-benchmarks.sh
```

**Important**: Benchmarks are designed for bare metal execution with CPU affinity and performance governors. The script includes commented-out commands for:
- Setting CPU performance governor
- Pinning to specific CPU cores
- Setting realtime priorities

Results are saved to `build_release/hyperfine_results_*.md` and latency files to `build_release/latencies/`.

### Benchmark Configuration
Key parameters in `run-benchmarks.sh`:
- `NUM_REQUESTS_THROUGHPUT=50000`
- `NUM_REQUESTS_LATENCY=300000`
- `NUM_REQUESTS_MIXED=75000`
- `SERVER_CORE=2` and `CLIENT_CORE=3` (modify for your CPU topology)

## Architecture and Code Organization

### Language Implementations

Each language implementation follows the same architectural pattern but with language-idiomatic error handling:

**C** (`src/c/`, `include/httpc/`):
- Manual error inspection via `ErrorType` struct
- Explicit resource management with `_destroy()` functions
- System call abstraction via `HttpcSyscalls` for testability
- No allocations on hot path when using `--unsafe` mode

**C++** (`src/cpp/`, `include/httpcpp/`):
- Exception-based error handling via custom `HttpError` class
- RAII for automatic resource management
- Smart pointers optional but not required for performance paths
- Does NOT use `<experimental/net>`, uses direct C API calls

**Rust** (`src/rust/src/`):
- Result-based error handling with custom `HttpError` enum
- Ownership system prevents resource leaks by construction
- Uses `?` operator for error propagation
- Implements `From<std::io::Error>` for automatic conversion

**Python** (`src/python/httppy/`):
- Exception-based error handling with custom exception hierarchy
- Context managers for resource cleanup
- Can be built as a wheel and installed in virtual environment

### Key Components

**Transport Layer** (`*_transport.*`):
- Abstract interface for network I/O
- Two implementations: TCP and Unix Domain Sockets
- Handles connection establishment, read/write, and cleanup
- C version uses function pointers for polymorphism
- C++/Rust use virtual methods/traits

**Protocol Layer** (`http1_protocol.*`):
- HTTP/1.1 request formatting and response parsing
- Handles status line, headers, and body
- Supports both safe (copying) and unsafe (zero-copy) modes
- Parser is hand-written, no dependencies on external HTTP libraries

**Client API** (`httpc.*`, `httpcpp.*`, etc.):
- High-level API: `GET()` and `POST()` methods
- Takes URL, optional headers, optional body
- Returns response with status, headers, and body
- Manages transport and protocol layer internally

### System Call Abstraction

The C implementation uses a `HttpcSyscalls` struct (`include/httpc/syscalls.h`, `src/c/syscalls.c`) containing function pointers for all system calls. This enables:
- Complete unit testing with mock implementations
- Deterministic testing of error paths
- No need for actual network I/O in tests

Tests use this pattern: `tests/c/test_tcp_transport.cpp` shows mock syscall injection.

### Performance Features

- **Vectored I/O**: C client supports `--io-policy vectored` using `writev()`
- **Zero-copy modes**: All implementations have `--unsafe` modes that avoid copying response bodies
- **Compiler optimizations**: Release builds use `-march=native` for CPU-specific optimizations
- **Link-time optimization**: LTO enabled for Release builds when compiler supports it

## Common Development Workflows

### Adding a New HTTP Method

To add support for a new HTTP method (e.g., DELETE):
1. Add method enum/constant to error types
2. Update protocol layer request formatting (`http1_protocol.*`)
3. Add client API method (`httpc.*`)
4. Add tests to `tests/*/test_http1_protocol.*`
5. Repeat for all four language implementations

### Adding a New Transport

To add a new transport (e.g., TLS):
1. Create new transport implementation following `tcp_transport.*` pattern
2. Implement the `TransportInterface`/`Transport` trait/protocol
3. Update client API to accept new transport type
4. Add tests following existing transport tests
5. Add to benchmark suite

### Analyzing Latencies

Use the included `analyse_latencies.py` script to process benchmark results:
```bash
python analyse_latencies.py latencies/latencies_*.bin
```

## PR Review Triage Process

When receiving PR review feedback, categorize each comment by action type:

### A) Quality Standard Violation → Fix Immediately on Branch
- Bugs, correctness issues
- Missing tests for critical paths
- Poor error handling
- Security issues
- Performance regressions

**Action**: Fix on the current branch, add atomic commits, comment on PR linking to commit(s)

### B) Complex Quality Issue → Create Blocking Ticket First
- Requires architectural changes
- Needs significant refactoring
- Would take >2 hours to fix properly

**Action**: Create new issue, mark original as blocked by it, reference in PR comment, fix in separate PR

### C) Reasonable Feedback to Reject
- Stylistic preferences without clear benefit
- Suggestions that conflict with existing patterns
- Out of scope for this phase

**Action**: Politely explain reasoning in PR comment with justification

### D) Valid Future Work → Create Prioritized Ticket
- Nice-to-have improvements
- Optimizations that aren't critical
- Additional features/edge cases
- Documentation enhancements

**Action**: Create issue with appropriate priority label, reference in PR comment

### Workflow
1. Read all review comments
2. Categorize each comment (A/B/C/D)
3. Fix all (A) items with atomic commits
4. Create blocking issues for (B) items
5. Write polite responses for (C) items
6. Create future tickets for (D) items
7. Push commits and update PR with comments
8. Request re-review if needed

## Important Notes

- **README as Documentation**: The README.md is the comprehensive guide (350KB). It explains design decisions, architecture, and includes inline code references.
- **Code References**: The README uses the format `path/to/file.ext::Symbol` to reference specific code locations.
- **AI-Friendly Design**: The project is explicitly designed to be loaded into LLM context windows. Use `./dump_source_tree.sh > src.txt` to generate a single file for this purpose.
- **Sparse Comments**: Code comments are minimal by design - the README serves as the authoritative documentation.
- **No Black Box Libraries**: The project deliberately avoids using high-level HTTP libraries (no libcurl in main implementations, no requests in Python core, etc.) to demonstrate first-principles implementation.
- **Benchmark Baselines**: Benchmarks include comparisons against libcurl, Boost.Beast, reqwest, and requests to provide performance context.

## Project Philosophy

From the README: "In disciplines where performance is not merely a feature but the core business requirement... the use of 'black box' libraries is a liability." This project demonstrates building HTTP clients from first principles with full control over allocations, system calls, and performance characteristics.

The implementations prioritize:
1. Deterministic performance (no hidden allocations on hot paths)
2. Testability (system call abstraction, dependency injection)
3. Language idioms (different error handling per language)
4. Benchmarkability (comprehensive performance measurement)
