#!/usr/bin/env bash
# Structured Human-in-the-Loop (HITL) reproduction template for debug-loop.
# Copy to $TMPDIR, customize the steps between the markers, and execute.
set -euo pipefail

step() {
  printf '\n>>> %s\n' "$1"
  read -r -p "    [Press Enter when completed] " _
}

capture() {
  local var="$1" question="$2" answer
  printf '\n>>> %s\n' "$question"
  read -r -p "    > " answer
  printf -v "$var" '%s' "$answer"
}

# --- Customize reproduction steps below ---

step "Open the target application and navigate to the reproduction screen."
capture OBSERVED_ERROR "Trigger the action. Did the failure occur? (y/n)"
capture ERROR_DETAIL "Paste the redacted error output or observed symptom:"

# --- Customize reproduction steps above ---

printf '\n--- Captured Reproduction Telemetry ---\n'
printf 'OBSERVED_ERROR=%s\n' "$OBSERVED_ERROR"
printf 'ERROR_DETAIL=%s\n' "$ERROR_DETAIL"
