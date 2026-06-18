#!/bin/bash
#
# Cross-compile matplotlib for wasm32-wasip2 (Agg backend only).
#
# Native deps: only freetype (agg and qhull are vendored). The pure-Python and
# compiled run deps (numpy, contourpy, kiwisolver, cycler, fonttools, packaging,
# pyparsing, python-dateutil) are assembled separately for the runtime test.

set -eou pipefail

HERE=$(cd "$(dirname "$0")" && pwd)
REPO=$(cd "${HERE}/.." && pwd)

MATPLOTLIB_VERSION=3.10.8
MATPLOTLIB_SHA256=2299372c19d56bcd35cf05a2738308758d32b9eaed2371898d8f5bd33f084aa3
MATPLOTLIB_URL="https://files.pythonhosted.org/packages/source/m/matplotlib/matplotlib-${MATPLOTLIB_VERSION}.tar.gz"

# Build freetype first, with a clean environment (no leaked extension flags).
export CLIBS_PREFIX="${REPO}/build/clibs"
CLIBS="freetype" bash "${REPO}/scripts/build-clibs.sh"

. "${REPO}/scripts/wasi-pybuild.sh"

export PKG_CONFIG_PATH="${CLIBS_PREFIX}/lib/pkgconfig:${CLIBS_PREFIX}/share/pkgconfig:${PKG_CONFIG_PATH}"
export PKG_CONFIG_LIBDIR="${CLIBS_PREFIX}/lib/pkgconfig:${CLIBS_PREFIX}/share/pkgconfig:${PKG_CONFIG_LIBDIR}"
export CFLAGS="${CFLAGS} -I${CLIBS_PREFIX}/include -D_WASI_EMULATED_PROCESS_CLOCKS"
export CXXFLAGS="${CXXFLAGS} -I${CLIBS_PREFIX}/include -D_WASI_EMULATED_PROCESS_CLOCKS"
# qhull calls clock(); it's a strong symbol so a global lib resolves it (pulled
# only where referenced). libsetjmp is whole-archived per-extension in meson.build
# below (its __c_longjmp is a weak EH tag a plain -l can't pull).
export LDFLAGS="${LDFLAGS} -L${CLIBS_PREFIX}/lib -lwasi-emulated-process-clocks"

fetch_sdist "${MATPLOTLIB_URL}" "${HERE}/src"

# Source adaptations (kept minimal; applied idempotently via python):
#  - neutralise threading.Timer in font_manager (no threads under wasi)
#  - drop the freetype2 pkg-config version constraint so the CMake-built
#    freetype2.pc (release-numbered, not libtool-numbered) is accepted
python3 - "${HERE}/src" "${SJLJ_LIB}" <<'PY'
import re, sys, pathlib
root = pathlib.Path(sys.argv[1])
sjlj = sys.argv[2]

fm = root / "lib" / "matplotlib" / "font_manager.py"
s = fm.read_text()
if "_WasiNoTimer" not in s:
    shim = ("class _WasiNoTimer:\n"
            "    def __init__(self, *a, **k): pass\n"
            "    def start(self): pass\n"
            "    def cancel(self): pass\n\n")
    s = s.replace("import threading\n", "import threading\n" + shim, 1)
    s = s.replace("threading.Timer", "_WasiNoTimer")
    fm.write_text(s)

ext = root / "extern" / "meson.build"
e = ext.read_text()
e2 = re.sub(r"dependency\('freetype2'[^)]*\)", "dependency('freetype2')", e)
if e2 != e:
    ext.write_text(e2)

# wasm32 is ILP32: get_height()/get_width() return unsigned int, which narrows
# to py::ssize_t (long) in the Agg buffer initializer list (-Wc++11-narrowing
# is a hard error). Add explicit casts (matplotlib upstream patch 0004).
agg = root / "src" / "_backend_agg_wrapper.cpp"
a = agg.read_text()
for old, new in (
    ("renderer->get_height(),", "static_cast<py::ssize_t>(renderer->get_height()),"),
    ("renderer->get_width() * 4,", "static_cast<py::ssize_t>(renderer->get_width() * 4),"),
    ("renderer->get_width(),", "static_cast<py::ssize_t>(renderer->get_width()),"),
):
    if new not in a:
        a = a.replace(old, new)
agg.write_text(a)

# Whole-archive libsetjmp into only the freetype-using extensions (_backend_agg,
# ft2font) so freetype's setjmp (__c_longjmp, a weak EH tag) resolves without
# leaving a dangling tag in the others.
mb = root / "src" / "meson.build"
m = mb.read_text()
if "whole-archive" not in m:
    link_args = (
        "    'link_args': ([\'_backend_agg\', \'ft2font\', \'_qhull\'].contains(ext) ? "
        "[\'-Wl,--whole-archive\', \'%s\', \'-Wl,--no-whole-archive\'] : []) "
        "+ kwargs.get(\'link_args\', []),\n" % sjlj
    )
    m = m.replace(
        "  additions = {\n"
        "    'cpp_args': [new_preprocessor] + kwargs.get('cpp_args', []),\n"
        "  }",
        "  additions = {\n"
        "    'cpp_args': [new_preprocessor] + kwargs.get('cpp_args', []),\n"
        + link_args +
        "  }",
        1,
    )
    mb.write_text(m)
PY

if [ ! -e "${HERE}/venv" ]; then
  python3.14 -m venv "${HERE}/venv"
fi
. "${HERE}/venv/bin/activate"
pip install --upgrade pip
pip install "meson-python>=0.13.1" "meson>=1.2.0,<2" ninja "pybind11>=2.13.2" wheel numpy setuptools_scm

# sdist has no git metadata; pin the version for setuptools_scm.
export SETUPTOOLS_SCM_PRETEND_VERSION="${MATPLOTLIB_VERSION}"

enable_cross_python

cd "${HERE}/src"
CROSS_FILE="$(pwd)/build.meson.cross"
write_cross_file "${CROSS_FILE}"

rm -rf build wheels
mkdir -p wheels
pip wheel . -w wheels -v --no-build-isolation --no-deps \
  -Csetup-args="--cross-file=${CROSS_FILE}" \
  -Csetup-args="-Dsystem-freetype=true" \
  -Csetup-args="-Dsystem-qhull=false" \
  -Csetup-args="-DrcParams-backend=Agg" \
  -Csetup-args="-Db_lto=false" \
  -Csetup-args="-Dbuildtype=release"

unpack_wheel wheels
