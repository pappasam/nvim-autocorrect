NVIM ?= nvim
STYLUA ?= stylua
PYTHON ?= python3
NVIM_TEST = $(NVIM) -u NONE --headless -i NONE -l

.PHONY: help build check test benchmark benchmark-dictionary format
help:
	@echo 'Targets: build check test benchmark benchmark-dictionary format'

build:
	$(NVIM_TEST) scripts/build-dictionary.lua

check:
	$(STYLUA) --config-path stylua.toml --check lua plugin scripts tests
	$(MAKE) test
	$(NVIM_TEST) scripts/build-dictionary.lua --check

test: build
	$(NVIM_TEST) tests/test_source.lua
	$(PYTHON) tests/test_source.py
	$(PYTHON) tests/test_policy.py
	$(PYTHON) tests/test_protected_words.py
	$(NVIM_TEST) tests/test_autocorrect.lua
	$(NVIM_TEST) tests/test_build.lua
	$(NVIM_TEST) tests/test_cache.lua
	$(NVIM_TEST) tests/test_plugin.lua

benchmark:
	$(NVIM_TEST) tests/benchmark.lua

benchmark-dictionary: build
	$(NVIM_TEST) tests/benchmark_dictionary.lua

format:
	$(STYLUA) --config-path stylua.toml lua plugin scripts tests
