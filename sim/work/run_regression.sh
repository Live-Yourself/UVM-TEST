#!/bin/bash
set -euo pipefail

# Batch regression launcher for UVM tests
#
# Usage examples:
#   bash run_regression.sh -l testlists/smoke.list
#   bash run_regression.sh -l testlists/nightly.list -j 4
#   bash run_regression.sh -l testlists/nightly.list --repeat 5 --nightly
#
# List format (space-separated):
#   <test_name> [seed] [extra_plusargs...]
# Examples:
#   i2c_smoke_test
#   i2c_rand_burst_test 12345 +ADDR_BUCKET=HIGH +BURST_LEN=8

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
RUN_UVM="${SCRIPT_DIR}/run_uvm.sh"

LIST_FILE=""
JOBS=1
REPEAT=1
NIGHTLY=0
STOP_ON_FAIL=0
SHOW_OUTPUT=0

usage() {
  cat <<'EOF'
Usage: bash run_regression.sh -l <testlist> [options]

Options:
  -l, --list <file>       Test list file path (required)
  -j, --jobs <N>          Parallel workers (default: 1)
  -r, --repeat <N>        Repeat each list item N times (default: 1)
      --nightly           Nightly mode tag (same behavior, richer summary banner)
      --stop-on-fail      Stop launching new runs after first failure (sequential mode)
      --show-output       Show run_uvm output (live in foreground)
  -h, --help              Show this help
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    -l|--list)
      LIST_FILE="$2"; shift 2 ;;
    -j|--jobs)
      JOBS="$2"; shift 2 ;;
    -r|--repeat)
      REPEAT="$2"; shift 2 ;;
    --nightly)
      NIGHTLY=1; shift ;;
    --stop-on-fail)
      STOP_ON_FAIL=1; shift ;;
    --show-output)
      SHOW_OUTPUT=1; shift ;;
    -h|--help)
      usage; exit 0 ;;
    *)
      echo "[ERR] Unknown option: $1"; usage; exit 2 ;;
  esac
done

if [[ -z "${LIST_FILE}" ]]; then
  echo "[ERR] Missing test list."; usage; exit 2
fi

if [[ ! -f "${LIST_FILE}" ]]; then
  if [[ -f "${SCRIPT_DIR}/${LIST_FILE}" ]]; then
    LIST_FILE="${SCRIPT_DIR}/${LIST_FILE}"
  else
    echo "[ERR] Test list not found: ${LIST_FILE}"; exit 2
  fi
fi

if [[ ! -x "${RUN_UVM}" ]]; then
  chmod +x "${RUN_UVM}" || true
fi

START_TS=$(date '+%F %T')
echo "[REG] Start : ${START_TS}"
echo "[REG] List  : ${LIST_FILE}"
echo "[REG] Jobs  : ${JOBS}"
echo "[REG] Repeat: ${REPEAT}"
if [[ "${NIGHTLY}" -eq 1 ]]; then
  echo "[REG] Mode  : NIGHTLY"
fi

TMP_DIR="${SCRIPT_DIR}/.reg_tmp"
mkdir -p "${TMP_DIR}"
SUMMARY_CSV="${TMP_DIR}/regression_batch_$(date +%Y%m%d_%H%M%S).csv"
echo "case_id,test,seed,extra,status,case_log,start_ts,end_ts" > "${SUMMARY_CSV}"

FAIL_ROOT="${SCRIPT_DIR}/../sim_result/fail_logs"
if [[ "${NIGHTLY}" -eq 1 ]]; then
  FAIL_MODE_DIR="${FAIL_ROOT}/nightly"
elif [[ "${JOBS}" -gt 1 ]]; then
  FAIL_MODE_DIR="${FAIL_ROOT}/parallel"
else
  FAIL_MODE_DIR="${FAIL_ROOT}/batch"
fi
mkdir -p "${FAIL_MODE_DIR}"

case_id=0
pids=()
declare -A pid_case

await_slot() {
  while true; do
    running=$(jobs -rp | wc -l | tr -d ' ')
    if [[ "${running}" -lt "${JOBS}" ]]; then
      break
    fi
    sleep 0.2
  done
}

run_one() {
  local cid="$1" test_name="$2" seed_val="$3" extra_args="$4"
  local status="PASS"
  local case_log="${TMP_DIR}/case_${cid}_${test_name}.log"
  local start_ts end_ts
  local cmd=(bash "${RUN_UVM}" "${test_name}")

  if [[ -n "${seed_val}" ]]; then
    cmd+=("${seed_val}")
  fi
  if [[ -n "${extra_args}" ]]; then
    if [[ -z "${seed_val}" ]]; then
      cmd+=("")
    fi
    cmd+=("${extra_args}")
  fi

  start_ts=$(date '+%F %T')
  echo "[REG][CASE ${cid}] START test=${test_name} seed=${seed_val:-auto} extra='${extra_args}'"

  if [[ "${SHOW_OUTPUT}" -eq 1 ]]; then
    if [[ "${JOBS}" -gt 1 ]]; then
      if "${cmd[@]}" 2>&1 | sed "s/^/[CASE ${cid}] /" | tee "${case_log}"; then
        status="PASS"
      else
        status="FAIL"
      fi
    else
      if "${cmd[@]}" 2>&1 | tee "${case_log}"; then
        status="PASS"
      else
        status="FAIL"
      fi
    fi
  else
    if "${cmd[@]}" >"${case_log}" 2>&1; then
      status="PASS"
    else
      status="FAIL"
      echo "[REG][CASE ${cid}] FAIL, check log: ${case_log}"
    fi
  fi

  end_ts=$(date '+%F %T')

  if [[ "${status}" == "FAIL" ]]; then
    fail_dir="${FAIL_MODE_DIR}/case_${cid}_${test_name}_$(date +%Y%m%d_%H%M%S)"
    mkdir -p "${fail_dir}"
    cp "${case_log}" "${fail_dir}/runner.log" || true
    sim_log=$(grep '^       log :' "${case_log}" | tail -n 1 | sed -E 's/^.*log : //')
    if [[ -n "${sim_log}" ]] && [[ -f "${sim_log}" ]]; then
      cp "${sim_log}" "${fail_dir}/sim.log" || true
    fi
    latest_log=$(grep '^       log_latest:' "${case_log}" | tail -n 1 | sed -E 's/^.*log_latest: //')
    if [[ -n "${latest_log}" ]] && [[ -f "${latest_log}" ]]; then
      cp "${latest_log}" "${fail_dir}/latest.log" || true
    fi
  fi

  echo "[REG][CASE ${cid}] DONE status=${status}"

  echo "${cid},${test_name},${seed_val},${extra_args},${status},${case_log},${start_ts},${end_ts}" >> "${SUMMARY_CSV}"
}

while IFS= read -r line || [[ -n "$line" ]]; do
  # trim leading/trailing spaces
  line="${line#${line%%[![:space:]]*}}"
  line="${line%${line##*[![:space:]]}}"

  [[ -z "${line}" ]] && continue
  [[ "${line}" =~ ^# ]] && continue

  test_name=$(echo "${line}" | awk '{print $1}')
  second=$(echo "${line}" | awk '{print $2}')

  seed_val=""
  extra_args=""
  if [[ "${second}" =~ ^[0-9]+$ ]]; then
    seed_val="${second}"
    extra_args=$(echo "${line}" | cut -d' ' -f3-)
  else
    extra_args=$(echo "${line}" | cut -d' ' -f2-)
  fi

  if [[ "${extra_args}" == "${line}" ]]; then
    extra_args=""
  fi

  for ((i=1; i<=REPEAT; i++)); do
    case_id=$((case_id + 1))

    if [[ "${JOBS}" -gt 1 ]]; then
      await_slot
      run_one "${case_id}" "${test_name}" "${seed_val}" "${extra_args}" &
      pid=$!
      pids+=("${pid}")
      pid_case["${pid}"]="${case_id}:${test_name}"
    else
      run_one "${case_id}" "${test_name}" "${seed_val}" "${extra_args}"
      if [[ "${STOP_ON_FAIL}" -eq 1 ]]; then
        last_status=$(tail -n 1 "${SUMMARY_CSV}" | awk -F, '{print $5}')
        if [[ "${last_status}" == "FAIL" ]]; then
          echo "[REG] Stop on first failure."
          break 2
        fi
      fi
    fi
  done
done < "${LIST_FILE}"

if [[ "${JOBS}" -gt 1 ]]; then
  for pid in "${pids[@]}"; do
    wait "${pid}" || true
  done
fi

# Reorder summary by completion time (newest -> oldest)
SUMMARY_SORTED="${SUMMARY_CSV}.sorted"
head -n 1 "${SUMMARY_CSV}" > "${SUMMARY_SORTED}"
tail -n +2 "${SUMMARY_CSV}" | sort -t, -k8,8r >> "${SUMMARY_SORTED}"
mv "${SUMMARY_SORTED}" "${SUMMARY_CSV}"

TOTAL=$(awk -F, 'NR>1{c++} END{print c+0}' "${SUMMARY_CSV}")
PASS=$(awk -F, 'NR>1&&$5=="PASS"{c++} END{print c+0}' "${SUMMARY_CSV}")
FAIL=$((TOTAL - PASS))
RATE="0.00"
if [[ "${TOTAL}" -gt 0 ]]; then
  RATE=$(awk -v p="${PASS}" -v t="${TOTAL}" 'BEGIN{printf "%.2f", (p*100.0)/t}')
fi

echo "[REG] Done"
echo "[REG] Total=${TOTAL} Pass=${PASS} Fail=${FAIL} PassRate=${RATE}%"
echo "[REG] Batch summary: ${SUMMARY_CSV}"
echo "[REG] Failed logs dir: ${FAIL_MODE_DIR}"
echo "[REG] Global dashboard: ${SCRIPT_DIR}/../sim_result/regression_dashboard.md"

if [[ "${FAIL}" -gt 0 ]]; then
  exit 1
fi
