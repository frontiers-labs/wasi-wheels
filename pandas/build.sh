#!/bin/bash
#
# Cross-compile pandas for wasm32-wasip2 against the wasi numpy build.
#
# pandas' meson build resolves numpy headers via numpy.get_include() in the
# build interpreter. We install a matching host numpy and overlay the wasm
# target's _numpyconfig.h (wasm32 is ILP32, so the size macros differ) so the
# Cython extensions are compiled with the correct ABI.

set -eou pipefail

HERE=$(cd "$(dirname "$0")" && pwd)
REPO=$(cd "${HERE}/.." && pwd)
. "${REPO}/scripts/wasi-pybuild.sh"

PANDAS_VERSION=2.3.3
NUMPY_VERSION=2.4.4
PANDAS_URL="https://files.pythonhosted.org/packages/source/p/pandas/pandas-${PANDAS_VERSION}.tar.gz"

NUMPY_TARGET_INC="${REPO}/numpy/src/build/lib.wasi-wasm32-${PY_VER}/numpy/_core/include/numpy"
if [ ! -e "${NUMPY_TARGET_INC}/_numpyconfig.h" ]; then
  echo "cross-built numpy headers not found at ${NUMPY_TARGET_INC}; build numpy first" >&2
  exit 1
fi

fetch_sdist "${PANDAS_URL}" "${HERE}/src"

# eryx's wasi CPython lacks _ctypes (libffi) and mmap (no mmap syscall), which
# pandas hard-imports at module load in several files on the `import pandas`
# path (errors, the dataframe-interchange module, io.common, ...). All uses are
# inside functions (Windows error text, interchange buffers, memory-mapped
# reads), so guard every top-level import across the non-test tree. The mmap
# stub keeps isinstance() checks working.
python3 - "${HERE}/src" <<'PY'
import pathlib, re, sys
root = pathlib.Path(sys.argv[1]) / "pandas"

ctypes_guard = (
    "try:\n    import ctypes\n"
    "except ImportError:  # no _ctypes on wasi\n    ctypes = None"
)
mmap_guard = (
    "try:\n    import mmap\n"
    "except ImportError:  # no mmap on wasi\n"
    "    import types as _t\n"
    "    class _UnavailableMmap:  # placeholder for isinstance checks\n"
    "        pass\n"
    "    mmap = _t.SimpleNamespace(mmap=_UnavailableMmap, ACCESS_READ=0)"
)

for f in root.rglob("*.py"):
    if "tests" in f.parts:
        continue
    s = orig = f.read_text()
    if "no _ctypes on wasi" not in s:
        s = re.sub(r"(?m)^import ctypes$", ctypes_guard, s)
    if "no mmap on wasi" not in s:
        s = re.sub(r"(?m)^import mmap$", mmap_guard, s)
    if s != orig:
        f.write_text(s)
PY

if [ ! -e "${HERE}/venv" ]; then
  python3.14 -m venv "${HERE}/venv"
fi
. "${HERE}/venv/bin/activate"
pip install --upgrade pip
pip install "meson-python>=0.16.0" "meson>=1.3.0,<2" "Cython>=3.0.6,<4" ninja wheel \
  "versioneer[toml]" "numpy==${NUMPY_VERSION}"

HOST_NP_INC=$(python -c "import numpy; print(numpy.get_include())")
cp -f "${NUMPY_TARGET_INC}/_numpyconfig.h" "${HOST_NP_INC}/numpy/"
cp -f "${NUMPY_TARGET_INC}/numpyconfig.h" "${HOST_NP_INC}/numpy/" 2>/dev/null || true

# Catch implicit declarations: on wasm they silently produce wrong ABI.
export CFLAGS="${CFLAGS} -Werror=implicit-function-declaration -Oz"

enable_cross_python

cd "${HERE}/src"
CROSS_FILE="$(pwd)/build.meson.cross"
write_cross_file "${CROSS_FILE}"

rm -rf build wheels
mkdir -p wheels
pip wheel . -w wheels -v --no-build-isolation --no-deps \
  -Csetup-args="--cross-file=${CROSS_FILE}" \
  -Csetup-args="-Dbuildtype=release"

unpack_wheel wheels
