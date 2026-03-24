#!/bin/bash
set -euo pipefail

# Usage:
#   bash run_uvm.sh [UVM_TESTNAME] [SEED] [EXTRA_PLUSARGS]
# Notes:
#   The argument is a UVM test class name, not a top-level file name.
#   The simulation top is fixed to tb_uvm_top from the filelist.
#   SEED is optional; when omitted, script auto-generates a seed and records it.

TEST_NAME=${1:-i2c_smoke_test}
SEED_ARG=${2:-}
EXTRA_PLUSARGS=${3:-}
CDIR=$(pwd)
RESULT_BASE="$CDIR/../sim_result"

# Arg normalization:
# If 2nd argument is not numeric, treat it as EXTRA_PLUSARGS rather than SEED.
# This supports calling style: bash run_uvm.sh <test> +SCB_SRC=MON
if [[ -n "${SEED_ARG}" ]] && [[ ! "${SEED_ARG}" =~ ^[0-9]+$ ]]; then
  if [[ -n "${EXTRA_PLUSARGS}" ]]; then
    EXTRA_PLUSARGS="${SEED_ARG} ${EXTRA_PLUSARGS}"
  else
    EXTRA_PLUSARGS="${SEED_ARG}"
  fi
  SEED_ARG=""
fi

RESULT_ROOT="$RESULT_BASE/${TEST_NAME}"
WAVE_DIR="$RESULT_ROOT/wave"
LOG_DIR="$RESULT_ROOT/log"
MISC_DIR="$RESULT_ROOT/misc"
COV_DIR="$MISC_DIR/CovData"

mkdir -p "$WAVE_DIR" "$LOG_DIR" "$MISC_DIR" "$COV_DIR"

if [[ -n "$SEED_ARG" ]]; then
  SEED="$SEED_ARG"
  SEED_MODE="fixed"
else
  # Generate a per-run seed in [1, 2147483646]
  NS=$(date +%s%N)
  SEED=$(( (NS % 2147483646) + 1 ))
  SEED_MODE="auto"
fi

RUN_TAG="$(date +%Y%m%d_%H%M%S)"
COV_RUN_NAME="${RUN_TAG}_${SEED}"
COV_RUN_DIR="${COV_DIR}/${COV_RUN_NAME}.cm"
LOG_FILE="${LOG_DIR}/${COV_RUN_NAME}.log"
LATEST_LOG="${LOG_DIR}/${TEST_NAME}.log"
RUN_WORK_DIR="${MISC_DIR}/work_${COV_RUN_NAME}_$$"
mkdir -p "${RUN_WORK_DIR}"

# Optional DUT-only code/toggle collection (set env: COV_SCOPE=dut)
COV_SCOPE="${COV_SCOPE:-all}"
COV_SCOPE_INFO="all"

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
  -f /home/huhh/uvm_auto_regression/sim/work/filelist.f
  -top tb_uvm_top
  +UVM_TESTNAME=${TEST_NAME}
  ${SEED_OPT}
  -timescale=1ns/1ps
  -debug_access+all -kdb -lca
  -cm line+cond+fsm+tgl+branch
  -cm_dir ${COV_RUN_DIR}
  -l ${LOG_FILE}
  -o simv
)

if [[ "${COV_SCOPE}" == "dut" ]]; then
  CM_HIER_TMP="${MISC_DIR}/cm_hier_dut_${RUN_TAG}_${SEED}_$$.cfg"
  echo "+tree tb_uvm_top.dut" > "${CM_HIER_TMP}"
  VCS_CMD+=( -cm_hier "${CM_HIER_TMP}" )
  COV_SCOPE_INFO="dut"
fi

if [[ -n "${EXTRA_PLUSARGS}" ]]; then
  # shellcheck disable=SC2206
  EXTRA_ARR=( ${EXTRA_PLUSARGS} )
  VCS_CMD+=("${EXTRA_ARR[@]}")
fi

FSDB_FILE_PATH=""
FSDB_FILE_FINAL=""
FSDB_EXPECTED=0
FSDB_PRODUCED=0

# FSDB switch:
#   FSDB_ENABLE=1/on/true  -> enable FSDB when Verdi PLI exists
#   FSDB_ENABLE=0/off/false -> disable FSDB
#   unset                   -> default enable (backward compatible)
FSDB_ENABLE_RAW="${FSDB_ENABLE:-1}"
case "${FSDB_ENABLE_RAW}" in
  1|on|ON|true|TRUE|yes|YES) FSDB_ENABLE_FLAG=1 ;;
  0|off|OFF|false|FALSE|no|NO) FSDB_ENABLE_FLAG=0 ;;
  *) FSDB_ENABLE_FLAG=1 ;;
esac

if [[ "${FSDB_ENABLE_FLAG}" -eq 1 ]] && [[ -n "${VERDI_HOME:-}" ]] && [[ -f "${VERDI_HOME}/share/PLI/VCS/LINUX64/novas.tab" ]]; then
  FSDB_EXPECTED=1
  FSDB_FILE_PATH="${WAVE_DIR}/${COV_RUN_NAME}.fsdb"

  VCS_CMD+=(
    +define+DUMP_FSDB
    -P "${VERDI_HOME}/share/PLI/VCS/LINUX64/novas.tab" "${VERDI_HOME}/share/PLI/VCS/LINUX64/pli.a"
    +FSDB_FILE=${FSDB_FILE_PATH}
  )
elif [[ "${FSDB_ENABLE_FLAG}" -eq 1 ]]; then
  echo "[WARN] FSDB enabled but VERDI_HOME/PLI not found; FSDB will not be generated."
else
  echo "[INFO] FSDB disabled by FSDB_ENABLE=${FSDB_ENABLE_RAW}"
fi

FSDB_REQUIRE="${FSDB_REQUIRE:-0}"

VCS_RC=0
RUN_ABORT_REASON=""
if pushd "${RUN_WORK_DIR}" >/dev/null; then
  if "${VCS_CMD[@]}" -R; then
    VCS_RC=0
  else
    VCS_RC=$?
    RUN_ABORT_REASON="VCS_RUN_FAIL"
    if [[ -f "${LOG_FILE}" ]]; then
      if grep -q "FSDB ERROR" "${LOG_FILE}" || grep -q "unexpected call to the exit() function" "${LOG_FILE}"; then
        RUN_ABORT_REASON="FSDB_IO_ERROR"
      fi
    fi
    echo "[WARN] vcs -R failed (rc=${VCS_RC}), continue to record FAIL into regression DBs"
  fi
  popd >/dev/null
else
  VCS_RC=2
  RUN_ABORT_REASON="WORKDIR_ENTER_FAIL"
  echo "[WARN] cannot enter run work dir: ${RUN_WORK_DIR}"
fi

if [[ -f "${LOG_FILE}" ]]; then
  cp "${LOG_FILE}" "${LATEST_LOG}"
else
  echo "[WARN] simulation log not found: ${LOG_FILE}"
fi


if [[ "${VCS_RC}" -eq 0 ]] && [[ -d "${COV_RUN_DIR}.vdb" ]]; then
  urg -dir "${COV_RUN_DIR}.vdb" -report "${MISC_DIR}/Cov_${COV_RUN_NAME}" || \
    echo "[WARN] urg single-run report failed for ${COV_RUN_DIR}.vdb"
fi

 
# Merge all test coverage DBs into one consolidated report under sim_result
MERGE_REPORT_DIR="${RESULT_BASE}/Cov_Report_All"
MERGE_LIST_FILE="${RESULT_BASE}/merged_cov_inputs.txt"
find "${RESULT_BASE}" -type d -name "*.cm.vdb" | sort > "${MERGE_LIST_FILE}"

if [[ -s "${MERGE_LIST_FILE}" ]]; then
  URG_MERGE_CMD=(urg)
  while IFS= read -r vdb; do
    URG_MERGE_CMD+=(-dir "${vdb}")
  done < "${MERGE_LIST_FILE}"
  URG_MERGE_CMD+=(-report "${MERGE_REPORT_DIR}")
  "${URG_MERGE_CMD[@]}" || echo "[WARN] urg merged report failed"
fi

if [[ -f "${CDIR}/run_summarize.sh" ]]; then
  # shellcheck source=/dev/null
  source "${CDIR}/run_summarize.sh"
else
  echo "[ERR] missing post script: ${SCRIPT_DIR}/run_summarize.sh"
  exit 2
fi
