NVIM ?= nvim
STYLUA ?= stylua
PYTHON ?= python3

.PHONY: test lint format perf perf-ui ui differential defaults test-fff
test:
	$(NVIM) --headless -u NONE -i NONE -l tests/run.lua
lint:
	$(STYLUA) --check lua plugin tests scripts doc
	$(NVIM) --headless -u NONE -i NONE -l scripts/check.lua
format:
	$(STYLUA) lua plugin tests scripts doc
perf:
	$(NVIM) --headless -u NONE -i NONE -l scripts/perf.lua
perf-ui:
	$(PYTHON) scripts/bench_ui.py
ui:
	$(PYTHON) tests/ui.py
differential:
	$(NVIM) --headless -u NONE -i NONE -l tests/differential.lua
defaults:
	$(NVIM) --headless -u NONE -i NONE -l scripts/defaults.lua
	$(STYLUA) doc/default-config.lua
test-fff:
	$(NVIM) --headless -u NONE -i NONE -l scripts/fff_real.lua
