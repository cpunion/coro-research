; =============================================================================
; Platform: Host (Native - macOS/Linux)
; =============================================================================

declare i32 @printf(ptr, ...)
declare ptr @aligned_alloc(i64, i64)

define void @print(ptr %str) {
  call i32 (ptr, ...) @printf(ptr %str)
  ret void
}

define ptr @malloc(i32 %size) {
  %size64 = zext i32 %size to i64
  %ptr = call ptr @aligned_alloc(i64 8, i64 %size64)
  ret ptr %ptr
}

define void @exit_qemu(i32 %code) {
  ret void  ; No-op on host
}

; Entry point for host
define i32 @main() {
  call void @run_test()
  ret i32 0
}

declare void @run_test()
