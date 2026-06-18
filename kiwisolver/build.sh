#!/bin/bash
#
# Cross-compile kiwisolver (C++/cppy) for wasm32-wasip2. No external libs.

set -eou pipefail

HERE=$(cd "$(dirname "$0")" && pwd)
REPO=$(cd "${HERE}/.." && pwd)
. "${REPO}/scripts/wasi-pybuild.sh"

KIWISOLVER_VERSION=1.5.0
KIWISOLVER_SHA256=d4193f3d9dc3f6f79aaed0e5637f45d98850ebf01f7ca20e69457f3e8946b66a
KIWISOLVER_URL="https://files.pythonhosted.org/packages/source/k/kiwisolver/kiwisolver-${KIWISOLVER_VERSION}.tar.gz"

fetch_sdist "${KIWISOLVER_URL}" "${HERE}/src"

if [ ! -e "${HERE}/venv" ]; then
  python3.14 -m venv "${HERE}/venv"
fi
. "${HERE}/venv/bin/activate"
pip install --upgrade pip setuptools wheel "cppy>=1.3.0" setuptools_scm

export SETUPTOOLS_SCM_PRETEND_VERSION="${KIWISOLVER_VERSION}"

enable_cross_python

cd "${HERE}/src"
rm -rf build wheels
mkdir -p wheels
pip wheel . -w wheels -v --no-build-isolation --no-deps

unpack_wheel wheels
