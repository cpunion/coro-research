# =============================================================================
# LLVM Coroutine Async/Await Demo - Multi-Platform Test Suite
#
# Structure:
#   coro_async.ll      - Platform-independent coroutine logic
#   platform_xxx.ll    - Platform-specific code (print, malloc, entry point)
# =============================================================================

OPT := opt
LLC := llc
CLANG := clang
LLD := ld.lld
WASM_LD := wasm-ld
LLVM_LINK := llvm-link

CORO_PASSES := -passes='coro-early,coro-split,coro-cleanup'
BUILD := build

.PHONY: all clean host wasm riscv arm test help

all: host wasm riscv arm

$(BUILD):
	@mkdir -p $(BUILD)

# =============================================================================
# Common: Link core + platform, then run coro passes
# =============================================================================
$(BUILD)/%_merged.ll: coro_async.ll platform_%.ll | $(BUILD)
	$(LLVM_LINK) $^ -S -o $@

$(BUILD)/%_lowered.ll: $(BUILD)/%_merged.ll
	$(OPT) $(CORO_PASSES) $< -S -o $@

# =============================================================================
# HOST (Native)
# =============================================================================
host: $(BUILD)/host_test
	@echo "========================================"
	@echo "HOST (Native)"
	@echo "========================================"
	@./$(BUILD)/host_test

$(BUILD)/host_test: $(BUILD)/host_lowered.ll
	$(CLANG) $< -o $@

# =============================================================================
# WebAssembly (WASI)
# Note: Uses -O0 to prevent optimizer from breaking coroutine suspend paths
# =============================================================================
wasm: $(BUILD)/wasm_test.wasm
	@echo "========================================"
	@echo "WebAssembly (wasmtime)"
	@echo "========================================"
	@wasmtime $(BUILD)/wasm_test.wasm || true
	@echo ""

$(BUILD)/wasm_test.wasm: $(BUILD)/wasm_lowered.ll
	$(LLC) -O0 -mtriple=wasm32-unknown-wasip1 -filetype=obj $< -o $(BUILD)/wasm_test.o
	$(WASM_LD) --no-entry --export=_start $(BUILD)/wasm_test.o -o $@

# =============================================================================
# RISC-V (QEMU virt)
# Note: Uses -O0 to prevent optimizer from breaking coroutine suspend paths
# =============================================================================
riscv: $(BUILD)/riscv_test.elf
	@echo "========================================"
	@echo "RISC-V (QEMU virt)"
	@echo "========================================"
	@timeout 5 qemu-system-riscv32 -M virt -nographic -bios none -kernel $< 2>/dev/null || true

$(BUILD)/riscv_test.elf: $(BUILD)/riscv_lowered.ll riscv/link.ld
	$(LLC) -O0 -mtriple=riscv32-unknown-elf -mattr=+m -filetype=obj $< -o $(BUILD)/riscv_test.o
	$(LLD) -T riscv/link.ld $(BUILD)/riscv_test.o -o $@

# =============================================================================
# ARM Cortex-M3 (QEMU lm3s6965evb)
# Note: Uses -O0 to prevent optimizer from breaking coroutine suspend paths
# =============================================================================
arm: $(BUILD)/arm_test.elf
	@echo "========================================"
	@echo "ARM Cortex-M3 (QEMU lm3s6965evb)"
	@echo "========================================"
	@timeout 5 qemu-system-arm -M lm3s6965evb -nographic -semihosting -kernel $< 2>/dev/null || true

$(BUILD)/arm_test.elf: $(BUILD)/arm_lowered.ll arm/link.ld
	$(LLC) -O0 -mtriple=thumbv7m-none-eabi -mcpu=cortex-m3 -filetype=obj $< -o $(BUILD)/arm_test.o
	$(LLD) -T arm/link.ld $(BUILD)/arm_test.o -o $@

# =============================================================================
# Test all platforms
# =============================================================================
test: host wasm riscv arm
	@echo "========================================"
	@echo "All tests completed!"
	@echo "========================================"

clean:
	rm -rf $(BUILD)

help:
	@echo "LLVM Coroutine Demo - Targets:"
	@echo "  all     - Build host, wasm, riscv"
	@echo "  host    - Native platform"
	@echo "  wasm    - WebAssembly (WASI)"
	@echo "  riscv   - RISC-V bare-metal"
	@echo "  arm     - ARM Cortex-M3 (experimental)"
	@echo "  test    - Run all tests"
	@echo "  clean   - Remove build/"
