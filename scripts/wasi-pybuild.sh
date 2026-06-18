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
#
# meson and setuptools both add the host interpreter's include dir (derived
# from the install scheme, which sysconfigdata cannot override) ahead of our
# cross include, so a wasm build would compile against the 64-bit pyconfig.h
# and fail (LONG_BIT / immortal-refcount shift). Overlay the cross CPython
# headers onto the host include dir so whichever path wins is wasm-correct.
# Query the host paths before exporting the wasm sysconfig name.
enable_cross_python() {
  local d
  for d in "$(python3 -c 'import sysconfig; print(sysconfig.get_path("platinclude"))')" \
           "$(python3 -c 'import sysconfig; print(sysconfig.get_path("include"))')"; do
    if [ -n "${d}" ] && [ -d "${d}" ]; then
      cp -rf "${CROSS_PREFIX}/include/python${PY_VER}/." "${d}/"
    fi
  done
  export _PYTHON_SYSCONFIGDATA_NAME="_sysconfigdata_${ARCH_TRIPLET}"
  export PYTHONPATH="${CROSS_PREFIX}/lib/python${PY_VER}"
  patch_meson_no_groups
}

# wasm-ld rejects --start-group/--end-group, which the stock pip meson wraps
# around link archives. numpy uses a patched vendored meson; for the pip meson
# in our build venvs, disable the group insertion directly. No-op when meson is
# not installed (setuptools-only packages).
patch_meson_no_groups() {
  local f
  f="$(python3 -c 'import mesonbuild.compilers.mixins.clike as m; print(m.__file__)' 2>/dev/null || true)"
  [ -n "${f}" ] && [ -f "${f}" ] || return 0
  python3 - "${f}" <<'PY'
import sys, pathlib
p = pathlib.Path(sys.argv[1])
s = p.read_text()
needle = "if group_end > group_start >= 0:"
if needle in s and "wasi: wasm-ld lacks --start-group" not in s:
    s = s.replace(
        needle,
        "if False and group_end > group_start >= 0:  # wasi: wasm-ld lacks --start-group",
        1,
    )
    p.write_text(s)
PY
}

# Compile the C++ exception ABI stubs once; link into every extension.
CXA_STUB_OBJ="${WASI_SCRIPTS}/cxa_stubs.o"
"${CC}" --target="${TARGET}" -fPIC -c "${WASI_SCRIPTS}/cxa_stubs.c" -o "${CXA_STUB_OBJ}"

# setjmp/longjmp lowering must match the C libraries (freetype/libjpeg use it).
SJLJ="-mllvm -wasm-enable-sjlj"
# The wasm SjLj runtime (__c_longjmp, __wasm_setjmp/longjmp) lives in wasi-sdk's
# libsetjmp.a. Packages that use setjmp link it with --whole-archive (below);
# plain -lsetjmp resolves too late under setuptools, which puts LDFLAGS before
# the object files.
export SJLJ_LIB="${WASI_SDK_PATH}/share/wasi-sysroot/lib/${TARGET}/libsetjmp.a"
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
