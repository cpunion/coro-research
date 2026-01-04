# LLVM Coroutine Research

Multi-platform LLVM stackless coroutine demo and research.

## Platforms Tested

| Platform | Status | Notes |
|----------|--------|-------|
| Host (Native) | ✅ Pass | macOS/Linux |
| RISC-V RV32 | ✅ Pass | QEMU virt, requires `-O0` |
| ARM Cortex-M3 | ✅ Pass | QEMU lm3s6965evb, requires `-O0` |
| WebAssembly | ⚠️ Known Bug | Multi-suspend has LLVM bug |
| WebAssembly (br workaround) | ✅ Pass | Fixed with `icmp+br` + `ret` patch |

## Build & Test

```bash
# Prerequisites
# - LLVM 18+ (brew install llvm)
# - wasmtime (for WASM tests)
# - qemu-system-riscv32, qemu-system-arm (for embedded tests)

# Ensure LLVM is in PATH
export PATH="/opt/homebrew/opt/llvm/bin:$PATH"

# Test individual platforms
make host      # Native
make wasm      # WebAssembly (shows known bug)
make wasm-br   # WebAssembly with workaround (correct output)
make riscv     # RISC-V (QEMU)
make arm       # ARM Cortex-M3 (QEMU)

# Test all
make test

# Clean
make clean
```

## File Structure

```
.
├── coro_async.ll         # Platform-independent coroutine logic
├── coro_async_br.ll      # Version using icmp+br (WASM workaround)
├── platform_host.ll      # Native platform support
├── platform_wasm.ll      # WebAssembly/WASI support
├── platform_riscv.ll     # RISC-V bare-metal support
├── platform_arm.ll       # ARM Cortex-M3 bare-metal support
├── riscv/                # RISC-V linker scripts
├── arm/                  # ARM linker scripts
├── llvm_coro_wasm.md     # WebAssembly coroutine documentation
├── llvm_coro_embedded.md # Embedded platform documentation
└── Makefile              # Build system
```

## WASM Multi-Suspend Bug

LLVM's WASM backend has a known bug with multi-suspend point coroutines. The issue is:

1. `coro-split` pass generates `switch` with `suspend: unreachable`
2. WASM `br_table` incorrectly handles default case
3. Resume function doesn't return, falls through to next resume point

**Workaround** (implemented in `wasm-br` target):
1. Use `icmp` + `br` instead of `switch` in source IR
2. Post-process lowered IR: replace `unreachable` with `ret void` in suspend blocks

See the [LLGo Proposal](https://github.com/goplus/llgo/issues/1529) for details.

## License

MIT
