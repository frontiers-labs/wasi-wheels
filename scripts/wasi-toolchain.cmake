# CMake toolchain for cross-compiling C libraries to wasm32-wasip2 with
# wasi-sdk. Targets the same triple as the CPython build so the static
# archives link cleanly into the Python extension shared objects.
#
# Requires WASI_SDK_PATH in the environment.

set(CMAKE_SYSTEM_NAME WASI)
set(CMAKE_SYSTEM_VERSION 1)
set(CMAKE_SYSTEM_PROCESSOR wasm32)

set(_wasi_sdk "$ENV{WASI_SDK_PATH}")
if(_wasi_sdk STREQUAL "")
  message(FATAL_ERROR "WASI_SDK_PATH is not set")
endif()

set(_triple wasm32-wasip2)

set(CMAKE_C_COMPILER "${_wasi_sdk}/bin/clang")
set(CMAKE_CXX_COMPILER "${_wasi_sdk}/bin/clang++")
set(CMAKE_C_COMPILER_TARGET ${_triple})
set(CMAKE_CXX_COMPILER_TARGET ${_triple})
set(CMAKE_ASM_COMPILER_TARGET ${_triple})

set(CMAKE_SYSROOT "${_wasi_sdk}/share/wasi-sysroot")
set(CMAKE_AR "${_wasi_sdk}/bin/llvm-ar")
set(CMAKE_RANLIB "${_wasi_sdk}/bin/llvm-ranlib")
set(CMAKE_NM "${_wasi_sdk}/bin/llvm-nm")

# -fPIC: every archive is linked into a shared (.so) Python extension.
# wasm-enable-sjlj: freetype's rasterizer and libjpeg's error handling use
# setjmp/longjmp, which wasi-sdk lowers via the wasm exception-handling proposal.
set(_wasi_cflags "-fPIC -O2 -mllvm -wasm-enable-sjlj")
set(CMAKE_C_FLAGS_INIT "${_wasi_cflags}")
set(CMAKE_CXX_FLAGS_INIT "${_wasi_cflags}")

set(CMAKE_FIND_ROOT_PATH_MODE_PROGRAM NEVER)
set(CMAKE_FIND_ROOT_PATH_MODE_LIBRARY ONLY)
set(CMAKE_FIND_ROOT_PATH_MODE_INCLUDE ONLY)
set(CMAKE_FIND_ROOT_PATH_MODE_PACKAGE ONLY)
