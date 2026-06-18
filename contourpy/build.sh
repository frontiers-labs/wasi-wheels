#!/bin/bash
#
# Cross-compile contourpy (C++/pybind11) for wasm32-wasip2. No external libs.
# pybind11/numpy.h is self-contained, so no numpy headers are needed at build.

set -eou pipefail

HERE=$(cd "$(dirname "$0")" && pwd)
REPO=$(cd "${HERE}/.." && pwd)
. "${REPO}/scripts/wasi-pybuild.sh"

CONTOURPY_VERSION=1.3.3
CONTOURPY_SHA256=083e12155b210502d0bca491432bb04d56dc3432f95a979b429f2848c3dbe880
CONTOURPY_URL="https://files.pythonhosted.org/packages/source/c/contourpy/contourpy-${CONTOURPY_VERSION}.tar.gz"

fetch_sdist "${CONTOURPY_URL}" "${HERE}/src"

if [ ! -e "${HERE}/venv" ]; then
  python3.14 -m venv "${HERE}/venv"
fi
. "${HERE}/venv/bin/activate"
pip install --upgrade pip
pip install "meson-python>=0.13.1" "meson>=1.2.0,<2" ninja "pybind11>=2.13.2,!=2.13.3" wheel

cd "${HERE}/src"
CROSS_FILE="$(pwd)/build.meson.cross"
write_cross_file "${CROSS_FILE}"

rm -rf build wheels
mkdir -p wheels
pip wheel . -w wheels -v --no-build-isolation --no-deps \
  -Csetup-args="--cross-file=${CROSS_FILE}" \
  -Csetup-args="-Dbuildtype=release"

unpack_wheel wheels
