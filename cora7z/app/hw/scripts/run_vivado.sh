#!/usr/bin/env bash
# ==============================================================================
# run_vivado.sh: Standardized Vivado batch runner with context-based log organization
#
# Usage:
#   bash cora7z/app/hw/scripts/run_vivado.sh <path_to_tcl_script> [context_or_task_id]
#
# Examples:
#   bash cora7z/app/hw/scripts/run_vivado.sh cora7z/app/hw/scripts/configure_block_design.tcl task_2.1
#   bash cora7z/app/hw/scripts/run_vivado.sh cora7z/app/hw/scripts/add_rle_to_bd.tcl task_2.2
#   bash cora7z/app/hw/scripts/run_vivado.sh cora7z/app/hw/scripts/add_lz4_to_bd.tcl task_2.3
#
# Outputs:
#   All execution logs, journals, and reports are saved in:
#     out/vivado/<context_or_task_id>/vivado.log
#     out/vivado/<context_or_task_id>/vivado.jou
# ==============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../../../../" && pwd)"

if [ -f "${REPO_ROOT}/.agents/env.sh" ]; then
    # shellcheck disable=SC1091
    source "${REPO_ROOT}/.agents/env.sh"
fi

if [ $# -lt 1 ]; then
    echo "Usage: $0 <path_to_tcl_script> [context_or_task_id]" >&2
    exit 1
fi

TCL_SCRIPT="$1"
CONTEXT="${2:-adhoc}"

if [ ! -f "${TCL_SCRIPT}" ]; then
    echo "ERROR: Tcl script '${TCL_SCRIPT}' does not exist." >&2
    exit 1
fi

# Convert TCL_SCRIPT to absolute path
TCL_SCRIPT="$(cd "$(dirname "${TCL_SCRIPT}")" && pwd)/$(basename "${TCL_SCRIPT}")"

OUT_DIR="${REPO_ROOT}/out/vivado/${CONTEXT}"
mkdir -p "${OUT_DIR}"

LOG_FILE="${OUT_DIR}/vivado.log"
JOURNAL_FILE="${OUT_DIR}/vivado.jou"

echo "================================================================================"
echo "[VIVADO RUNNER] Executing Tcl Script: ${TCL_SCRIPT}"
echo "[VIVADO RUNNER] Target Context / Task: ${CONTEXT}"
echo "[VIVADO RUNNER] Log File:              ${LOG_FILE}"
echo "[VIVADO RUNNER] Journal File:          ${JOURNAL_FILE}"
echo "================================================================================"

# Execute Vivado non-interactively
set +e
vivado -mode batch -notrace \
    -log "${LOG_FILE}" \
    -journal "${JOURNAL_FILE}" \
    -source "${TCL_SCRIPT}" \
    -tclargs "${OUT_DIR}"
EXIT_CODE=$?
set -e

echo ""
echo "================================================================================"
echo "[VIVADO RUNNER] Execution finished with exit code: ${EXIT_CODE}"

if [ -f "${LOG_FILE}" ]; then
    CW_COUNT=$(grep -c "^CRITICAL WARNING:" "${LOG_FILE}" 2>/dev/null || true)
    ERR_COUNT=$(grep -c "^ERROR:" "${LOG_FILE}" 2>/dev/null || true)
    WARN_COUNT=$(grep -c "^WARNING:" "${LOG_FILE}" 2>/dev/null || true)

    echo "[VIVADO RUNNER] Results Summary:"
    echo "  - Errors:            ${ERR_COUNT}"
    echo "  - Critical Warnings: ${CW_COUNT}"
    echo "  - Warnings:          ${WARN_COUNT}"
    echo "================================================================================"

    if [ "${EXIT_CODE}" -ne 0 ] || [ "${ERR_COUNT}" -gt 0 ]; then
        echo "[ERROR] Vivado encountered fatal errors. Last 30 lines of log:" >&2
        tail -n 30 "${LOG_FILE}" >&2
        exit 1
    fi

    if [ "${CW_COUNT}" -gt 0 ]; then
        echo "[WARNING] Critical warnings detected in ${LOG_FILE}:" >&2
        grep -n "^CRITICAL WARNING:" "${LOG_FILE}" >&2
    fi
else
    echo "[ERROR] Expected log file '${LOG_FILE}' was not created." >&2
    exit 1
fi

exit "${EXIT_CODE}"
