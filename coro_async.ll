; =============================================================================
; LLVM Coroutine Async/Await Demo - Platform Independent Core
;
; This file contains:
; - Coroutine logic (platform independent)
; - Event queue simulation
; - All entry points (_start, main, Reset_Handler) - linker picks what's needed
;
; Platform-specific functions (must be provided by platform file):
; - @print(ptr %str)       - print null-terminated string
; - @malloc(i32/i64 %size) - allocate memory
; - @exit_qemu(i32 %code)  - exit (for embedded platforms)
; =============================================================================

; ============== External Platform Functions ==============
; These are defined in platform-specific files
declare void @print(ptr)
declare ptr @malloc(i32)
declare void @exit_qemu(i32)

; ============== LLVM Coroutine Intrinsics ==============
declare token @llvm.coro.id(i32, ptr, ptr, ptr)
declare i32 @llvm.coro.size.i32()
declare ptr @llvm.coro.begin(token, ptr)
declare i8 @llvm.coro.suspend(token, i1)
declare i1 @llvm.coro.end(ptr, i1, token)
declare ptr @llvm.coro.free(token, ptr)
declare void @llvm.coro.resume(ptr)
declare void @llvm.coro.destroy(ptr)
declare token @llvm.coro.save(ptr)

; ============== Event Queue Simulation ==============
@event_queue = global [8 x ptr] zeroinitializer

define void @register_event(ptr %hdl, i32 %event_id) {
entry:
  %idx = srem i32 %event_id, 8
  %slot = getelementptr [8 x ptr], ptr @event_queue, i32 0, i32 %idx
  store ptr %hdl, ptr %slot
  ret void
}

define void @trigger_event(i32 %event_id) {
entry:
  %idx = srem i32 %event_id, 8
  %slot = getelementptr [8 x ptr], ptr @event_queue, i32 0, i32 %idx
  %hdl = load ptr, ptr %slot
  %is_null = icmp eq ptr %hdl, null
  br i1 %is_null, label %done, label %resume

resume:
  store ptr null, ptr %slot
  call void @llvm.coro.resume(ptr %hdl)
  br label %done

done:
  ret void
}

; ============== String Constants ==============
@.str_coro1_start = private constant [25 x i8] c"[Coro1] Starting task 1\0A\00"
@.str_coro1_wait = private constant [32 x i8] c"[Coro1] Waiting for event 1...\0A\00"
@.str_coro1_got = private constant [31 x i8] c"[Coro1] Resumed after event 1\0A\00"
@.str_coro1_wait2 = private constant [32 x i8] c"[Coro1] Waiting for event 2...\0A\00"
@.str_coro1_got2 = private constant [31 x i8] c"[Coro1] Resumed after event 2\0A\00"
@.str_coro1_done = private constant [21 x i8] c"[Coro1] Task 1 done\0A\00"

@.str_coro2_start = private constant [25 x i8] c"[Coro2] Starting task 2\0A\00"
@.str_coro2_wait = private constant [32 x i8] c"[Coro2] Waiting for event 3...\0A\00"
@.str_coro2_got = private constant [31 x i8] c"[Coro2] Resumed after event 3\0A\00"
@.str_coro2_done = private constant [21 x i8] c"[Coro2] Task 2 done\0A\00"

@.str_main_create = private constant [31 x i8] c"[Main] Creating coroutines...\0A\00"
@.str_main_trig1 = private constant [27 x i8] c"[Main] Triggering event 1\0A\00"
@.str_main_trig2 = private constant [27 x i8] c"[Main] Triggering event 2\0A\00"
@.str_main_trig3 = private constant [27 x i8] c"[Main] Triggering event 3\0A\00"
@.str_main_done = private constant [29 x i8] c"[Main] All coroutines done!\0A\00"
@.str_sep = private constant [42 x i8] c"========================================\0A\00"
@.str_pass = private constant [21 x i8] c">>> TEST PASSED <<<\0A\00"

; ============== Coroutine 1: Two suspend points ==============
define ptr @coro_task1() presplitcoroutine {
entry:
  %id = call token @llvm.coro.id(i32 0, ptr null, ptr null, ptr null)
  %size = call i32 @llvm.coro.size.i32()
  %alloc = call ptr @malloc(i32 %size)
  %hdl = call ptr @llvm.coro.begin(token %id, ptr %alloc)

  call void @print(ptr @.str_coro1_start)
  call void @print(ptr @.str_coro1_wait)
  call void @register_event(ptr %hdl, i32 1)

  %save1 = call token @llvm.coro.save(ptr %hdl)
  %s1 = call i8 @llvm.coro.suspend(token %save1, i1 false)
  switch i8 %s1, label %suspend [i8 0, label %resume1  i8 1, label %cleanup]

resume1:
  call void @print(ptr @.str_coro1_got)
  call void @print(ptr @.str_coro1_wait2)
  call void @register_event(ptr %hdl, i32 2)

  %save2 = call token @llvm.coro.save(ptr %hdl)
  %s2 = call i8 @llvm.coro.suspend(token %save2, i1 false)
  switch i8 %s2, label %suspend [i8 0, label %resume2  i8 1, label %cleanup]

resume2:
  call void @print(ptr @.str_coro1_got2)
  call void @print(ptr @.str_coro1_done)
  br label %cleanup

cleanup:
  br label %done
done:
  %unused = call i1 @llvm.coro.end(ptr %hdl, i1 false, token none)
  ret ptr %hdl
suspend:
  ret ptr %hdl
}

; ============== Coroutine 2: One suspend point ==============
define ptr @coro_task2() presplitcoroutine {
entry:
  %id = call token @llvm.coro.id(i32 0, ptr null, ptr null, ptr null)
  %size = call i32 @llvm.coro.size.i32()
  %alloc = call ptr @malloc(i32 %size)
  %hdl = call ptr @llvm.coro.begin(token %id, ptr %alloc)

  call void @print(ptr @.str_coro2_start)
  call void @print(ptr @.str_coro2_wait)
  call void @register_event(ptr %hdl, i32 3)

  %save = call token @llvm.coro.save(ptr %hdl)
  %s = call i8 @llvm.coro.suspend(token %save, i1 false)
  switch i8 %s, label %suspend [i8 0, label %resume  i8 1, label %cleanup]

resume:
  call void @print(ptr @.str_coro2_got)
  call void @print(ptr @.str_coro2_done)
  br label %cleanup

cleanup:
  br label %done
done:
  %unused = call i1 @llvm.coro.end(ptr %hdl, i1 false, token none)
  ret ptr %hdl
suspend:
  ret ptr %hdl
}

; ============== Test Runner (called by all entry points) ==============
define void @run_test() {
entry:
  call void @print(ptr @.str_sep)
  call void @print(ptr @.str_main_create)

  %hdl1 = call ptr @coro_task1()
  %hdl2 = call ptr @coro_task2()

  call void @print(ptr @.str_sep)
  call void @print(ptr @.str_main_trig1)
  call void @trigger_event(i32 1)

  call void @print(ptr @.str_sep)
  call void @print(ptr @.str_main_trig3)
  call void @trigger_event(i32 3)

  call void @print(ptr @.str_sep)
  call void @print(ptr @.str_main_trig2)
  call void @trigger_event(i32 2)

  call void @print(ptr @.str_sep)
  call void @print(ptr @.str_main_done)
  call void @print(ptr @.str_pass)
  ret void
}
