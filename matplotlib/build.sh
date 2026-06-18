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
# qhull calls clock(); -lwasi-emulated-process-clocks provides it (a strong
# symbol, pulled only where referenced). setjmp in freetype/qhull is neutralised
# by the nosjlj.h force-include, so no libsetjmp handling is needed.
export LDFLAGS="${LDFLAGS} -L${CLIBS_PREFIX}/lib -lwasi-emulated-process-clocks"

fetch_sdist "${MATPLOTLIB_URL}" "${HERE}/src"

# Source adaptations (kept minimal; applied idempotently via python):
#  - neutralise threading.Timer in font_manager (no threads under wasi)
#  - drop the freetype2 pkg-config version constraint so the CMake-built
#    freetype2.pc (release-numbered, not libtool-numbered) is accepted
python3 - "${HERE}/src" <<'PY'
import re, sys, pathlib
root = pathlib.Path(sys.argv[1])

fm = root / "lib" / "matplotlib" / "font_manager.py"
s = fm.read_text()
if "_WasiNoTimer" not in s:
    shim = ("class _WasiNoTimer:\n"
            "    def __init__(self, *a, **k): pass\n"
            "    def start(self): pass\n"
            "    def cancel(self): pass\n\n")
    s = s.replace("import threading\n", "import threading\n" + shim, 1)
    s = s.replace("threading.Timer", "_WasiNoTimer")
# Directory enumeration (os.walk/os.listdir) returns nothing on the eryx VFS,
# so FontManager's font scan finds no fonts even though they are packaged and
# openable. After the scan, register the bundled fonts from a build-time index
# (plain file reads work on the VFS) so text rendering can find DejaVu Sans.
if "_wasi_index.txt" not in s:
    needle = "        finally:\n            timer.cancel()\n"
    addon = (
        "        finally:\n"
        "            timer.cancel()\n"
        "        if not self.ttflist:\n"
        "            try:\n"
        "                _idx = os.path.join(str(mpl.get_data_path()), 'fonts', '_wasi_index.txt')\n"
        "                with open(_idx) as _fh:\n"
        "                    _rels = [_l.strip() for _l in _fh if _l.strip()]\n"
        "                for _rel in _rels:\n"
        "                    try:\n"
        "                        self.addfont(os.path.join(str(mpl.get_data_path()), _rel))\n"
        "                    except Exception:\n"
        "                        pass\n"
        "            except OSError:\n"
        "                pass\n"
    )
    if needle in s:
        s = s.replace(needle, addon, 1)
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

# The eryx preinit sandbox has NO writable filesystem, so matplotlib's config/
# cache dir resolution must not crash: Path.home() raises (no $HOME), and so
# does the tempfile.mkdtemp fallback (no writable /tmp at preinit). Patch
# _get_config_or_cache_dir to (a) pick a literal /tmp candidate instead of
# Path.home() and (b) return that path string instead of raising when no dir is
# writable. The FontManager is still built by scanning the bundled (read-only)
# fonts and gets frozen into the eryx snapshot; font_manager.json_dump already
# tolerates the cache write failing, so a non-writable path here is harmless.
init = root / "lib" / "matplotlib" / "__init__.py"
i = init.read_text()
home_default = "    else:\n        configdir = Path.home() / \".matplotlib\"\n"
home_patched = ("    else:\n"
                "        try:\n"
                "            configdir = Path.home() / \".matplotlib\"\n"
                "        except (RuntimeError, OSError):\n"
                "            configdir = Path(os.environ.get(\"TMPDIR\") or \"/tmp\")\n")
if home_default in i:
    i = i.replace(home_default, home_patched, 1)

raise_default = (
    "    try:\n"
    "        tmpdir = tempfile.mkdtemp(prefix=\"matplotlib-\")\n"
    "    except OSError as exc:\n"
    "        raise OSError(\n"
    "            f\"Matplotlib requires access to a writable cache directory, but there \"\n"
    "            f\"was an issue with the default path ({configdir}), and a temporary \"\n"
    "            f\"directory could not be created; set the MPLCONFIGDIR environment \"\n"
    "            f\"variable to a writable directory\") from exc\n")
raise_patched = (
    "    try:\n"
    "        tmpdir = tempfile.mkdtemp(prefix=\"matplotlib-\")\n"
    "    except OSError:\n"
    "        return str(configdir)  # wasi: no writable dir at preinit\n")
if raise_default in i:
    i = i.replace(raise_default, raise_patched, 1)

init.write_text(i)

# ft2font registers a module-level __getattr__ (a deprecation shim) that raises
# a C++ exception for unknown names. pybind11 turns AttributeError into a C++
# throw, and on wasi we have no working C++ exception runtime (cxa_stubs abort),
# so a routine hasattr() probe at import aborts the whole interpreter. Drop the
# shim: matplotlib 3.10 uses the enum classes, not the deprecated module-level
# constants, so nothing on the import/render path needs it.
ftw = root / "src" / "ft2font_wrapper.cpp"
f = ftw.read_text()
f = f.replace(
    '    m.def("__getattr__", ft2font__getattr__);\n',
    "    (void)ft2font__getattr__;  // wasi: no C++ exceptions; drop throwing shim\n",
    1,
)
ftw.write_text(f)

# Skip the Tk backend extension: _tkagg dlopen()s Tcl/Tk, and wasi has no
# dlopen. It's useless headless; matplotlib uses the Agg backend.
mb = root / "src" / "meson.build"
m = mb.read_text()
if "ext == '_tkagg'" not in m:
    m = m.replace(
        "foreach ext, kwargs : extension_data\n",
        "foreach ext, kwargs : extension_data\n"
        "  if ext == '_tkagg'\n    continue\n  endif\n",
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

# Generate the font index consumed by the FontManager patch above. Built here
# on the real filesystem (os.listdir works); at runtime the eryx VFS cannot
# enumerate directories, so the bundled fonts are registered from this list.
FONTS_DIR="build/lib.wasi-wasm32-${PY_VER}/matplotlib/mpl-data/fonts"
python3 - "${FONTS_DIR}" <<'PY'
import os, sys
root = sys.argv[1]
out = []
for sub in ("ttf", "afm", "pdfcorefonts"):
    d = os.path.join(root, sub)
    if not os.path.isdir(d):
        continue
    for name in sorted(os.listdir(d)):
        if name.lower().endswith((".ttf", ".otf", ".afm")):
            out.append(f"fonts/{sub}/{name}")
with open(os.path.join(root, "_wasi_index.txt"), "w") as fh:
    fh.write("\n".join(out) + "\n")
print("wrote font index:", len(out), "entries ->", os.path.join(root, "_wasi_index.txt"))
PY
