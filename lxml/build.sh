#!/bin/bash
#
# Cross-compile lxml for wasm32-wasip2 against static libxml2 + libxslt.
#
# lxml is a setuptools/Cython extension that links libxml2, libxslt and
# libexslt. We cross-build those C libraries first (scripts/build-clibs.sh) and
# point lxml at them via the installed xml2-config / xslt-config scripts. The
# sdist ships pre-generated Cython C, so no Cython is needed at build time
# (--without-cython); the build interpreter only needs setuptools.

set -eou pipefail

HERE=$(cd "$(dirname "$0")" && pwd)
REPO=$(cd "${HERE}/.." && pwd)

LXML_VERSION=6.0.0
LXML_URL="https://files.pythonhosted.org/packages/source/l/lxml/lxml-${LXML_VERSION}.tar.gz"

# Build the C libraries first, with a clean environment: the Python-extension
# CFLAGS/LDFLAGS (-shared, libpython) must not leak into their CMake builds.
export CLIBS_PREFIX="${REPO}/build/clibs"
CLIBS="libxml2 libxslt" bash "${REPO}/scripts/build-clibs.sh"

. "${REPO}/scripts/wasi-pybuild.sh"

export PKG_CONFIG_PATH="${CLIBS_PREFIX}/lib/pkgconfig:${PKG_CONFIG_PATH}"
export PKG_CONFIG_LIBDIR="${CLIBS_PREFIX}/lib/pkgconfig:${PKG_CONFIG_LIBDIR}"
export CFLAGS="${CFLAGS} -I${CLIBS_PREFIX}/include"
export LDFLAGS="${LDFLAGS} -L${CLIBS_PREFIX}/lib"

fetch_sdist "${LXML_URL}" "${HERE}/src"

if [ ! -e "${HERE}/venv" ]; then
  python3.14 -m venv "${HERE}/venv"
fi
. "${HERE}/venv/bin/activate"
pip install --upgrade pip setuptools wheel

enable_cross_python

cd "${HERE}/src"
rm -rf build

# lxml reads its libxml2/libxslt link flags from these config scripts (installed
# by the CMake clib builds into the shared prefix). The extension itself is
# compiled with the wasi clang set up by wasi-pybuild.sh.
python3 setup.py build -j 4 \
  --without-cython \
  --with-xml2-config="${CLIBS_PREFIX}/bin/xml2-config" \
  --with-xslt-config="${CLIBS_PREFIX}/bin/xslt-config"
