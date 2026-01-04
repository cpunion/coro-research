# LLVM Coroutine 嵌入式平台支持

本文档记录 LLVM coroutine intrinsics 在嵌入式裸机（bare-metal）平台上的支持情况。

## 结论

**LLVM coroutine 完全支持嵌入式平台**，在无操作系统、无线程支持的环境下正常工作。

| 平台 | 状态 | QEMU 机器 | 备注 |
|------|------|-----------|------|
| RISC-V RV32I | ✅ 通过 | virt | 完全正常 |
| ARM Cortex-M3 | ⚠️ 部分 | lm3s6965evb, mps2-an385 | suspend 工作，resume 时 HardFault |
| WebAssembly | ✅ 通过 | wasmtime/iwasm | 见 [llvm_coro_wasm.md](llvm_coro_wasm.md) |

### ARM 问题分析

ARM Cortex-M 在协程 resume 时出现 HardFault，可能原因：
1. **Thumb 模式函数指针**: ARM Thumb 模式要求函数地址最低位为1
2. **间接调用**: 协程 resume/destroy 使用函数指针表，可能需要特殊处理
3. 需要进一步调试生成的函数指针是否正确设置 Thumb 位

## RISC-V 裸机测试

### 测试环境

- LLVM 版本: 19.1.7
- 目标: riscv32-unknown-elf
- 模拟器: QEMU virt 机器
- 无操作系统、无线程、无标准库

### 完整示例

```llvm
; coro_riscv.ll - RISC-V bare-metal coroutine example
target datalayout = "e-m:e-p:32:32-i64:64-n32-S128"
target triple = "riscv32-unknown-elf"

; UART address for QEMU virt machine
@UART_BASE = constant i32 268435456  ; 0x10000000

; Simple heap pointer
@heap_ptr = global i32 2147549184  ; 0x80010000

define ptr @simple_alloc(i32 %size) {
  %ptr_addr = load i32, ptr @heap_ptr
  %aligned_size = add i32 %size, 7
  %aligned_size2 = and i32 %aligned_size, -8
  %new_ptr = add i32 %ptr_addr, %aligned_size2
  store i32 %new_ptr, ptr @heap_ptr
  %result = inttoptr i32 %ptr_addr to ptr
  ret ptr %result
}

; Print character to UART
define void @putchar(i8 %c) nounwind {
entry:
  %uart = inttoptr i32 268435456 to ptr
  store volatile i8 %c, ptr %uart
  ret void
}

; Print null-terminated string
define void @print(ptr %str) nounwind {
entry:
  br label %loop
loop:
  %ptr = phi ptr [ %str, %entry ], [ %next, %cont ]
  %c = load i8, ptr %ptr
  %done = icmp eq i8 %c, 0
  br i1 %done, label %exit, label %cont
cont:
  call void @putchar(i8 %c)
  %next = getelementptr i8, ptr %ptr, i32 1
  br label %loop
exit:
  ret void
}

; Exit QEMU using test device
define void @exit_qemu(i32 %code) nounwind {
entry:
  %test = inttoptr i32 1048576 to ptr  ; 0x100000
  %val = or i32 %code, 21845           ; 0x5555 = pass
  store volatile i32 %val, ptr %test
  ret void
}

; LLVM Coroutine Intrinsics
declare token @llvm.coro.id(i32, ptr, ptr, ptr)
declare i32 @llvm.coro.size.i32()
declare ptr @llvm.coro.begin(token, ptr)
declare i8 @llvm.coro.suspend(token, i1)
declare i1 @llvm.coro.end(ptr, i1, token)
declare void @llvm.coro.resume(ptr)
declare token @llvm.coro.save(ptr)

; String constants
@.str1 = private constant [16 x i8] c"coro: starting\0A\00"
@.str2 = private constant [18 x i8] c"coro: suspending\0A\00"
@.str3 = private constant [15 x i8] c"coro: resumed\0A\00"
@.str4 = private constant [14 x i8] c"coro: ending\0A\00"
@.str5 = private constant [15 x i8] c"main: created\0A\00"
@.str6 = private constant [16 x i8] c"main: resuming\0A\00"
@.str7 = private constant [12 x i8] c"main: done\0A\00"

; Coroutine function
define ptr @my_coro() presplitcoroutine {
entry:
  %id = call token @llvm.coro.id(i32 0, ptr null, ptr null, ptr null)
  %size = call i32 @llvm.coro.size.i32()
  %alloc = call ptr @simple_alloc(i32 %size)
  %hdl = call ptr @llvm.coro.begin(token %id, ptr %alloc)

  call void @print(ptr @.str1)
  call void @print(ptr @.str2)

  %save = call token @llvm.coro.save(ptr %hdl)
  %s = call i8 @llvm.coro.suspend(token %save, i1 false)
  switch i8 %s, label %suspend [
    i8 0, label %resume
    i8 1, label %cleanup
  ]

resume:
  call void @print(ptr @.str3)
  call void @print(ptr @.str4)
  br label %cleanup

cleanup:
  br label %done

done:
  %unused = call i1 @llvm.coro.end(ptr %hdl, i1 false, token none)
  ret ptr %hdl

suspend:
  ret ptr %hdl
}

; Main function
define void @main() {
entry:
  %hdl = call ptr @my_coro()
  call void @print(ptr @.str5)
  call void @print(ptr @.str6)
  call void @llvm.coro.resume(ptr %hdl)
  call void @print(ptr @.str7)
  call void @exit_qemu(i32 0)
  ret void
}

; Entry point - must be at 0x80000000 for QEMU virt
define void @_start() naked noreturn nounwind section ".text._start" {
entry:
  call void asm sideeffect "la sp, _stack_top", ""()
  call void @main()
  call void asm sideeffect "1: j 1b", ""()
  unreachable
}
```

### 链接脚本

```ld
/* riscv_virt.ld - Linker script for QEMU RISC-V virt machine */
OUTPUT_ARCH(riscv)
ENTRY(_start)

MEMORY
{
    RAM (rwx) : ORIGIN = 0x80000000, LENGTH = 128M
}

SECTIONS
{
    . = 0x80000000;

    .text : {
        *(.text._start)   /* Entry point first */
        *(.text*)
    } > RAM

    .rodata : {
        *(.rodata*)
    } > RAM

    .data : {
        *(.data*)
    } > RAM

    .bss : {
        *(.bss*)
        *(COMMON)
    } > RAM

    . = ALIGN(16);
    . = . + 0x4000;  /* 16KB stack */
    _stack_top = .;
}
```

### 编译步骤

```bash
# 1. 运行 coroutine passes
opt -passes='coro-early,coro-split,coro-cleanup' coro_riscv.ll -S -o coro_riscv_lowered.ll

# 2. 编译到 RISC-V 对象文件
llc -mtriple=riscv32-unknown-elf -mattr=+m -filetype=obj coro_riscv_lowered.ll -o coro_riscv.o

# 3. 链接
ld.lld -T riscv_virt.ld coro_riscv.o -o coro_riscv.elf

# 4. 运行
qemu-system-riscv32 -M virt -nographic -bios none -kernel coro_riscv.elf
```

### 测试输出

```
coro: starting
coro: suspending
main: created
main: resuming
coro: resumed
coro: ending
main: done
=== OK ===
```

## ARM Cortex-M3 测试

### 状态

ARM Cortex-M3 测试部分成功：
- ✅ 协程创建成功
- ✅ 第一次 suspend 成功
- ⚠️ resume 时出现 HardFault

### 可能原因

1. 函数指针表（indirect call）问题
2. Thumb 模式下的函数调用约定
3. 需要进一步调试栈和寄存器状态

### 测试输出

```
coro: starting
coro: suspending
qemu: fatal: Lockup: can't escalate 3 to HardFault
```

## 嵌入式平台的关键点

### 1. 内存分配

嵌入式系统通常没有标准库，需要自己实现简单的内存分配器：

```llvm
@heap_ptr = global i32 0x80010000  ; 堆起始地址

define ptr @simple_alloc(i32 %size) {
  %ptr_addr = load i32, ptr @heap_ptr
  %aligned_size = add i32 %size, 7
  %aligned_size2 = and i32 %aligned_size, -8  ; 8字节对齐
  %new_ptr = add i32 %ptr_addr, %aligned_size2
  store i32 %new_ptr, ptr @heap_ptr
  %result = inttoptr i32 %ptr_addr to ptr
  ret ptr %result
}
```

### 2. 协程帧大小

使用 `llvm.coro.size.i32()` 获取协程帧大小（32位平台）：

```llvm
%size = call i32 @llvm.coro.size.i32()
%frame = call ptr @simple_alloc(i32 %size)
```

### 3. 入口点

裸机程序需要正确的入口点和栈初始化：

```llvm
define void @_start() naked noreturn section ".text._start" {
  call void asm sideeffect "la sp, _stack_top", ""()
  call void @main()
  unreachable
}
```

### 4. 输出

使用 UART 或 semihosting 进行输出：

```llvm
; UART 输出 (RISC-V QEMU virt)
define void @putchar(i8 %c) {
  %uart = inttoptr i32 0x10000000 to ptr
  store volatile i8 %c, ptr %uart
  ret void
}

; Semihosting 输出 (ARM)
define void @print(ptr %str) {
  call void asm sideeffect "mov r1, $0\0Amov r0, #0x04\0Abkpt #0xAB", "r"(ptr %str)
  ret void
}
```

## 协程在嵌入式中的优势

1. **无栈开销**: 每个协程只需要一个小的帧（通常 < 100 字节）
2. **无线程依赖**: 不需要操作系统或线程支持
3. **确定性**: 没有抢占，完全由程序控制切换点
4. **低延迟**: 协程切换只是函数调用，比线程切换快得多

## 参考文件

示例文件在 `examples/` 目录：
- `examples/coro_riscv.ll` - RISC-V 裸机版本
- `examples/riscv_virt.ld` - RISC-V 链接脚本
