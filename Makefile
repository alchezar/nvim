# Tests run on mini.test. Each case gets a fresh child nvim (see tests/).
# Bump MINI_TEST_REF, then delete .deps/mini.test to fetch the new version.
NVIM ?= nvim
MINI_TEST_REF ?= v0.18.0
# --clean keeps the runner off the real shada and user dirs; -u still applies.
RUN = $(NVIM) --headless --clean -u tests/minimal_init.lua

.PHONY: test test-file

test: .deps/mini.test
	$(RUN) -c "lua MiniTest.run()"

# make test-file FILE=tests/test_smoke.lua
test-file: .deps/mini.test
	$(RUN) -c "lua MiniTest.run_file('$(FILE)')"

.deps/mini.test:
	git clone --filter=blob:none --branch $(MINI_TEST_REF) https://github.com/nvim-mini/mini.test $@
