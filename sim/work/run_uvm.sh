#!/bin/bash
set -euo pipefail

# Usage:
#   bash run_uvm.sh [UVM_TESTNAME] [SEED]
# Notes:
#   The argument is a UVM test class name, not a top-level file name.
#   The simulation top is fixed to tb_uvm_top from the filelist.
#   SEED is optional; when omitted, script auto-generates a seed and records it.

TEST_NAME=${1:-i2c_smoke_test}
SEED_ARG=${2:-}
CDIR=$(pwd)

RESULT_ROOT="$CDIR/../sim_result/${TEST_NAME}"
WAVE_DIR="$RESULT_ROOT/wave"
LOG_DIR="$RESULT_ROOT/log"
MISC_DIR="$RESULT_ROOT/misc"
COV_DIR="$MISC_DIR/CovData"

mkdir -p "$WAVE_DIR" "$LOG_DIR" "$MISC_DIR" "$COV_DIR"
cd "$MISC_DIR"

if [[ -n "$SEED_ARG" ]]; then
  SEED="$SEED_ARG"
  SEED_MODE="fixed"
else
  # Generate a per-run seed in [1, 2147483646]
  NS=$(date +%s%N)
  SEED=$(( (NS % 2147483646) + 1 ))
  SEED_MODE="auto"
fi

SEED_OPT="+ntb_random_seed=${SEED}"
SEED_INFO="${SEED_MODE}(${SEED})"
SEED_FILE="${LOG_DIR}/${TEST_NAME}.seed"
SEED_HIST_FILE="${LOG_DIR}/seed_history.log"

echo "${SEED}" > "${SEED_FILE}"
echo "$(date '+%F %T') test=${TEST_NAME} mode=${SEED_MODE} seed=${SEED}" >> "${SEED_HIST_FILE}"

VCS_CMD=(
  vcs
  -full64
  -sverilog
  -ntb_opts uvm-1.2
  -f ../../work/uvm_filelist.f
  -top tb_uvm_top
  +UVM_TESTNAME=${TEST_NAME}
  ${SEED_OPT}
  -timescale=1ns/1ps
  -debug_access+all -kdb -lca
  -cm line+cond+fsm+tgl+branch
  -cm_dir ${COV_DIR}/${TEST_NAME}.cm
  -l ${LOG_DIR}/${TEST_NAME}.log
  -o simv
)

if [[ -n "${VERDI_HOME:-}" ]] && [[ -f "${VERDI_HOME}/share/PLI/VCS/LINUX64/novas.tab" ]]; then
  VCS_CMD+=(
    +define+DUMP_FSDB
    -P "${VERDI_HOME}/share/PLI/VCS/LINUX64/novas.tab" "${VERDI_HOME}/share/PLI/VCS/LINUX64/pli.a"
    +FSDB_FILE=${WAVE_DIR}/${TEST_NAME}.fsdb
  )
else
  echo "[WARN] VERDI_HOME is not set or PLI was not found; FSDB will not be generated."
fi

"${VCS_CMD[@]}" -R

if [[ -d "${COV_DIR}/${TEST_NAME}.cm.vdb" ]]; then
  urg -dir "${COV_DIR}/${TEST_NAME}.cm.vdb" -report "${MISC_DIR}/Cov_Report"
fi

echo "[DONE] UVM test=${TEST_NAME}"
echo "       top : tb_uvm_top"
echo "       seed: ${SEED_INFO}"
echo "       seed_file: ${SEED_FILE}"
echo "       log : ${LOG_DIR}/${TEST_NAME}.log"
echo "       cov : ${MISC_DIR}/Cov_Report"
echo "       fsdb: ${WAVE_DIR}/${TEST_NAME}.fsdb (if enabled)"
