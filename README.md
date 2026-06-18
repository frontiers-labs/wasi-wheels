# WASI wheels

This repository contains build files to produce WASI builds of a set of Python packages which do not have official WASI builds.

**Please note**: This project is an experimental proof-of-concept that Python packages containing native extensions can be cross-compiled for WASI and used with [componentize-py](https://github.com/bytecodealliance/componentize-py).  It is not being actively maintained; the packages are out-of-date with respect to their upstream versions, and might not even build anymore.  Do not rely on these builds for anything serious.

## Building the Packages

Before building, the submodules need to be intialized:

```bash
git submodule update --init --recursive
```

Build all the pacakge using

```bash
make
```

Once the build process is complete, the wheels can be found in the `build` directory. The packages can be used in your code by extracting the `tar.gz` directory in your project root. 

## eryx-compatible native builds

A newer set of packages is built against the exact toolchain that
[eryx](https://github.com/eryx-org/eryx) ships with — CPython 3.14, wasi-sdk-27,
target `wasm32-wasip2` — so the resulting `.so` extensions link cleanly into the
eryx runtime. These are `numpy`, `pandas`, `pillow`, `matplotlib` (plus
matplotlib's compiled deps `contourpy` and `kiwisolver`) and `lxml`.

Each has a dedicated workflow under `.github/workflows/build-<pkg>.yml` that
builds the wheel. `numpy`, `pandas`, `pillow` and `lxml` are also runtime-tested
via `eryx-precompile` (compile + import + a real operation). matplotlib is built
and imported but not runtime-tested — see the limitation below. Sources are
pinned PyPI sdists fetched at build time (not submodules); the shared cross
toolchain lives in `scripts/`, and the C libraries the wheels link against
(zlib, libjpeg-turbo, freetype for Pillow/matplotlib; libxml2 and libxslt for
lxml) are cross-compiled by `scripts/build-clibs.sh`.

Build an individual package locally with, e.g.:

```bash
make build/pandas-wasi.tar.gz
make build/pillow-wasi.tar.gz
make build/matplotlib-wasi.tar.gz
make build/lxml-wasi.tar.gz
```

The release also ships the interpreter the wheels run on as
`cpython-wasi.tar.gz`: the cross-built CPython 3.14 shared library
(`libpython3.14.so`), headers and the full standard library (including
`lib-dynload` extension modules and the wasm sysconfigdata). Build it with:

```bash
make build/cpython-wasi.tar.gz
```

### Known limitations

wasi-sdk on `wasm32-wasip2` cannot unwind C++ exceptions; throwing aborts (see
`scripts/cxa_stubs.c`). `setjmp`/`longjmp` are likewise neutralised
(`scripts/nosjlj.h` traps on `longjmp`) so the extensions don't emit a wasm
exception tag, which eryx's component encoder cannot link. This is fine for
normal use but means error/edge-case paths in `contourpy`, `kiwisolver` and
pandas' C++ window module trap instead of raising.

**matplotlib** is built **Agg-only** (headless `savefig`) and is **not**
runtime-tested by CI. It builds, eryx-encodes and imports, but its render path
needs to read its bundled font files (`mpl-data/fonts/`) at runtime, and the
stock eryx runtime VFS exposes only importable `.py`/`.so` modules — not package
data files — so `open()` of a font fails there. To render inside a host (e.g.
Friday) the runtime must expose the font data directory to the sandbox
filesystem. Source patches applied to make matplotlib viable in the sandbox:

- `font_manager` registers the bundled fonts from a build-time index
  (`mpl-data/fonts/_wasi_index.txt`) because directory enumeration
  (`os.walk`/`os.listdir`) returns nothing on the eryx VFS;
- the config/cache dir falls back to `/tmp` when `$HOME` is unavailable;
- `ft2font`'s throwing module-level `__getattr__` (a deprecation shim) is dropped
  so a routine `hasattr` probe at import does not abort.

Set `MPLBACKEND=Agg` and a writable `MPLCONFIGDIR` at runtime. Pillow must be
importable alongside matplotlib (`matplotlib.colors` imports `PIL` at import).

