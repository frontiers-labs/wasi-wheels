/* dup() stub for wasm32-wasip2.
 *
 * wasi-libc does not provide dup() (no preview1 syscall maps to it), so
 * unistd.h never declares it and clang 20 rejects the implicit declaration as
 * a hard error. libxml2's xmlIO.c (xmlOutputDefaultOpen) calls dup(STDOUT_FILENO)
 * only on the "-" / stdout output path; lxml serialises to memory and never
 * exercises it, so a failing stub is enough to compile and link cleanly.
 *
 * Force-included via -include alongside nosjlj.h in the clib toolchain.
 */
#ifndef WASI_DUP_H
#define WASI_DUP_H
#include <errno.h>
static inline int dup(int oldfd) {
    (void) oldfd;
    errno = ENOSYS;
    return -1;
}
#endif
