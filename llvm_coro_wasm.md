# LLVM Coroutine WebAssembly 支持

本文档记录 LLVM coroutine intrinsics 在 WebAssembly 平台上的支持情况和使用方法。

## 结论

**LLVM coroutine 完全支持编译到 WebAssembly**，经过测试可以在 wasmtime 和 iwasm 运行时正常运行。

## 测试环境

- LLVM 版本: 19.1.7
- 目标平台: wasm32-unknown-wasip1
- 运行时: wasmtime, iwasm (WAMR)

## 最小示例

以下是一个完整的 LLVM IR 示例，展示了无栈协程在 WebAssembly 上的实现：

```llvm
; coro_wasm_minimal.ll
; Minimal LLVM Coroutine for WebAssembly - no libc dependency
target datalayout = "e-m:e-p:32:32-p10:8:8-p20:8:8-i64:64-n32:64-S128-ni:1:10:20"
target triple = "wasm32-unknown-wasip1"

; WASI fd_write: (fd, iovs, iovs_len, nwritten) -> errno
declare i32 @fd_write(i32, ptr, i32, ptr) #0

attributes #0 = { "wasm-import-module"="wasi_snapshot_preview1" "wasm-import-name"="fd_write" }

; Simple memory allocator - just bump pointer
@heap_ptr = global i32 65536  ; Start heap at 64KB

define ptr @simple_alloc(i32 %size) {
  %ptr_addr = load i32, ptr @heap_ptr
  %new_ptr = add i32 %ptr_addr, %size
  store i32 %new_ptr, ptr @heap_ptr
  %result = inttoptr i32 %ptr_addr to ptr
  ret ptr %result
}

; LLVM Coroutine Intrinsics
declare token @llvm.coro.id(i32, ptr, ptr, ptr)
declare i32 @llvm.coro.size.i32()
declare ptr @llvm.coro.begin(token, ptr)
declare i8 @llvm.coro.suspend(token, i1)
declare i1 @llvm.coro.end(ptr, i1, token)
declare ptr @llvm.coro.free(token, ptr)
declare void @llvm.coro.resume(ptr)
declare void @llvm.coro.destroy(ptr)
declare token @llvm.coro.save(ptr)

; String constants
@.str1 = private constant [16 x i8] c"coro: starting\0A\00"
@.str2 = private constant [18 x i8] c"coro: suspending\0A\00"
@.str3 = private constant [15 x i8] c"coro: resumed\0A\00"
@.str4 = private constant [14 x i8] c"coro: ending\0A\00"
@.str5 = private constant [15 x i8] c"main: created\0A\00"
@.str6 = private constant [16 x i8] c"main: resuming\0A\00"
@.str7 = private constant [12 x i8] c"main: done\0A\00"

; iovec structure for fd_write
%struct.iovec = type { ptr, i32 }

; Print helper using WASI fd_write
define void @print(ptr %str, i32 %len) {
entry:
  %iov = alloca %struct.iovec
  %nwritten = alloca i32
  %buf_ptr = getelementptr %struct.iovec, ptr %iov, i32 0, i32 0
  store ptr %str, ptr %buf_ptr
  %len_ptr = getelementptr %struct.iovec, ptr %iov, i32 0, i32 1
  store i32 %len, ptr %len_ptr
  call i32 @fd_write(i32 1, ptr %iov, i32 1, ptr %nwritten)
  ret void
}

; Simple coroutine with one suspend point
define ptr @my_coro() presplitcoroutine {
entry:
  %id = call token @llvm.coro.id(i32 0, ptr null, ptr null, ptr null)
  %size = call i32 @llvm.coro.size.i32()
  %alloc = call ptr @simple_alloc(i32 %size)
  %hdl = call ptr @llvm.coro.begin(token %id, ptr %alloc)

  call void @print(ptr @.str1, i32 15)
  call void @print(ptr @.str2, i32 17)

  %save = call token @llvm.coro.save(ptr %hdl)
  %s = call i8 @llvm.coro.suspend(token %save, i1 false)
  switch i8 %s, label %suspend [
    i8 0, label %resume
    i8 1, label %cleanup
  ]

resume:
  call void @print(ptr @.str3, i32 14)
  call void @print(ptr @.str4, i32 13)
  br label %cleanup

cleanup:
  br label %done

done:
  %unused = call i1 @llvm.coro.end(ptr %hdl, i1 false, token none)
  ret ptr %hdl

suspend:
  ret ptr %hdl
}

; Entry point - exported as _start for WASI
define void @_start() {
entry:
  %hdl = call ptr @my_coro()
  call void @print(ptr @.str5, i32 14)

  call void @print(ptr @.str6, i32 15)
  call void @llvm.coro.resume(ptr %hdl)

  call void @print(ptr @.str7, i32 11)
  ret void
}
```

## 编译步骤

### 1. 运行 Coroutine Passes

LLVM coroutine 需要通过特定的 passes 来降低（lower）协程 intrinsics：

```bash
opt -passes='coro-early,coro-split,coro-cleanup' coro_wasm_minimal.ll -S -o coro_wasm_minimal_lowered.ll
```

这些 passes 的作用：
- `coro-early`: 早期协程处理，准备协程框架
- `coro-split`: 将协程函数拆分为多个部分（ramp, resume, destroy, cleanup）
- `coro-cleanup`: 清理协程相关的临时结构

### 2. 编译到 WebAssembly 对象文件

```bash
llc -mtriple=wasm32-unknown-wasip1 -filetype=obj coro_wasm_minimal_lowered.ll -o coro_wasm_minimal.o
```

### 3. 链接生成 WASM 二进制

```bash
wasm-ld --no-entry --export=_start coro_wasm_minimal.o -o coro_wasm_minimal.wasm
```

参数说明：
- `--no-entry`: 不使用默认的 `_start` 入口点查找逻辑
- `--export=_start`: 导出 `_start` 函数作为入口点

### 一键编译脚本

```bash
#!/bin/bash
set -e

INPUT=$1
OUTPUT=${INPUT%.ll}.wasm
LOWERED=${INPUT%.ll}_lowered.ll
OBJ=${INPUT%.ll}.o

echo "=== Compiling $INPUT to WebAssembly ==="

echo "Step 1: Running coroutine passes..."
opt -passes='coro-early,coro-split,coro-cleanup' "$INPUT" -S -o "$LOWERED"

echo "Step 2: Compiling to object file..."
llc -mtriple=wasm32-unknown-wasip1 -filetype=obj "$LOWERED" -o "$OBJ"

echo "Step 3: Linking..."
wasm-ld --no-entry --export=_start "$OBJ" -o "$OUTPUT"

echo "=== Done: $OUTPUT ==="
```

## 运行 WebAssembly

### 使用 wasmtime

```bash
wasmtime coro_wasm_minimal.wasm
```

### 使用 iwasm (WAMR)

```bash
iwasm coro_wasm_minimal.wasm
```

### 预期输出

```
coro: starting
coro: suspending
main: created
main: resuming
coro: resumed
coro: ending
main: done
```

输出说明：
1. `coro: starting` - 协程开始执行
2. `coro: suspending` - 协程准备暂停
3. `main: created` - main 函数收到协程句柄，协程已暂停
4. `main: resuming` - main 准备恢复协程
5. `coro: resumed` - 协程从暂停点恢复执行
6. `coro: ending` - 协程执行完毕
7. `main: done` - main 函数结束

## 协程降低后的结构

运行 coroutine passes 后，原始的 `my_coro` 函数会被拆分为：

| 函数 | 作用 |
|------|------|
| `my_coro` | Ramp 函数，创建协程帧并运行到第一个 suspend 点 |
| `my_coro.resume` | Resume 函数，从 suspend 点恢复执行 |
| `my_coro.destroy` | Destroy 函数，销毁协程并释放资源 |
| `my_coro.cleanup` | Cleanup 函数，处理协程取消时的清理 |

协程帧（Coroutine Frame）结构：
```llvm
%my_coro.Frame = type { ptr, ptr, i1 }
;                       ^    ^    ^
;                       |    |    +-- 当前状态索引
;                       |    +------- destroy 函数指针
;                       +------------ resume 函数指针
```

## WASI 导入配置

在 LLVM IR 中，使用属性来指定 WASI 导入：

```llvm
declare i32 @fd_write(i32, ptr, i32, ptr) #0

attributes #0 = {
  "wasm-import-module"="wasi_snapshot_preview1"
  "wasm-import-name"="fd_write"
}
```

这会生成正确的 WebAssembly 导入：
```
Import[1]:
 - func[0] sig=1 <fd_write> <- wasi_snapshot_preview1.fd_write
```

## 注意事项

1. **内存管理**: WebAssembly 使用线性内存，需要自己实现或链接内存分配器
2. **栈分配**: `alloca` 在 WASM 中会使用影子栈（shadow stack）
3. **函数指针**: LLVM coroutine 使用函数指针表（table）实现 resume/destroy 调度
4. **32位指针**: 使用 `llvm.coro.size.i32()` 而非 `llvm.coro.size.i64()`

## 与 Native 编译的区别

| 方面 | Native (x86_64/arm64) | WebAssembly |
|------|----------------------|-------------|
| 指针大小 | 64-bit | 32-bit |
| coro.size | `llvm.coro.size.i64()` | `llvm.coro.size.i32()` |
| malloc 参数 | i64 | i32 |
| 标准库 | libc (printf) | WASI (fd_write) |
| 入口点 | main | _start |

## 参考文件

示例文件保存在 `examples/` 目录：
- `examples/coro_simple.ll` - Native 版本（arm64/x86_64）
- `examples/coro_wasm_minimal.ll` - WebAssembly 版本源码
