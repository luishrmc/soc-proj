# ==============================================================================
# Top-level repository Makefile
# Convenient entry points for simulation, verification gates, and plan audits.
# ==============================================================================

.PHONY: all venv test lint view list clean plan-check plan-sync memory-check audit help

all: test

# Set up Python virtual environment
venv:
	$(MAKE) -C cora7z/app/hw venv

# Run VUnit simulation suite
test:
	$(MAKE) -C cora7z/app/hw test TB=$(TB)

# View simulation waveforms in GTKWave
view:
	$(MAKE) -C cora7z/app/hw view TB=$(TB)

# List all discovered test cases
list:
	$(MAKE) -C cora7z/app/hw list

# Run static VHDL lint gate
lint:
	bash .agents/hooks/vhdl-lint.sh

# Run memory consistency and line limit checks
memory-check:
	python3 .agents/hooks/memory-check.py

# Validate project plan CSVs, dependencies, and state
plan-check:
	python3 .agents/hooks/plan-sync.py check

# Synchronize plan status, changelog, and state
plan-sync:
	python3 .agents/hooks/plan-sync.py sync

# Run pre-task audit (git tree, tools, boundary snapshot)
audit:
	bash .agents/hooks/pre-task-audit.sh

# Clean simulation and temporary build outputs
clean:
	$(MAKE) -C cora7z/app/hw clean
	rm -rf out/ghdl out/*.log

help:
	@echo "Cora Z7-10 Project Commands"
	@echo "==========================="
	@echo "  make venv          Create .venv and install simulation requirements"
	@echo "  make test [TB=..]  Run VUnit simulation suite"
	@echo "  make view [TB=..]  Open GTKWave waveform viewer"
	@echo "  make lint          Run VHDL-2008 static analysis and rules check"
	@echo "  make memory-check  Check freshness of utils/memory/ digests and bounds"
	@echo "  make plan-check    Verify utils/plan/ CSV integrity and DAG"
	@echo "  make plan-sync     Regenerate STATUS.md and CHANGELOG.md"
	@echo "  make audit         Execute pre-task audit gate"
	@echo "  make clean         Remove simulation outputs and temporary files"
