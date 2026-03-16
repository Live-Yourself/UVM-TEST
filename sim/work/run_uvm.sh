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
SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
SIM_DIR=$(cd "${SCRIPT_DIR}/.." && pwd)
RESULT_BASE="${SIM_DIR}/sim_result"
FILELIST="${SCRIPT_DIR}/filelist.f"

RESULT_ROOT="$RESULT_BASE/${TEST_NAME}"
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

RUN_TAG="$(date +%Y%m%d_%H%M%S)"
COV_RUN_NAME="${TEST_NAME}_${SEED}_${RUN_TAG}"
COV_RUN_DIR="${COV_DIR}/${COV_RUN_NAME}.cm"
LOG_FILE="${LOG_DIR}/${COV_RUN_NAME}.log"
LATEST_LOG="${LOG_DIR}/${TEST_NAME}.log"

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
  -f ${FILELIST}
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
  CM_HIER_TMP="${MISC_DIR}/cm_hier_dut_${RUN_TAG}.cfg"
  echo "+tree tb_uvm_top.dut" > "${CM_HIER_TMP}"
  VCS_CMD+=( -cm_hier "${CM_HIER_TMP}" )
  COV_SCOPE_INFO="dut"
fi

if [[ -n "${EXTRA_PLUSARGS}" ]]; then
  # shellcheck disable=SC2206
  EXTRA_ARR=( ${EXTRA_PLUSARGS} )
  VCS_CMD+=("${EXTRA_ARR[@]}")
fi

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

cp "${LOG_FILE}" "${LATEST_LOG}"

if [[ -d "${COV_RUN_DIR}.vdb" ]]; then
  urg -dir "${COV_RUN_DIR}.vdb" -report "${MISC_DIR}/Cov_Report_${COV_RUN_NAME}" || \
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

LOG_ARCHIVE="${LOG_FILE}"

UVM_ERR_CNT=$(grep -cE '^UVM_ERROR .*\[[^]]+\]' "${LOG_FILE}" || true)
UVM_FATAL_CNT=$(grep -cE '^UVM_FATAL .*\[[^]]+\]' "${LOG_FILE}" || true)
UVM_WARN_CNT=$(grep -cE '^UVM_WARNING .*\[[^]]+\]' "${LOG_FILE}" || true)

if [[ "${UVM_ERR_CNT}" -eq 0 && "${UVM_FATAL_CNT}" -eq 0 ]]; then
  RUN_STATUS="PASS"
else
  RUN_STATUS="FAIL"
fi

FUNC_COV="N/A"
FCOV_VAL=$(sed -nE 's/.*functional_coverage=([0-9]+(\.[0-9]+)?)%.*/\1/p' "${LOG_FILE}" | tail -n 1)
if [[ -n "${FCOV_VAL}" ]]; then
  FUNC_COV="${FCOV_VAL}"
fi

FUNC_COV_SAMPLES="0"
FCOV_SAMPLES_VAL=$(sed -nE 's/.*functional_coverage=[0-9]+(\.[0-9]+)?% samples=([0-9]+).*/\2/p' "${LOG_FILE}" | tail -n 1)
if [[ -n "${FCOV_SAMPLES_VAL}" ]]; then
  FUNC_COV_SAMPLES="${FCOV_SAMPLES_VAL}"
fi

FCOV_MIN_SAMPLES="${FCOV_MIN_SAMPLES:-1}"
if [[ "${FUNC_COV_SAMPLES}" =~ ^[0-9]+$ ]] && [[ "${FUNC_COV_SAMPLES}" -lt "${FCOV_MIN_SAMPLES}" ]]; then
  RUN_STATUS="FAIL"
  echo "[WARN] FCOV samples=${FUNC_COV_SAMPLES} < FCOV_MIN_SAMPLES=${FCOV_MIN_SAMPLES}, mark run as FAIL"
fi

# Parse bucket-hit line from scoreboard and persist as coverage report CSV
BUCKET_DB="${RESULT_BASE}/coverage_buckets.csv"
if [[ ! -f "${BUCKET_DB}" ]]; then
  echo "timestamp,test,seed,addr_low,addr_mid,addr_high,len_single,len_short,len_burst,illegal_read" > "${BUCKET_DB}"
fi

addr_low=0
addr_mid=0
addr_high=0
len_single=0
len_short=0
len_burst=0
illegal_read=0

bucket_line=$(grep "\[SCB_BUCKET\]" "${LOG_FILE}" | tail -n 1 || true)
if [[ -n "${bucket_line}" ]]; then
  addr_low=$(echo "${bucket_line}" | sed -nE 's/.*addr_low=([0-9]+).*/\1/p')
  addr_mid=$(echo "${bucket_line}" | sed -nE 's/.*addr_mid=([0-9]+).*/\1/p')
  addr_high=$(echo "${bucket_line}" | sed -nE 's/.*addr_high=([0-9]+).*/\1/p')
  len_single=$(echo "${bucket_line}" | sed -nE 's/.*len_single=([0-9]+).*/\1/p')
  len_short=$(echo "${bucket_line}" | sed -nE 's/.*len_short=([0-9]+).*/\1/p')
  len_burst=$(echo "${bucket_line}" | sed -nE 's/.*len_burst=([0-9]+).*/\1/p')
  illegal_read=$(echo "${bucket_line}" | sed -nE 's/.*illegal_read=([0-9]+).*/\1/p')
fi

echo "$(date '+%F %T'),${TEST_NAME},${SEED},${addr_low:-0},${addr_mid:-0},${addr_high:-0},${len_single:-0},${len_short:-0},${len_burst:-0},${illegal_read:-0}" >> "${BUCKET_DB}"

BUCKET2_DB="${RESULT_BASE}/coverage_buckets_v2.csv"
if [[ ! -f "${BUCKET2_DB}" ]]; then
  echo "timestamp,test,seed,legal_wr,legal_rd,illegal_wr,illegal_rd,ack_all,ack_nack,rd_match" > "${BUCKET2_DB}"
fi

legal_wr=0
legal_rd=0
illegal_wr=0
illegal_rd=0
ack_all=0
ack_nack=0
rd_match=0

bucket2_line=$(grep "\[SCB_BUCKET2\]" "${LOG_FILE}" | tail -n 1 || true)
if [[ -n "${bucket2_line}" ]]; then
  legal_wr=$(echo "${bucket2_line}" | sed -nE 's/.*legal_wr=([0-9]+).*/\1/p')
  legal_rd=$(echo "${bucket2_line}" | sed -nE 's/.*legal_rd=([0-9]+).*/\1/p')
  illegal_wr=$(echo "${bucket2_line}" | sed -nE 's/.*illegal_wr=([0-9]+).*/\1/p')
  illegal_rd=$(echo "${bucket2_line}" | sed -nE 's/.*illegal_rd=([0-9]+).*/\1/p')
  ack_all=$(echo "${bucket2_line}" | sed -nE 's/.*ack_all=([0-9]+).*/\1/p')
  ack_nack=$(echo "${bucket2_line}" | sed -nE 's/.*ack_nack=([0-9]+).*/\1/p')
  rd_match=$(echo "${bucket2_line}" | sed -nE 's/.*rd_match=([0-9]+).*/\1/p')
fi

echo "$(date '+%F %T'),${TEST_NAME},${SEED},${legal_wr:-0},${legal_rd:-0},${illegal_wr:-0},${illegal_rd:-0},${ack_all:-0},${ack_nack:-0},${rd_match:-0}" >> "${BUCKET2_DB}"

RUN_DB="${RESULT_BASE}/regression_runs.csv"
if [[ ! -f "${RUN_DB}" ]]; then
  echo "timestamp,test,seed,mode,status,uvm_error,uvm_fatal,uvm_warning,func_cov,func_cov_samples,log" > "${RUN_DB}"
fi
echo "$(date '+%F %T'),${TEST_NAME},${SEED},${SEED_MODE},${RUN_STATUS},${UVM_ERR_CNT},${UVM_FATAL_CNT},${UVM_WARN_CNT},${FUNC_COV},${FUNC_COV_SAMPLES},${LOG_ARCHIVE}" >> "${RUN_DB}"

FAIL_DB="${RESULT_BASE}/failure_events.csv"
if [[ ! -f "${FAIL_DB}" ]]; then
  echo "timestamp,test,seed,id,count" > "${FAIL_DB}"
fi
if [[ "${RUN_STATUS}" == "FAIL" ]]; then
  grep "UVM_ERROR" "${LOG_FILE}" | sed -n 's/.*\[\([^]]*\)\].*/\1/p' | sort | uniq -c | while read -r cnt id; do
    echo "$(date '+%F %T'),${TEST_NAME},${SEED},${id},${cnt}" >> "${FAIL_DB}"
  done
fi

DASHBOARD_FILE="${RESULT_BASE}/regression_dashboard.md"
TOTAL_RUNS=$(awk -F, 'NR>1{c++} END{print c+0}' "${RUN_DB}")
PASS_RUNS=$(awk -F, 'NR>1&&$5=="PASS"{c++} END{print c+0}' "${RUN_DB}")
FAIL_RUNS=$(awk -F, 'NR>1&&$5=="FAIL"{c++} END{print c+0}' "${RUN_DB}")

if [[ "${TOTAL_RUNS}" -gt 0 ]]; then
  PASS_RATE=$(awk -v p="${PASS_RUNS}" -v t="${TOTAL_RUNS}" 'BEGIN{printf "%.2f", (p*100.0)/t}')
else
  PASS_RATE="0.00"
fi

CODE_COV_HINT="${MERGE_REPORT_DIR}"

{
  echo "# UVM Regression Dashboard"
  echo
  echo "- Total runs: ${TOTAL_RUNS}"
  echo "- Passed runs: ${PASS_RUNS}"
  echo "- Failed runs: ${FAIL_RUNS}"
  echo "- Pass rate: ${PASS_RATE}%"
  echo "- Merged code coverage report: ${CODE_COV_HINT}"
  echo
  echo "## Test Pass Rate"
  echo
  echo "| test | runs | pass | fail | pass_rate | latest_seed | latest_func_cov | latest_func_cov_samples |"
  echo "|---|---:|---:|---:|---:|---:|---:|---:|"
  awk -F, '
    NR>1{
      test=$2; runs[test]++; if($5=="PASS") pass[test]++; else fail[test]++;
      seed[test]=$3; fcov[test]=$9; fsample[test]=$10;
    }
    END{
      for (t in runs) {
        pr=(runs[t]>0)?(pass[t]*100.0/runs[t]):0.0;
        printf "| %s | %d | %d | %d | %.2f%% | %s | %s | %s |\n", t, runs[t], pass[t]+0, fail[t]+0, pr, seed[t], fcov[t], fsample[t];
      }
    }' "${RUN_DB}" | sort
  echo
  echo "## Failure Distribution (by error ID)"
  echo
  if [[ -f "${FAIL_DB}" ]]; then
    echo "| error_id | count |"
    echo "|---|---:|"
    awk -F, 'NR>1{cnt[$4]+=$5} END{for (id in cnt) printf "| %s | %d |\n", id, cnt[id]}' "${FAIL_DB}" | sort -t'|' -k3,3nr
  else
    echo "No failure records yet."
  fi
  echo
  echo "## Missing Scenarios"
  echo
  echo "| scenario | mapped_test | status | note |"
  echo "|---|---|---|---|"
  for pair in \
    "basic read/write loop:i2c_smoke_test" \
    "illegal address NACK:i2c_illegal_addr_test" \
    "clock low stretch timing:i2c_stretch_test" \
    "random burst read/write:i2c_rand_burst_test"; do
    scenario=${pair%%:*}
    tname=${pair##*:}
    tpass=$(awk -F, -v t="${tname}" 'NR>1&&$2==t&&$5=="PASS"{c++} END{print c+0}' "${RUN_DB}")
    if [[ "${tpass}" -gt 0 ]]; then
      echo "| ${scenario} | ${tname} | ✅ covered | at least one PASS |"
    else
      echo "| ${scenario} | ${tname} | ❌ missing | no PASS record yet, prioritize this test |"
    fi
  done
  echo
  echo "## Functional Coverage Trend (latest 20 runs)"
  echo
  echo "| timestamp | test | seed | status | func_cov(%) | func_cov_samples |"
  echo "|---|---|---:|---|---:|---:|"
  tail -n +2 "${RUN_DB}" | tail -n 20 | awk -F, '{printf "| %s | %s | %s | %s | %s | %s |\n", $1, $2, $3, $5, $9, $10}'
  echo
  echo "## Functional Bucket Status (V2 aggregate)"
  echo
  if [[ -f "${BUCKET2_DB}" ]]; then
    total_legal_wr=$(awk -F, 'NR>1{c+=$4} END{print c+0}' "${BUCKET2_DB}")
    total_legal_rd=$(awk -F, 'NR>1{c+=$5} END{print c+0}' "${BUCKET2_DB}")
    total_illegal_wr=$(awk -F, 'NR>1{c+=$6} END{print c+0}' "${BUCKET2_DB}")
    total_illegal_rd=$(awk -F, 'NR>1{c+=$7} END{print c+0}' "${BUCKET2_DB}")
    total_ack_all=$(awk -F, 'NR>1{c+=$8} END{print c+0}' "${BUCKET2_DB}")
    total_ack_nack=$(awk -F, 'NR>1{c+=$9} END{print c+0}' "${BUCKET2_DB}")
    total_rd_match=$(awk -F, 'NR>1{c+=$10} END{print c+0}' "${BUCKET2_DB}")
    echo "| bucket | hit_count | status |"
    echo "|---|---:|---|"
    for pair in \
      "legal_wr:${total_legal_wr}" \
      "legal_rd:${total_legal_rd}" \
      "illegal_wr:${total_illegal_wr}" \
      "illegal_rd:${total_illegal_rd}" \
      "ack_all:${total_ack_all}" \
      "ack_nack:${total_ack_nack}" \
      "rd_match:${total_rd_match}"; do
      bname=${pair%%:*}
      bcnt=${pair##*:}
      if [[ "${bcnt}" -gt 0 ]]; then
        bstat="covered"
      else
        bstat="missing"
      fi
      echo "| ${bname} | ${bcnt} | ${bstat} |"
    done
  else
    echo "No v2 bucket records yet."
  fi
  echo
  echo "## Functional Coverage Average by Test"
  echo
  echo "| test | valid_cov_samples | avg_func_cov(%) | latest_func_cov(%) |"
  echo "|---|---:|---:|---:|"
  awk -F, '
    NR>1{
      t=$2;
      latest[t]=$9;
      if ($9!="N/A") {
        sum[t]+=$9;
        cnt[t]++;
      }
    }
    END{
      for (t in latest) {
        avg=(cnt[t]>0)?(sum[t]/cnt[t]):0.0;
        printf "| %s | %d | %.2f | %s |\n", t, cnt[t]+0, avg, latest[t];
      }
    }' "${RUN_DB}" | sort
} > "${DASHBOARD_FILE}"

echo "[DONE] UVM test=${TEST_NAME}"
echo "       top : tb_uvm_top"
echo "       seed: ${SEED_INFO}"
echo "       cov_scope: ${COV_SCOPE_INFO}"
echo "       seed_file: ${SEED_FILE}"
echo "       log : ${LOG_FILE}"
echo "       log_latest: ${LATEST_LOG}"
echo "       cov_run : ${MISC_DIR}/Cov_Report_${COV_RUN_NAME}"
echo "       cov_merged: ${MERGE_REPORT_DIR}"
echo "       cov_inputs: ${MERGE_LIST_FILE}"
echo "       cov_buckets: ${BUCKET_DB}"
echo "       cov_buckets_v2: ${BUCKET2_DB}"
echo "       dashboard: ${DASHBOARD_FILE}"
echo "       fsdb: ${WAVE_DIR}/${TEST_NAME}.fsdb (if enabled)"
