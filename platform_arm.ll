; =============================================================================
; Platform: ARM Cortex-M3 (QEMU lm3s6965evb)
; Memory layout: SRAM 64KB (0x20000000 - 0x2000FFFF)
;   - .data/.bss: 0x20000000 - 0x20000FFF (4KB reserved)
;   - heap: 0x20001000 - grows UP
;   - stack: 0x20010000 - grows DOWN
; =============================================================================

@heap_ptr = global i32 536875008  ; 0x20001000 - after .data/.bss

define void @print(ptr %str) nounwind {
  call void asm sideeffect "mov r1, $0\0Amov r0, #0x04\0Abkpt #0xAB", "r,~{r0},~{r1}"(ptr %str)
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
  %args = alloca [2 x i32]
  store i32 %code, ptr %args
  call void asm sideeffect "mov r1, $0\0Amov r0, #0x18\0Abkpt #0xAB", "r,~{r0},~{r1}"(ptr %args)
  ret void
}

; Entry point for ARM - with proper .data/.bss initialization
define void @Reset_Handler() naked noreturn nounwind section ".text.Reset_Handler" {
  call void asm sideeffect "
    .syntax unified
    ldr sp, =0x20010000

    /* Copy .data from flash to RAM */
    ldr r0, =_sdata
    ldr r1, =_edata
    ldr r2, =_sidata
1:  cmp r0, r1
    bge 2f
    ldr r3, [r2], #4
    str r3, [r0], #4
    b 1b
2:
    /* Zero .bss */
    ldr r0, =_sbss
    ldr r1, =_ebss
    mov r2, #0
3:  cmp r0, r1
    bge 4f
    str r2, [r0], #4
    b 3b
4:
    bl run_test
    mov r0, #0
    bl exit_qemu
5:  b 5b
  ", ""()
  unreachable
}

; Vector table
@vectors = constant [2 x ptr] [
  ptr inttoptr (i32 536936448 to ptr),  ; SP = 0x20010000 (top of 64KB SRAM)
  ptr @Reset_Handler
], section ".vectors", align 256

declare void @run_test()
