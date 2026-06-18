BUILD_DIR := $(abspath build)
WASI_SDK := $(BUILD_DIR)/wasi-sdk
CPYTHON := $(abspath cpython/builddir/wasi/install)
SYSCONFIG := $(abspath cpython/builddir/wasi/build/lib.wasi-wasm32-3.14)
OUTPUTS := \
	$(BUILD_DIR)/aiohttp-wasi.tar.gz \
	$(BUILD_DIR)/charset_normalizer-wasi.tar.gz \
	$(BUILD_DIR)/frozenlist-wasi.tar.gz \
	$(BUILD_DIR)/lxml-wasi.tar.gz \
	$(BUILD_DIR)/multidict-wasi.tar.gz \
	$(BUILD_DIR)/numpy-wasi.tar.gz \
	$(BUILD_DIR)/pandas-wasi.tar.gz \
	$(BUILD_DIR)/pydantic_core-wasi.tar.gz \
	$(BUILD_DIR)/regex-wasi.tar.gz \
	$(BUILD_DIR)/sqlalchemy-wasi.tar.gz \
	$(BUILD_DIR)/tiktoken-wasi.tar.gz \
	$(BUILD_DIR)/tiktoken_ext-wasi.tar.gz \
	$(BUILD_DIR)/wrapt-wasi.tar.gz \
	$(BUILD_DIR)/yaml-wasi.tar.gz \
	$(BUILD_DIR)/_yaml-wasi.tar.gz \
	$(BUILD_DIR)/yarl-wasi.tar.gz
WASI_SDK_VERSION := 27
HOST_OS := $(shell uname -s | sed -e 's/Darwin/macos/' -e 's/Linux/linux/')
HOST_ARCH := $(shell uname -m | sed -e 's/aarch64/arm64/')
PYO3_CROSS_LIB_DIR := $(abspath cpython/builddir/wasi/build/lib.wasi-wasm32-3.14)

.PHONY: all
all: $(OUTPUTS)

$(OUTPUTS): $(WASI_SDK) $(CPYTHON)

$(BUILD_DIR)/aiohttp-wasi.tar.gz: $(WASI_SDK) $(CPYTHON)
	@mkdir -p "$(@D)"
	(cd aiohttp && CROSS_PREFIX=$(CPYTHON) WASI_SDK_PATH=$(WASI_SDK) bash build.sh)
	cp -a aiohttp/src/build/*/aiohttp "$(@D)"
	(cd "$(@D)" && tar czf aiohttp-wasi.tar.gz aiohttp)

$(BUILD_DIR)/charset_normalizer-wasi.tar.gz: $(WASI_SDK) $(CPYTHON)
	@mkdir -p "$(@D)"
	(cd charset_normalizer && CROSS_PREFIX=$(CPYTHON) WASI_SDK_PATH=$(WASI_SDK) bash build.sh)
	cp -a charset_normalizer/src/build/lib.*/charset_normalizer "$(@D)"
	(cd "$(@D)" && tar czf charset_normalizer-wasi.tar.gz charset_normalizer)

$(BUILD_DIR)/frozenlist-wasi.tar.gz: $(WASI_SDK) $(CPYTHON)
	@mkdir -p "$(@D)"
	(cd frozenlist && CROSS_PREFIX=$(CPYTHON) WASI_SDK_PATH=$(WASI_SDK) bash build.sh)
	cp -a frozenlist/src/build/*/frozenlist "$(@D)"
	(cd "$(@D)" && tar czf frozenlist-wasi.tar.gz frozenlist)

$(BUILD_DIR)/multidict-wasi.tar.gz: $(WASI_SDK) $(CPYTHON)
	@mkdir -p "$(@D)"
	(cd multidict && CROSS_PREFIX=$(CPYTHON) WASI_SDK_PATH=$(WASI_SDK) bash build.sh)
	cp -a multidict/src/build/lib.*/multidict "$(@D)"
	(cd "$(@D)" && tar czf multidict-wasi.tar.gz multidict)

$(BUILD_DIR)/numpy-wasi.tar.gz: $(WASI_SDK) $(CPYTHON)
	@mkdir -p "$(@D)"
	(cd numpy && CROSS_PREFIX=$(CPYTHON) WASI_SDK_PATH=$(WASI_SDK) bash build.sh)
	cp -a numpy/src/build/lib.*/numpy "$(@D)"
	(cd "$(@D)" && tar czf numpy-wasi.tar.gz numpy)

# pandas compiles its Cython extensions against the wasi numpy headers, so the
# numpy build must run first.
$(BUILD_DIR)/pandas-wasi.tar.gz: $(WASI_SDK) $(CPYTHON) $(BUILD_DIR)/numpy-wasi.tar.gz
	@mkdir -p "$(@D)"
	(cd pandas && CROSS_PREFIX=$(CPYTHON) WASI_SDK_PATH=$(WASI_SDK) bash build.sh)
	cp -a pandas/src/build/lib.*/pandas "$(@D)"
	(cd "$(@D)" && tar czf pandas-wasi.tar.gz pandas)

$(BUILD_DIR)/pillow-wasi.tar.gz: $(WASI_SDK) $(CPYTHON)
	@mkdir -p "$(@D)"
	(cd pillow && CROSS_PREFIX=$(CPYTHON) WASI_SDK_PATH=$(WASI_SDK) bash build.sh)
	cp -a pillow/src/build/lib.*/PIL "$(@D)"
	(cd "$(@D)" && tar czf pillow-wasi.tar.gz PIL)

$(BUILD_DIR)/contourpy-wasi.tar.gz: $(WASI_SDK) $(CPYTHON)
	@mkdir -p "$(@D)"
	(cd contourpy && CROSS_PREFIX=$(CPYTHON) WASI_SDK_PATH=$(WASI_SDK) bash build.sh)
	cp -a contourpy/src/build/lib.*/contourpy "$(@D)"
	(cd "$(@D)" && tar czf contourpy-wasi.tar.gz contourpy)

$(BUILD_DIR)/kiwisolver-wasi.tar.gz: $(WASI_SDK) $(CPYTHON)
	@mkdir -p "$(@D)"
	(cd kiwisolver && CROSS_PREFIX=$(CPYTHON) WASI_SDK_PATH=$(WASI_SDK) bash build.sh)
	cp -a kiwisolver/src/build/lib.*/kiwisolver "$(@D)"
	(cd "$(@D)" && tar czf kiwisolver-wasi.tar.gz kiwisolver)

# matplotlib (Agg backend). Ships matplotlib + mpl_toolkits + pylab.py. Its
# compiled run deps (numpy, contourpy, kiwisolver) are built by their own
# targets and assembled for the runtime test in CI.
$(BUILD_DIR)/matplotlib-wasi.tar.gz: $(WASI_SDK) $(CPYTHON)
	@mkdir -p "$(@D)"
	(cd matplotlib && CROSS_PREFIX=$(CPYTHON) WASI_SDK_PATH=$(WASI_SDK) bash build.sh)
	cp -a matplotlib/src/build/lib.*/matplotlib "$(@D)"
	cp -a matplotlib/src/build/lib.*/mpl_toolkits "$(@D)"
	cp -a matplotlib/src/build/lib.*/pylab.py "$(@D)"
	(cd "$(@D)" && tar czf matplotlib-wasi.tar.gz matplotlib mpl_toolkits pylab.py)

# lxml links the cross-built libxml2 + libxslt static archives (built first by
# its build.sh via scripts/build-clibs.sh).
$(BUILD_DIR)/lxml-wasi.tar.gz: $(WASI_SDK) $(CPYTHON)
	@mkdir -p "$(@D)"
	(cd lxml && CROSS_PREFIX=$(CPYTHON) WASI_SDK_PATH=$(WASI_SDK) bash build.sh)
	cp -a lxml/src/build/lib.*/lxml "$(@D)"
	(cd "$(@D)" && tar czf lxml-wasi.tar.gz lxml)

$(BUILD_DIR)/pydantic_core-wasi.tar.gz: $(WASI_SDK) $(CPYTHON)
	@mkdir -p "$(@D)"
	(cd pydantic-core && PYO3_CROSS_LIB_DIR=$(PYO3_CROSS_LIB_DIR) CROSS_PREFIX=$(CPYTHON) WASI_SDK_PATH=$(WASI_SDK) bash build.sh)
	cp -a pydantic-core/src/build/*/pydantic_core "$(@D)"
	(cd "$(@D)" && tar czf pydantic_core-wasi.tar.gz pydantic_core)

$(BUILD_DIR)/regex-wasi.tar.gz: $(WASI_SDK) $(CPYTHON)
	@mkdir -p "$(@D)"
	(cd regex && CROSS_PREFIX=$(CPYTHON) WASI_SDK_PATH=$(WASI_SDK) bash build.sh)
	cp -a regex/src/build/lib.*/regex "$(@D)"
	(cd "$(@D)" && tar czf regex-wasi.tar.gz regex)

$(BUILD_DIR)/sqlalchemy-wasi.tar.gz: $(WASI_SDK) $(CPYTHON)
	@mkdir -p "$(@D)"
	(cd sqlalchemy && CROSS_PREFIX=$(CPYTHON) WASI_SDK_PATH=$(WASI_SDK) bash build.sh)
	cp -a sqlalchemy/src/build/lib.*/sqlalchemy "$(@D)"
	(cd "$(@D)" && tar czf sqlalchemy-wasi.tar.gz sqlalchemy)

$(BUILD_DIR)/tiktoken_ext-wasi.tar.gz: $(BUILD_DIR)/tiktoken-wasi.tar.gz
	cp -a tiktoken/src/build/lib.*/tiktoken_ext "$(@D)"
	(cd "$(@D)" && tar czf tiktoken_ext-wasi.tar.gz tiktoken_ext)

$(BUILD_DIR)/tiktoken-wasi.tar.gz: $(WASI_SDK) $(CPYTHON)
	@mkdir -p "$(@D)"
	(cd tiktoken && PYO3_CROSS_LIB_DIR=$(PYO3_CROSS_LIB_DIR) CROSS_PREFIX=$(CPYTHON) SYSCONFIG=$(SYSCONFIG) WASI_SDK_PATH=$(WASI_SDK) bash build.sh)
	cp -a tiktoken/src/build/lib.*/tiktoken "$(@D)"
	(cd "$(@D)" && tar czf tiktoken-wasi.tar.gz tiktoken)

$(BUILD_DIR)/wrapt-wasi.tar.gz: $(WASI_SDK) $(CPYTHON)
	@mkdir -p "$(@D)"
	(cd wrapt && CROSS_PREFIX=$(CPYTHON) WASI_SDK_PATH=$(WASI_SDK) bash build.sh)
	cp -a wrapt/src/build/lib.*/wrapt "$(@D)"
	(cd "$(@D)" && tar czf wrapt-wasi.tar.gz wrapt)

$(BUILD_DIR)/yaml-wasi.tar.gz: $(BUILD_DIR)/_yaml-wasi.tar.gz
	cp -a yaml/src/build/lib.*/yaml "$(@D)"
	(cd "$(@D)" && tar czf yaml-wasi.tar.gz yaml)

$(BUILD_DIR)/_yaml-wasi.tar.gz: $(WASI_SDK) $(CPYTHON)
	@mkdir -p "$(@D)"
	(cd yaml && CROSS_PREFIX=$(CPYTHON) WASI_SDK_PATH=$(WASI_SDK) bash build.sh)
	cp -a yaml/src/build/lib.*/_yaml "$(@D)"
	(cd "$(@D)" && tar czf _yaml-wasi.tar.gz _yaml)

$(BUILD_DIR)/yarl-wasi.tar.gz: $(WASI_SDK) $(CPYTHON)
	@mkdir -p "$(@D)"
	(cd yarl && CROSS_PREFIX=$(CPYTHON) WASI_SDK_PATH=$(WASI_SDK) bash build.sh)
	cp -a yarl/src/build/*/yarl "$(@D)"
	(cd "$(@D)" && tar czf yarl-wasi.tar.gz yarl)

$(WASI_SDK):
	@mkdir -p "$(@D)"
	(cd "$(@D)" && \
		curl -LO https://github.com/WebAssembly/wasi-sdk/releases/download/wasi-sdk-${WASI_SDK_VERSION}/wasi-sdk-${WASI_SDK_VERSION}.0-${HOST_ARCH}-${HOST_OS}.tar.gz && \
		tar xf wasi-sdk-${WASI_SDK_VERSION}.0-${HOST_ARCH}-${HOST_OS}.tar.gz && \
		mv wasi-sdk-${WASI_SDK_VERSION}.0-${HOST_ARCH}-${HOST_OS} wasi-sdk && \
		rm "wasi-sdk-$(WASI_SDK_VERSION).0-${HOST_ARCH}-${HOST_OS}.tar.gz")

$(CPYTHON): $(WASI_SDK)
	@mkdir -p "$(@D)"
	@mkdir -p "$(@D)"/../build
	@echo "$(@D)"
	(cd "$(@D)"/../build && ../../configure --prefix=$$(pwd)/install && make)
	(cd "$(@D)" && \
		WASI_SDK_PATH=$(WASI_SDK) \
		CONFIG_SITE=../../Tools/wasm/wasi/config.site-wasm32-wasi \
		CFLAGS=-fPIC \
		../../Tools/wasm/wasi-env \
		../../configure \
		-C \
		--host=wasm32-unknown-wasip2 \
		--build=$$(../../config.guess) \
		--with-build-python=$$(if [ -e $$(pwd)/../build/python.exe ]; \
			then echo $$(pwd)/../build/python.exe; \
			else echo $$(pwd)/../build/python; \
			fi) \
		--prefix=$$(pwd)/install \
		--enable-wasm-dynamic-linking \
		--enable-ipv6 \
		--disable-test-modules && \
		make build_all install && \
		$(WASI_SDK)/bin/clang \
		--target=wasm32-wasip2 \
		-shared \
		-o $(CPYTHON)/lib/libpython3.14.so \
		-Wl,--whole-archive $(CPYTHON)/lib/libpython3.14.a -Wl,--no-whole-archive \
		$(CPYTHON)/../Modules/_hacl/libHacl_HMAC.a \
		$(CPYTHON)/../Modules/_hacl/libHacl_Hash_BLAKE2.a \
		$(CPYTHON)/../Modules/_hacl/libHacl_Hash_MD5.a \
		$(CPYTHON)/../Modules/_hacl/libHacl_Hash_SHA1.a \
		$(CPYTHON)/../Modules/_hacl/libHacl_Hash_SHA2.a \
		$(CPYTHON)/../Modules/_hacl/libHacl_Hash_SHA3.a \
		$(CPYTHON)/../Modules/_decimal/libmpdec/libmpdec.a \
		$(CPYTHON)/../Modules/expat/libexpat.a \
		-lwasi-emulated-signal \
		-lwasi-emulated-getpid \
		-lwasi-emulated-process-clocks \
		-ldl)

.PHONY: install-hooks
install-hooks:
	git config core.hooksPath .githooks
	@echo "git hooks enabled (core.hooksPath=.githooks)"

# Cross-build just the C libraries (no CPython needed). Used by the pre-commit
# hook; also handy on its own.
.PHONY: check-clibs
check-clibs:
	bash scripts/check-clibs.sh

.PHONY: clean
clean:
	rm -rf $(BUILD_DIR) cpython/builddir numpy/numpy/build
	rm -rf pandas/src pillow/src contourpy/src kiwisolver/src matplotlib/src lxml/src
	rm -f scripts/cxa_stubs.o
	find . -name 'venv' -maxdepth 2 | xargs -I {} rm -rf {}
	find . -name 'build' -maxdepth 3 | xargs -I {} rm -rf {}
	find . -name 'dist' -maxdepth 3 | xargs -I {} rm -rf {}
