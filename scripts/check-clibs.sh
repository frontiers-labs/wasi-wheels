#!/bin/bash
#
# Pre-commit guard: cross-compile the lxml C libraries (libxml2, libxslt) for
# wasm32-wasip2 with wasi-sdk.
#
# This is the slice of the build that does NOT need the CPython cross-build, and
# it is where toolchain/clib regressions surface (wasi-libc gaps like the
# missing dup(), find_package re-rooting, SjLj stubs). Run by the pre-commit
# hook whenever a clib build input changes; also runnable by hand.
#
# Scope: defaults to the libs the `make all` CI path builds (libxml2 + libxslt,
# via lxml). The pillow/matplotlib clibs (zlib/libjpeg/libpng/freetype) live in
# a separate release workflow and are not built here; override with CLIBS=... to
# include them. Note libpng currently does not cross-build under nosjlj.h (it
# takes the address of longjmp, which the trapping macro cannot rewrite) — a
# pre-existing issue tracked outside this guard.

set -euo pipefail

HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
REPO=$(cd "${HERE}/.." && pwd)
cd "${REPO}"

export WASI_SDK_PATH="${REPO}/build/wasi-sdk"
export CLIBS_PREFIX="${REPO}/build/clibs"

# wasi-sdk is large; fetch it once via the Makefile target and cache it under
# build/ (gitignored). Reused on subsequent runs.
if [ ! -x "${WASI_SDK_PATH}/bin/clang" ]; then
  echo "[check-clibs] wasi-sdk not found; fetching via make..."
  make "${WASI_SDK_PATH}"
fi

# build-clibs.sh short-circuits a lib once its archive is installed. Drop the
# installed archives + cmake configs to force a real recompile/re-link (what
# actually catches breakage), while keeping the downloaded source tarballs in
# the work dir so this stays fast on repeat runs.
rm -f "${CLIBS_PREFIX}"/lib/*.a
rm -rf "${CLIBS_PREFIX}"/lib/cmake

echo "[check-clibs] cross-building C libraries for wasm32-wasip2..."
CLIBS="${CLIBS:-libxml2 libxslt}" bash "${REPO}/scripts/build-clibs.sh"

echo "[check-clibs] OK"
