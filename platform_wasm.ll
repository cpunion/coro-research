; =============================================================================
; Platform: WebAssembly (WASI)
; =============================================================================

; WASI fd_write
declare i32 @fd_write(i32, ptr, i32, ptr) #0
attributes #0 = { "wasm-import-module"="wasi_snapshot_preview1" "wasm-import-name"="fd_write" }

%struct.iovec = type { ptr, i32 }

@heap_ptr = global i32 65536

; Print null-terminated string
define void @print(ptr %str) {
entry:
  ; Calculate string length
  br label %len_loop
len_loop:
  %i = phi i32 [ 0, %entry ], [ %i_next, %len_loop ]
  %p = getelementptr i8, ptr %str, i32 %i
  %c = load i8, ptr %p
  %done = icmp eq i8 %c, 0
  %i_next = add i32 %i, 1
  br i1 %done, label %do_write, label %len_loop

do_write:
  %len = phi i32 [ %i, %len_loop ]
  %iov = alloca %struct.iovec
  %nwritten = alloca i32
  store ptr %str, ptr %iov
  %len_ptr = getelementptr %struct.iovec, ptr %iov, i32 0, i32 1
  store i32 %len, ptr %len_ptr
  call i32 @fd_write(i32 1, ptr %iov, i32 1, ptr %nwritten)
  ret void
}

define ptr @malloc(i32 %size) {
  %ptr_addr = load i32, ptr @heap_ptr
  %aligned = add i32 %size, 7
  %aligned2 = and i32 %aligned, -8
  %new_ptr = add i32 %ptr_addr, %aligned2
  store i32 %new_ptr, ptr @heap_ptr
  %result = inttoptr i32 %ptr_addr to ptr
  ret ptr %result
}

define void @exit_qemu(i32 %code) {
  ret void
}

; Entry point for WASM
define void @_start() {
  call void @run_test()
  ret void
}

declare void @run_test()
