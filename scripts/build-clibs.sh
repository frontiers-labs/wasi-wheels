#!/bin/bash
#
# Cross-compile the C libraries that Pillow and matplotlib link against
# (zlib, libjpeg-turbo, libpng, freetype) for wasm32-wasip2 and install them
# as static archives + pkg-config files into a shared prefix.
#
# Inputs (environment):
#   WASI_SDK_PATH  path to the wasi-sdk install
#   CLIBS_PREFIX   install prefix (default: <repo>/build/clibs)
#   CLIBS          space-separated subset to build (default: all)
#
# The prefix it populates is consumed via PKG_CONFIG_LIBDIR and *_ROOT vars.

set -eou pipefail

HERE=$(cd "$(dirname "$0")" && pwd)
REPO=$(cd "${HERE}/.." && pwd)
PREFIX=${CLIBS_PREFIX:-${REPO}/build/clibs}
WORK=${PREFIX}/work
TOOLCHAIN=${HERE}/wasi-toolchain.cmake
CLIBS=${CLIBS:-zlib libjpeg libpng freetype}

if [ -z "${WASI_SDK_PATH:-}" ]; then
  echo "WASI_SDK_PATH must be set" >&2
  exit 1
fi

mkdir -p "${PREFIX}" "${WORK}"

ZLIB_VERSION=1.3.1
ZLIB_SHA256=9a93b2b7dfdac77ceba5a558a580e74667dd6fede4585b91eefb60f03b72df23
LIBJPEG_VERSION=3.1.2
LIBPNG_VERSION=1.6.58
FREETYPE_VERSION=2.13.3

fetch() {
  local url=$1 out=$2 sha=$3
  if [ ! -e "${out}" ]; then
    curl -fSL -o "${out}.tmp" "${url}"
    mv "${out}.tmp" "${out}"
  fi
  if [ -n "${sha}" ]; then
    echo "${sha}  ${out}" | sha256sum -c -
  fi
}

cmake_build() {
  local src=$1
  shift
  rm -rf "${src}/build-wasi"
  cmake -S "${src}" -B "${src}/build-wasi" -G "Unix Makefiles" \
    -DCMAKE_TOOLCHAIN_FILE="${TOOLCHAIN}" \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_INSTALL_PREFIX="${PREFIX}" \
    -DCMAKE_PREFIX_PATH="${PREFIX}" \
    -DBUILD_SHARED_LIBS=OFF \
    "$@"
  cmake --build "${src}/build-wasi" -j"$(nproc)"
  cmake --install "${src}/build-wasi"
}

build_zlib() {
  [ -e "${PREFIX}/lib/libz.a" ] && return 0
  local t="${WORK}/zlib-${ZLIB_VERSION}.tar.gz"
  fetch "https://github.com/madler/zlib/releases/download/v${ZLIB_VERSION}/zlib-${ZLIB_VERSION}.tar.gz" "${t}" "${ZLIB_SHA256}"
  tar -C "${WORK}" -xf "${t}"
  cmake_build "${WORK}/zlib-${ZLIB_VERSION}" -DZLIB_BUILD_EXAMPLES=OFF
  # Drop shared libs; force static linking only.
  rm -f "${PREFIX}"/lib/libz.so* "${PREFIX}"/lib/libzlib.so* 2>/dev/null || true
  # zlib's CMake only renames the static lib to libz.a on UNIX; for the WASI
  # system name it stays libzlibstatic.a, which `-lz` won't find.
  if [ ! -e "${PREFIX}/lib/libz.a" ] && [ -e "${PREFIX}/lib/libzlibstatic.a" ]; then
    cp -f "${PREFIX}/lib/libzlibstatic.a" "${PREFIX}/lib/libz.a"
  fi
}

build_libjpeg() {
  [ -e "${PREFIX}/lib/libjpeg.a" ] && return 0
  local t="${WORK}/libjpeg-turbo-${LIBJPEG_VERSION}.tar.gz"
  fetch "https://github.com/libjpeg-turbo/libjpeg-turbo/releases/download/${LIBJPEG_VERSION}/libjpeg-turbo-${LIBJPEG_VERSION}.tar.gz" "${t}" ""
  tar -C "${WORK}" -xf "${t}"
  local src="${WORK}/libjpeg-turbo-${LIBJPEG_VERSION}"
  mkdir -p "${PREFIX}/lib" "${PREFIX}/include"
  rm -rf "${src}/build-wasi"
  cmake -S "${src}" -B "${src}/build-wasi" -G "Unix Makefiles" \
    -DCMAKE_TOOLCHAIN_FILE="${TOOLCHAIN}" \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_INSTALL_PREFIX="${PREFIX}" \
    -DENABLE_SHARED=OFF -DENABLE_STATIC=ON \
    -DWITH_SIMD=OFF -DWITH_TURBOJPEG=OFF
  # Build only the static library. The bundled cjpeg/djpeg/example executables
  # link full programs that need the wasm SjLj runtime symbol (__c_longjmp) and
  # fail; we only need libjpeg.a + its headers, which Pillow finds via JPEG_ROOT.
  cmake --build "${src}/build-wasi" --target jpeg-static -j"$(nproc)"
  cp -f "${src}/build-wasi/libjpeg.a" "${PREFIX}/lib/"
  cp -f "${src}/build-wasi/jconfig.h" "${PREFIX}/include/"
  cp -f "${src}/src/jpeglib.h" "${src}/src/jmorecfg.h" "${src}/src/jerror.h" "${PREFIX}/include/"
}

build_libpng() {
  [ -e "${PREFIX}/lib/libpng16.a" ] && return 0
  local t="${WORK}/libpng-${LIBPNG_VERSION}.tar.gz"
  fetch "https://download.sourceforge.net/libpng/libpng-${LIBPNG_VERSION}.tar.gz" "${t}" ""
  tar -C "${WORK}" -xf "${t}"
  cmake_build "${WORK}/libpng-${LIBPNG_VERSION}" \
    -DZLIB_ROOT="${PREFIX}" \
    -DPNG_SHARED=OFF -DPNG_STATIC=ON \
    -DPNG_TESTS=OFF -DPNG_TOOLS=OFF -DPNG_FRAMEWORK=OFF \
    -DPNG_ARM_NEON=off -DPNG_INTEL_SSE=off
}

build_freetype() {
  [ -e "${PREFIX}/lib/libfreetype.a" ] && return 0
  local t="${WORK}/freetype-${FREETYPE_VERSION}.tar.gz"
  fetch "https://download.savannah.gnu.org/releases/freetype/freetype-${FREETYPE_VERSION}.tar.gz" "${t}" ""
  tar -C "${WORK}" -xf "${t}"
  # Self-contained freetype: no harfbuzz/png/zlib/brotli/bzip2. Enough for
  # ft2font glyph rasterisation, which is all matplotlib and Pillow need.
  cmake_build "${WORK}/freetype-${FREETYPE_VERSION}" \
    -DFT_DISABLE_HARFBUZZ=ON -DFT_DISABLE_BROTLI=ON \
    -DFT_DISABLE_BZIP2=ON -DFT_DISABLE_PNG=ON -DFT_DISABLE_ZLIB=ON
}

for lib in ${CLIBS}; do
  case "${lib}" in
    zlib) build_zlib ;;
    libjpeg) build_libjpeg ;;
    libpng) build_libpng ;;
    freetype) build_freetype ;;
    *) echo "unknown clib: ${lib}" >&2; exit 1 ;;
  esac
done

echo "C libraries installed into ${PREFIX}"
ls -la "${PREFIX}/lib" || true
