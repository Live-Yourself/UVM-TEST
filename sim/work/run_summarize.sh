#!/bin/bash
# Post-processing for run_uvm.sh
# This script is intended to be sourced by run_uvm.sh after coverage DB merge step.

: "${RESULT_BASE:?}"
: "${TEST_NAME:?}"
: "${SEED:?}"
: "${SEED_MODE:?}"
: "${LOG_FILE:?}"
: "${LATEST_LOG:?}"
: "${MISC_DIR:?}"
: "${COV_RUN_NAME:?}"
: "${COV_RUN_DIR:?}"
: "${MERGE_REPORT_DIR:?}"
: "${MERGE_LIST_FILE:?}"
: "${BUCKET_DB:=}"
: "${BUCKET2_DB:=}"
: "${RUN_DB:=}"
: "${FAIL_DB:=}"
: "${DASHBOARD_FILE:=}"
: "${WAVE_DIR:?}"
: "${FSDB_FILE_PATH:=}"
: "${FSDB_FILE_FINAL:=}"
: "${FSDB_EXPECTED:=0}"
: "${FSDB_PRODUCED:=0}"
: "${FSDB_REQUIRE:=0}"
: "${RUN_ABORT_REASON:=}"
: "${VCS_RC:=0}"
: "${SEED_INFO:=}"
: "${COV_SCOPE_INFO:=all}"
: "${SEED_FILE:=}"

LOG_ARCHIVE="${LOG_FILE}"

if [[ -f "${LOG_FILE}" ]]; then
  UVM_ERR_CNT=$(grep -cE '^UVM_ERROR .*\[[^]]+\]' "${LOG_FILE}" || true)
  UVM_FATAL_CNT=$(grep -cE '^UVM_FATAL .*\[[^]]+\]' "${LOG_FILE}" || true)
  UVM_WARN_CNT=$(grep -cE '^UVM_WARNING .*\[[^]]+\]' "${LOG_FILE}" || true)
else
  UVM_ERR_CNT=0
  UVM_FATAL_CNT=0
  UVM_WARN_CNT=0
fi

if [[ "${VCS_RC}" -eq 0 ]] && [[ "${UVM_ERR_CNT}" -eq 0 && "${UVM_FATAL_CNT}" -eq 0 ]]; then
  RUN_STATUS="PASS"
else
  RUN_STATUS="FAIL"
fi

if [[ -n "${FSDB_FILE_PATH}" ]] && [[ -f "${FSDB_FILE_PATH}" ]]; then
  FSDB_PRODUCED=1
fi

FUNC_COV="N/A"
FCOV_VAL=""
if [[ -f "${LOG_FILE}" ]]; then
  FCOV_VAL=$(sed -nE 's/.*functional_coverage=([0-9]+(\.[0-9]+)?)%.*/\1/p' "${LOG_FILE}" | tail -n 1)
fi
if [[ -n "${FCOV_VAL}" ]]; then
  FUNC_COV="${FCOV_VAL}"
fi

FUNC_COV_SAMPLES="0"
FCOV_SAMPLES_VAL=""
if [[ -f "${LOG_FILE}" ]]; then
  FCOV_SAMPLES_VAL=$(sed -nE 's/.*functional_coverage=[0-9]+(\.[0-9]+)?% samples=([0-9]+).*/\2/p' "${LOG_FILE}" | tail -n 1)
fi
if [[ -n "${FCOV_SAMPLES_VAL}" ]]; then
  FUNC_COV_SAMPLES="${FCOV_SAMPLES_VAL}"
fi

FCOV_MIN_SAMPLES="${FCOV_MIN_SAMPLES:-1}"
if [[ "${FUNC_COV_SAMPLES}" =~ ^[0-9]+$ ]] && [[ "${FUNC_COV_SAMPLES}" -lt "${FCOV_MIN_SAMPLES}" ]]; then
  RUN_STATUS="FAIL"
  echo "[WARN] FCOV samples=${FUNC_COV_SAMPLES} < FCOV_MIN_SAMPLES=${FCOV_MIN_SAMPLES}, mark run as FAIL"
fi

# If FSDB is required in this run policy, convert silent-missing FSDB to FAIL.
if [[ "${FSDB_REQUIRE}" == "1" ]] && [[ "${FSDB_EXPECTED}" -eq 1 ]] && [[ "${RUN_STATUS}" == "PASS" ]] && [[ "${FSDB_PRODUCED}" -eq 0 ]]; then
  RUN_STATUS="FAIL"
  if [[ -z "${RUN_ABORT_REASON}" ]]; then
    RUN_ABORT_REASON="FSDB_MISSING"
  fi
  echo "[WARN] FSDB_REQUIRE=1 but no FSDB produced, mark run as FAIL"
fi

extract_kv_num() {
  local line="$1"
  local key="$2"
  local val
  val=$(echo "${line}" | sed -nE "s/.*${key}=([0-9]+).*/\\1/p")
  if [[ -z "${val}" ]]; then
    echo 0
  else
    echo "${val}"
  fi
}

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

bucket_line=""
if [[ -f "${LOG_FILE}" ]]; then
  bucket_line=$(grep -E "\[SCB_BUCKET\].*addr_low=[0-9]+.*addr_mid=[0-9]+.*addr_high=[0-9]+.*len_single=[0-9]+.*len_short=[0-9]+.*len_burst=[0-9]+.*illegal_read=[0-9]+" "${LOG_FILE}" | tail -n 1 || true)
fi
if [[ -n "${bucket_line}" ]]; then
  addr_low=$(extract_kv_num "${bucket_line}" "addr_low")
  addr_mid=$(extract_kv_num "${bucket_line}" "addr_mid")
  addr_high=$(extract_kv_num "${bucket_line}" "addr_high")
  len_single=$(extract_kv_num "${bucket_line}" "len_single")
  len_short=$(extract_kv_num "${bucket_line}" "len_short")
  len_burst=$(extract_kv_num "${bucket_line}" "len_burst")
  illegal_read=$(extract_kv_num "${bucket_line}" "illegal_read")
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
bucket2_seen=0

bucket2_line=""
if [[ -f "${LOG_FILE}" ]]; then
  bucket2_line=$(grep -E "\[SCB_BUCKET2\].*legal_wr=[0-9]+.*legal_rd=[0-9]+.*illegal_wr=[0-9]+.*illegal_rd=[0-9]+.*ack_all=[0-9]+.*ack_nack=[0-9]+.*rd_match=[0-9]+" "${LOG_FILE}" | tail -n 1 || true)
fi
if [[ -n "${bucket2_line}" ]]; then
  bucket2_seen=1
  legal_wr=$(extract_kv_num "${bucket2_line}" "legal_wr")
  legal_rd=$(extract_kv_num "${bucket2_line}" "legal_rd")
  illegal_wr=$(extract_kv_num "${bucket2_line}" "illegal_wr")
  illegal_rd=$(extract_kv_num "${bucket2_line}" "illegal_rd")
  ack_all=$(extract_kv_num "${bucket2_line}" "ack_all")
  ack_nack=$(extract_kv_num "${bucket2_line}" "ack_nack")
  rd_match=$(extract_kv_num "${bucket2_line}" "rd_match")
else
  echo "[WARN] SCB_BUCKET2 line not found in log, V2 bucket CSV row will be all zeros"
fi

# Optional strict check: if transactions reached SCB but SCB_BUCKET2 is absent,
# mark run FAIL to avoid false-positive closure dashboards.
STRICT_BUCKET2="${STRICT_BUCKET2:-0}"
if [[ "${bucket2_seen}" -eq 0 ]] && [[ "${STRICT_BUCKET2}" == "1" ]] && [[ "${FUNC_COV_SAMPLES}" =~ ^[0-9]+$ ]] && [[ "${FUNC_COV_SAMPLES}" -gt 0 ]]; then
  RUN_STATUS="FAIL"
  echo "[WARN] STRICT_BUCKET2=1 and SCB_BUCKET2 missing while func_cov_samples=${FUNC_COV_SAMPLES}; mark run as FAIL"
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
  if [[ -n "${RUN_ABORT_REASON}" ]]; then
    echo "$(date '+%F %T'),${TEST_NAME},${SEED},${RUN_ABORT_REASON},1" >> "${FAIL_DB}"
  fi
  if [[ -f "${LOG_FILE}" ]]; then
    (grep "UVM_ERROR" "${LOG_FILE}" || true) | sed -n 's/.*\[\([^]]*\)\].*/\1/p' | sort | uniq -c | while read -r cnt id; do
      echo "$(date '+%F %T'),${TEST_NAME},${SEED},${id},${cnt}" >> "${FAIL_DB}"
    done
  fi
fi

# Organize FSDB by final run status for easier debug triage.
if [[ -n "${FSDB_FILE_PATH}" ]] && [[ -f "${FSDB_FILE_PATH}" ]]; then
  status_dir="$(echo "${RUN_STATUS}" | tr '[:upper:]' '[:lower:]')"
  fsdb_target_dir="${WAVE_DIR}/${status_dir}"
  mkdir -p "${fsdb_target_dir}"
  if [[ "${RUN_STATUS}" == "PASS" ]]; then
    FSDB_FILE_FINAL="${fsdb_target_dir}/${TEST_NAME}.fsdb"
  else
    FSDB_FILE_FINAL="${fsdb_target_dir}/$(basename "${FSDB_FILE_PATH}")"
  fi
  mv "${FSDB_FILE_PATH}" "${FSDB_FILE_FINAL}" || FSDB_FILE_FINAL="${FSDB_FILE_PATH}"
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
    "functional coverage closure matrix:i2c_cov_closure_test" \
    "illegal address NACK:i2c_illegal_addr_test" \
    "clock low stretch timing:i2c_stretch_test" \
    "random burst read/write:i2c_rand_burst_test"; do
    scenario=${pair%%:*}
    tname=${pair##*:}
    tpass=$(awk -F, -v t="${tname}" 'NR>1&&$2==t&&$5=="PASS"{c++} END{print c+0}' "${RUN_DB}")
    if [[ "${tpass}" -gt 0 ]]; then
      echo "| ${scenario} | ${tname} | ? covered | at least one PASS |"
    else
      echo "| ${scenario} | ${tname} | ? missing | no PASS record yet, prioritize this test |"
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
    total_v2_hits=$((total_legal_wr + total_legal_rd + total_illegal_wr + total_illegal_rd + total_ack_all + total_ack_nack + total_rd_match))
    if [[ "${total_v2_hits}" -eq 0 ]] && [[ "${TOTAL_RUNS}" -gt 0 ]]; then
      echo
      echo "> ?? Note: all V2 buckets are 0. This often means SCB_BUCKET2 was not printed/parsed (collection path issue), not necessarily stimulus issue."
    fi
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
echo "       cov_run : ${MISC_DIR}/Cov_${COV_RUN_NAME}"
echo "       cov_merged: ${MERGE_REPORT_DIR}"
echo "       cov_inputs: ${MERGE_LIST_FILE}"
echo "       cov_buckets: ${BUCKET_DB}"
echo "       cov_buckets_v2: ${BUCKET2_DB}"
echo "       dashboard: ${DASHBOARD_FILE}"
if [[ -n "${FSDB_FILE_FINAL}" ]]; then
  echo "       fsdb: ${FSDB_FILE_FINAL}"
else
  echo "       fsdb: ${WAVE_DIR}/<pass|fail>/${COV_RUN_NAME}.fsdb (if enabled)"
fi
