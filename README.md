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
eryx runtime. These are `numpy`, `pandas`, `pillow` and `matplotlib` (plus
matplotlib's compiled deps `contourpy` and `kiwisolver`).

Each has a dedicated workflow under `.github/workflows/build-<pkg>.yml` that
builds the wheel and runtime-tests it via `eryx-precompile`. Sources are pinned
PyPI sdists fetched at build time (not submodules); the shared cross toolchain
lives in `scripts/`, and the C libraries Pillow/matplotlib link against (zlib,
libjpeg-turbo, freetype) are cross-compiled by `scripts/build-clibs.sh`.

Build an individual package locally with, e.g.:

```bash
make build/pandas-wasi.tar.gz
make build/pillow-wasi.tar.gz
make build/matplotlib-wasi.tar.gz
```

### Known limitations

wasi-sdk on `wasm32-wasip2` cannot unwind C++ exceptions; throwing aborts (see
`scripts/cxa_stubs.c`). This is fine for normal use of these packages but means:

- **matplotlib** is built **Agg-only** (headless `savefig`). Basic plotting works;
  `constrained_layout`/`tight_layout` drive `kiwisolver`'s exception paths and may
  abort. Set `MPLBACKEND=Agg` and a writable `MPLCONFIGDIR` at runtime.
- Error/edge-case paths in `contourpy`, `kiwisolver` and pandas' C++ window
  module trap instead of raising.

