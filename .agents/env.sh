#!/usr/bin/env bash
# Environment loader for Xilinx tools and the Python venv.
# Source it (`source .agents/env.sh`); it only affects the current shell.
# Override XILINX_ROOT before sourcing to point at another install.

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export REPO_ROOT

export XILINX_ROOT="${XILINX_ROOT:-$HOME/Xilinx/2026.1}"
export VIVADO_BIN="$XILINX_ROOT/Vivado/bin"
export VITIS_BIN="$XILINX_ROOT/Vitis/bin"
export ARM_GCC_BIN="$XILINX_ROOT/gnu/aarch32/lin/gcc-arm-none-eabi/bin"
export VUNIT_SIMULATOR="${VUNIT_SIMULATOR:-ghdl}"

# GHDL lives outside the default PATH on this machine
[ -d /opt/ghdl/bin ] && case ":$PATH:" in *":/opt/ghdl/bin:"*) ;; *) PATH="/opt/ghdl/bin:$PATH" ;; esac

for d in "$VIVADO_BIN" "$VITIS_BIN" "$ARM_GCC_BIN" "$REPO_ROOT/.venv/bin"; do
  [ -d "$d" ] && case ":$PATH:" in *":$d:"*) ;; *) PATH="$d:$PATH" ;; esac
done
export PATH
