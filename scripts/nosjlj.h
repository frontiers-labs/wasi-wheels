/* Drop-in replacement for <setjmp.h> on wasm32-wasip2.
 *
 * wasi-sdk's <setjmp.h> requires the wasm exception-handling proposal
 * (-mllvm -wasm-enable-sjlj), which makes the resulting .so carry a wasm
 * exception tag (__c_longjmp). eryx's component encoder (wit-component 0.243)
 * cannot link such modules ("failed to extract linking metadata"). So we avoid
 * SjLj/EH altogether: stub setjmp to always "succeed" (return 0) and longjmp to
 * trap. The libraries that use setjmp (libjpeg, freetype, qhull) then only trap
 * on the error paths they would have longjmp'd from (corrupt input, allocation
 * failure) — acceptable, and the same philosophy as cxa_stubs.c for C++.
 *
 * Force-included via -include; defining _SETJMP_H first makes the real
 * <setjmp.h> a no-op (so its #error never fires).
 */
#ifndef WASI_NOSJLJ_H
#define WASI_NOSJLJ_H
#define _SETJMP_H
typedef struct { unsigned long __opaque[32]; } jmp_buf[1];
typedef jmp_buf sigjmp_buf;
#define setjmp(env) (0)
#define _setjmp(env) (0)
#define sigsetjmp(env, savemask) (0)
#define longjmp(env, val) __builtin_trap()
#define _longjmp(env, val) __builtin_trap()
#define siglongjmp(env, val) __builtin_trap()
#endif
