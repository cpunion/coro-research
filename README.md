# LLVM Coroutine Multi-Platform Demo

测试 LLVM coroutine intrinsics 在多个平台上的异步机制支持。

## 测试结果

| 平台 | 状态 | 运行方式 | 备注 |
|------|------|----------|------|
| **Host (Native)** | ✅ 通过 | 直接运行 | clang 正确处理协程 |
| **RISC-V RV32** | ✅ 通过 | QEMU virt | 需要 -O0 防止优化破坏 suspend |
| **ARM Cortex-M3** | ✅ 通过 | QEMU lm3s6965evb | 需要 -O0 + 正确的 .data/.bss 初始化 |
| **WebAssembly** | ⚠️ 已知问题 | wasmtime | 多 suspend 点时有 bug |

### ARM Cortex-M3 修复说明

ARM Cortex-M3 需要以下修复才能正常工作：

1. **内存布局**: 堆和栈必须分开
   - 栈: 从 SRAM 顶部 (0x20010000) 向下增长
   - 堆: 从 0x20001000 向上增长
   - 预留 4KB (0x20000000-0x20000FFF) 给 .data/.bss

2. **启动代码初始化**: Reset_Handler 必须初始化 .data 和 .bss
   - 复制 .data 从 Flash 到 RAM
   - 将 .bss 清零

3. **编译优化**: 使用 -O0 防止优化器破坏协程 suspend 路径
   - LLVM 协程 pass 生成的 suspend 路径含 `unreachable`
   - 优化器可能错误地移除 suspend 后的返回指令

### WebAssembly 已知问题

WebAssembly 在多 suspend 点场景有问题：
- 第一个 suspend 点后继续执行而不是返回
- 可能是 WASM 后端对 `unreachable` 指令的处理方式不同

## 文件结构

```
demo/
├── coro_async.ll       # 平台无关的协程核心逻辑
├── platform_host.ll    # Host 平台特定代码
├── platform_wasm.ll    # WebAssembly 平台特定代码
├── platform_riscv.ll   # RISC-V 平台特定代码
├── platform_arm.ll     # ARM 平台特定代码
├── Makefile            # 构建和测试
├── riscv/link.ld       # RISC-V 链接脚本
└── arm/link.ld         # ARM 链接脚本
```

## 快速开始

```bash
# 运行所有测试
make test

# 单独测试某平台
make host
make wasm
make riscv
make arm

# 清理构建产物
make clean
```

## 依赖

- LLVM 工具链 (opt, llc, clang, llvm-link, ld.lld, wasm-ld)
- wasmtime (WebAssembly 测试)
- QEMU (RISC-V 和 ARM 测试)

## 测试内容

演示了完整的异步机制：

1. **协程创建** - 创建多个协程
2. **事件注册** - 协程注册等待事件
3. **挂起** - 协程在事件点挂起
4. **事件触发** - 模拟事件循环触发事件
5. **恢复执行** - 协程被恢复继续执行
6. **多协程交替** - 两个协程交替执行

## 预期输出

```
========================================
[Main] Creating coroutines...
[Coro1] Starting task 1
[Coro1] Waiting for event 1...
[Coro2] Starting task 2
[Coro2] Waiting for event 3...
========================================
[Main] Triggering event 1
[Coro1] Resumed after event 1
[Coro1] Waiting for event 2...
========================================
[Main] Triggering event 3
[Coro2] Resumed after event 3
[Coro2] Task 2 done
========================================
[Main] Triggering event 2
[Coro1] Resumed after event 2
[Coro1] Task 1 done
========================================
[Main] All coroutines done!
>>> TEST PASSED <<<
```

## 架构说明

### 平台无关代码 (coro_async.ll)

- LLVM coroutine intrinsics 声明
- 事件队列模拟 (`register_event`, `trigger_event`)
- 协程函数 (`coro_task1`, `coro_task2`)
- 测试运行器 (`run_test`)

### 平台特定代码 (platform_xxx.ll)

每个平台只需实现：

| 函数 | 用途 |
|------|------|
| `@print(ptr)` | 输出字符串 |
| `@malloc(i32)` | 内存分配 |
| `@exit_qemu(i32)` | 退出（嵌入式平台）|
| 入口点 | `main` / `_start` / `Reset_Handler` |

### 编译流程

```
coro_async.ll + platform_xxx.ll
        ↓ llvm-link
    merged.ll
        ↓ opt (coro passes)
    lowered.ll
        ↓ llc + ld
    executable
```
