#!/bin/bash
#
# Cross-compile Pillow for wasm32-wasip2 with zlib, libjpeg-turbo and freetype.
# Pillow's PNG codec uses zlib directly (no libpng); only jpeg + zlib are
# required, freetype adds text rendering.

set -eou pipefail

HERE=$(cd "$(dirname "$0")" && pwd)
REPO=$(cd "${HERE}/.." && pwd)

PILLOW_VERSION=12.2.0
PILLOW_SHA256=a830b1a40919539d07806aa58e1b114df53ddd43213d9c8b75847eee6c0182b5
PILLOW_URL="https://files.pythonhosted.org/packages/source/p/pillow/pillow-${PILLOW_VERSION}.tar.gz"

# Build the C libraries first, with a clean environment: the Python-extension
# CFLAGS/LDFLAGS (-shared, libpython) must not leak into their CMake builds.
export CLIBS_PREFIX="${REPO}/build/clibs"
CLIBS="zlib libjpeg freetype" bash "${REPO}/scripts/build-clibs.sh"

. "${REPO}/scripts/wasi-pybuild.sh"

export PKG_CONFIG_PATH="${CLIBS_PREFIX}/lib/pkgconfig:${CLIBS_PREFIX}/share/pkgconfig:${PKG_CONFIG_PATH}"
export PKG_CONFIG_LIBDIR="${CLIBS_PREFIX}/lib/pkgconfig:${CLIBS_PREFIX}/share/pkgconfig:${PKG_CONFIG_LIBDIR}"
export ZLIB_ROOT="${CLIBS_PREFIX}"
export JPEG_ROOT="${CLIBS_PREFIX}"
export FREETYPE_ROOT="${CLIBS_PREFIX}"
export CFLAGS="${CFLAGS} -I${CLIBS_PREFIX}/include"
export LDFLAGS="${LDFLAGS} -L${CLIBS_PREFIX}/lib"

fetch_sdist "${PILLOW_URL}" "${HERE}/src"

# setup.py adjustments:
#  - drop the Tkinter extension (dlopen()s Tk; no dlopen on wasi, useless headless)
#  - whole-archive libsetjmp into only the setjmp-using extensions (_imaging via
#    libjpeg, _imagingft via freetype). __c_longjmp is a weak EH tag that a plain
#    -lsetjmp won't pull; forcing it into the other extensions (e.g. _imagingmath)
#    would leave a dangling tag eryx can't parse.
python3 - "${HERE}/src" "${SJLJ_LIB}" <<'PY'
import pathlib, sys
p = pathlib.Path(sys.argv[1]) / "setup.py"
sjlj = sys.argv[2]
ela = '[%r, %r, %r]' % ("-Wl,--whole-archive", sjlj, "-Wl,--no-whole-archive")
s = p.read_text()
s = s.replace(
    'self._update_extension("PIL._imagingtk", tk_libs)',
    'self._remove_extension("PIL._imagingtk")',
    1,
)
s = s.replace(
    'Extension("PIL._imaging", files)',
    'Extension("PIL._imaging", files, extra_link_args=%s)' % ela,
    1,
)
s = s.replace(
    'Extension("PIL._imagingft", ["src/_imagingft.c"])',
    'Extension("PIL._imagingft", ["src/_imagingft.c"], extra_link_args=%s)' % ela,
    1,
)
p.write_text(s)
PY

if [ ! -e "${HERE}/venv" ]; then
  python3.14 -m venv "${HERE}/venv"
fi
. "${HERE}/venv/bin/activate"
pip install --upgrade pip setuptools wheel "pybind11>=2.13.2"

enable_cross_python

cd "${HERE}/src"
rm -rf build wheels
mkdir -p wheels
pip wheel . -w wheels -v --no-build-isolation --no-deps \
  -C platform-guessing=disable \
  -C zlib=enable -C jpeg=enable -C freetype=enable \
  -C tiff=disable -C webp=disable -C lcms=disable -C xcb=disable \
  -C jpeg2000=disable -C imagequant=disable -C avif=disable -C raqm=disable

unpack_wheel wheels
