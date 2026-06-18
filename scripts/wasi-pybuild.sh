# Sourced by package build.sh scripts. Sets the wasm32-wasip2 cross toolchain
# for building CPython extension wheels and provides shared helpers.
#
# Requires:
#   WASI_SDK_PATH  path to the wasi-sdk install
#   CROSS_PREFIX   path to the cpython wasi install (libpython + headers)

: "${WASI_SDK_PATH:?WASI_SDK_PATH must be set}"
: "${CROSS_PREFIX:?CROSS_PREFIX must be set}"

WASI_SCRIPTS=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
PY_VER=3.14
ARCH_TRIPLET=_wasi_wasm32-wasi
TARGET=wasm32-wasip2

export CC="${WASI_SDK_PATH}/bin/clang"
export CXX="${WASI_SDK_PATH}/bin/clang++"
export AR="${WASI_SDK_PATH}/bin/ar"
export RANLIB=true
export LDSHARED="${CC}"
# wasi-sdk's clang drives wasm-component-ld for wasip2, which meson's linker
# probe does not recognise; force lld's wasm driver. wasm-ld also rejects
# --start-group, so opt out via the patched meson clike mixin.
export CC_LD=lld
export CXX_LD=lld
export WASI_WHEELS_NO_LINK_GROUPS=1

# Point Python at the cross stdlib + wasm sysconfig. Exported via a function,
# not at source time: doing it before `python -m venv` runs makes host
# ensurepip load the wasm sysconfigdata and fail. Call after venv + host pip
# installs, right before the cross build.
enable_cross_python() {
  export _PYTHON_SYSCONFIGDATA_NAME="_sysconfigdata_${ARCH_TRIPLET}"
  export PYTHONPATH="${CROSS_PREFIX}/lib/python${PY_VER}"
}

# Compile the C++ exception ABI stubs once; link into every extension.
CXA_STUB_OBJ="${WASI_SCRIPTS}/cxa_stubs.o"
"${CC}" --target="${TARGET}" -fPIC -c "${WASI_SCRIPTS}/cxa_stubs.c" -o "${CXA_STUB_OBJ}"

# setjmp/longjmp lowering must match the C libraries (freetype/libjpeg use it).
SJLJ="-mllvm -wasm-enable-sjlj"
export CFLAGS="--target=${TARGET} -fPIC ${SJLJ} -I${CROSS_PREFIX}/include/python${PY_VER} -D__EMSCRIPTEN__=1"
export CXXFLAGS="--target=${TARGET} -fPIC ${SJLJ} -I${CROSS_PREFIX}/include/python${PY_VER}"
export LDFLAGS="--target=${TARGET} -shared ${CROSS_PREFIX}/lib/libpython${PY_VER}.so ${CXA_STUB_OBJ}"

# pkg-config: cpython first; package scripts prepend their C-lib prefix.
export PKG_CONFIG_LIBDIR="${CROSS_PREFIX}/lib/pkgconfig"
export PKG_CONFIG_PATH="${CROSS_PREFIX}/lib/pkgconfig"

write_cross_file() {
  cat > "$1" <<EOF
[binaries]
pkgconfig = 'pkg-config'

[properties]
needs_exe_wrapper = true
skip_sanity_check = true
longdouble_format = 'IEEE_QUAD_LE'

[host_machine]
system = 'wasi'
cpu_family = 'wasm32'
cpu = 'wasm32'
endian = 'little'
EOF
}

fetch_sdist() {
  # $1 = url, $2 = destination dir (flattened: strips the top-level dir)
  local url=$1 dest=$2 tmp
  tmp=$(mktemp -d)
  curl -fSL -o "${tmp}/src.tar.gz" "${url}"
  rm -rf "${dest}"
  mkdir -p "${dest}"
  tar -C "${dest}" --strip-components=1 -xf "${tmp}/src.tar.gz"
  rm -rf "${tmp}"
}

unpack_wheel() {
  # $1 = directory containing exactly one built wheel
  local wheel dest
  wheel=$(ls "$1"/*.whl | head -1)
  dest="build/lib.wasi-wasm32-${PY_VER}"
  rm -rf "${dest}"
  mkdir -p "${dest}"
  unzip -q -o "${wheel}" -d "${dest}"
  echo "${wheel}"
}
