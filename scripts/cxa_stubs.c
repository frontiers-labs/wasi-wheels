// Stubs for the Itanium C++ exception ABI symbols that wasi-sdk's libc++abi
// does not implement for wasm32-wasip2. Anything that actually throws will
// trap. This is acceptable for the packages here: their C++ throws only on
// argument/state errors that normal Python-level use does not reach
// (contourpy/kiwisolver layout edge cases, pandas window OOM).

#include <stdio.h>
#include <stdlib.h>

void *__cxa_allocate_exception(unsigned long thrown_size) {
    (void)thrown_size;
    fprintf(stderr, "wasi-wheels: C++ exception thrown; aborting (unsupported on wasi).\n");
    abort();
}

void __cxa_throw(void *thrown_exception, void *tinfo, void (*dest)(void *)) {
    (void)thrown_exception;
    (void)tinfo;
    (void)dest;
    fprintf(stderr, "wasi-wheels: __cxa_throw called; aborting (unsupported on wasi).\n");
    abort();
}

void __cxa_free_exception(void *thrown_exception) {
    (void)thrown_exception;
}
