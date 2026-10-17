# ==============================================================================
# VHDL build and simulation flow (VUnit + GHDL)
# Mirrors the reference setup in exercises/slides/corez7, with a venv target.
# ==============================================================================

# Repository root holds the virtual environment and requirements.txt
REPO_ROOT   := $(abspath $(CURDIR)/../../..)
VENV        ?= $(REPO_ROOT)/.venv
PYTHON      ?= $(VENV)/bin/python
VENV_STAMP  := $(VENV)/.installed
GTKWAVE     ?= gtkwave

# Directory paths
BUILD_DIR   ?= build
WAVES_DIR   ?= waves

# Target testbench shorthand (substring of the test name)
TB          ?=

RUN_SCRIPT  := run.py
GTKWAVE_OPT := --dark --rcvar 'fontname_signals Monospace 10'

# GHDL is the simulator driven by VUnit
export VUNIT_SIMULATOR ?= ghdl

# Dynamically locate any .gtkw containing the substring $(TB)
GTKW_FILE   := $(if $(TB),$(firstword $(wildcard $(WAVES_DIR)/*$(TB)*.gtkw)),)
GTKW_ARG    := $(if $(GTKW_FILE),-a $(GTKW_FILE),)

# Pattern filter for VUnit (e.g. *rle*)
TB_PATTERN  := $(if $(TB),"*$(TB)*",)

# Multi-core execution
MCE ?= 1
VUNIT_FLAGS ?= --output-path $(BUILD_DIR)
ifeq ($(MCE),1)
run test: VUNIT_FLAGS += -p 8
endif

.PHONY: all venv run test view list ls-config clean help

# Default target: run all VUnit test suites
all: run

# Create the virtual environment and install the pinned dependencies
venv: $(VENV_STAMP)

$(VENV_STAMP): $(REPO_ROOT)/requirements.txt
	python3 -m venv $(VENV)
	$(VENV)/bin/pip install -r $(REPO_ROOT)/requirements.txt
	@touch $(VENV_STAMP)

# Run simulations (all tests by default, or filtered if TB is set)
run: $(VENV_STAMP)
	@echo "==> Running VUnit simulations $(if $(TB),for [$(TB)],[ALL])..."
	$(PYTHON) $(RUN_SCRIPT) $(VUNIT_FLAGS) $(TB_PATTERN)

# Alias for 'run'
test: run

# Run simulation and launch GTKWave with the matching .gtkw file
view: $(VENV_STAMP)
	@echo "==> Simulating and opening GTKWave for [$(TB)]..."
	@$(if $(GTKW_FILE),echo "==> Attached savefile: $(GTKW_FILE)",echo "==> Note: no matching .gtkw found in $(WAVES_DIR)/")
	-$(PYTHON) $(RUN_SCRIPT) $(VUNIT_FLAGS) --gui \
		--gtkwave-args="$(GTKWAVE_OPT) $(GTKW_ARG)" $(TB_PATTERN)

# List all discovered testbenches and test cases
list: $(VENV_STAMP)
	@echo "==> Listing discovered VUnit test cases..."
	$(PYTHON) $(RUN_SCRIPT) $(VUNIT_FLAGS) --list

# Export language server config for VS Code / vhdl-ls
ls-config: $(VENV_STAMP)
	@echo "==> Generating vhdl_ls.toml configuration..."
	$(PYTHON) $(RUN_SCRIPT) $(VUNIT_FLAGS) --export-json vhdl_ls.toml

# Clean the build directory and temporary files
clean:
	@echo "==> Cleaning build directory: $(BUILD_DIR)..."
	rm -rf $(BUILD_DIR) vunit_out
	@echo "==> Clean complete."

help:
	@echo "VUnit Simulation Flow"
	@echo "====================="
	@echo "Usage: make [target] [TB=substring] [BUILD_DIR=path] [VUNIT_FLAGS='...']"
	@echo ""
	@echo "Targets:"
	@echo "  all / run   Run the full VUnit test suite (default)"
	@echo "  venv        Create .venv at the repo root and install requirements.txt"
	@echo "  test        Alias for run"
	@echo "  view        Run simulation and open GTKWave with the matching .gtkw"
	@echo "  list        List discovered tests without running"
	@echo "  ls-config   Generate vhdl_ls.toml for LSP / VS Code"
	@echo "  clean       Remove build artifacts"
