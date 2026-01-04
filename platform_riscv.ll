; =============================================================================
; Platform: RISC-V Bare-metal (QEMU virt)
; =============================================================================

@heap_ptr = global i32 2147549184  ; 0x80010000

define void @putchar(i8 %c) nounwind {
  %uart = inttoptr i32 268435456 to ptr  ; 0x10000000
  store volatile i8 %c, ptr %uart
  ret void
}

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

define ptr @malloc(i32 %size) {
  %ptr_addr = load i32, ptr @heap_ptr
  %aligned = add i32 %size, 7
  %aligned2 = and i32 %aligned, -8
  %new_ptr = add i32 %ptr_addr, %aligned2
  store i32 %new_ptr, ptr @heap_ptr
  %result = inttoptr i32 %ptr_addr to ptr
  ret ptr %result
}

define void @exit_qemu(i32 %code) nounwind {
  %test = inttoptr i32 1048576 to ptr  ; 0x100000
  %val = or i32 %code, 21845           ; 0x5555
  store volatile i32 %val, ptr %test
  ret void
}

; Entry point for RISC-V
define void @_start() naked noreturn nounwind section ".text._start" {
  call void asm sideeffect "la sp, _stack_top\0Acall run_test\0Acall exit_qemu\0A1: j 1b", ""()
  unreachable
}

declare void @run_test()
