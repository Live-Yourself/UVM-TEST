#!/bin/bash
set -euo pipefail

fail() {
  echo "[TEST][FAIL] $*" >&2
  exit 1
}

TEST_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
WORK_DIR=$(cd "${TEST_DIR}/.." && pwd)
REPO_ROOT=$(cd "${WORK_DIR}/../.." && pwd)
RUN_UVM="${WORK_DIR}/run_uvm.sh"
TMP_ROOT=$(mktemp -d)
trap 'rm -rf "${TMP_ROOT}"' EXIT

FAKE_BIN="${TMP_ROOT}/bin"
mkdir -p "${FAKE_BIN}"

cat > "${FAKE_BIN}/vcs" <<'FAKE_VCS'
#!/bin/bash
set -euo pipefail

log=""
fsdb=""
rc="${FAKE_VCS_RC:-0}"

if [[ -n "${FAKE_VCS_ARGS_FILE:-}" ]]; then
  printf '%s\n' "$@" > "${FAKE_VCS_ARGS_FILE}"
fi

while [[ $# -gt 0 ]]; do
  case "$1" in
    -l)
      log="$2"
      shift 2
      ;;
    +FSDB_FILE=*)
      fsdb="${1#+FSDB_FILE=}"
      shift
      ;;
    *)
      shift
      ;;
  esac
done

if [[ -n "${log}" ]]; then
  mkdir -p "$(dirname "${log}")"
  if [[ "${rc}" -eq 0 ]]; then
    cat > "${log}" <<'LOG'
UVM_INFO @ 0: reporter [SCB_FCOV] functional_coverage=10.00% samples=1
UVM_INFO @ 0: reporter [SCB_BUCKET] addr_low=1 addr_mid=0 addr_high=0 len_single=1 len_short=0 len_burst=0 illegal_read=0
UVM_INFO @ 0: reporter [SCB_BUCKET2] legal_wr=1 legal_rd=1 illegal_wr=0 illegal_rd=0 ack_all=1 ack_nack=0 rd_match=1
LOG
  else
    cat > "${log}" <<'LOG'
UVM_FATAL @ 0: reporter [FAKE_FAIL] fake VCS failure
LOG
  fi
fi

if [[ "${rc}" -eq 0 && -n "${fsdb}" ]]; then
  mkdir -p "$(dirname "${fsdb}")"
  printf 'fake fsdb\n' > "${fsdb}"
fi

exit "${rc}"
FAKE_VCS
chmod +x "${FAKE_BIN}/vcs"

extract_filelist_arg() {
  local args_file="$1"
  awk 'prev=="-f"{print; exit} {prev=$0}' "${args_file}"
}

test_cwd_independent_filelist() {
  local result_base="${TMP_ROOT}/result_cwd"
  local args_file="${TMP_ROOT}/vcs_args_cwd.txt"
  local filelist_arg

  (
    cd "${TMP_ROOT}"
    PATH="${FAKE_BIN}:${PATH}" \
      RESULT_BASE="${result_base}" \
      FSDB_ENABLE=0 \
      FAKE_VCS_RC=0 \
      FAKE_VCS_ARGS_FILE="${args_file}" \
      bash "${RUN_UVM}" i2c_smoke_test 123 >/dev/null
  )

  filelist_arg=$(extract_filelist_arg "${args_file}")
  [[ -n "${filelist_arg}" ]] || fail "vcs -f argument was not captured"
  [[ -f "${filelist_arg}" ]] || fail "generated filelist does not exist: ${filelist_arg}"

  if grep -q '/home/huhh/' "${filelist_arg}"; then
    fail "generated filelist still contains developer-local absolute paths"
  fi
  grep -q "^+incdir+${REPO_ROOT}/sim/uvm/if$" "${filelist_arg}" || \
    fail "generated filelist did not absolutize UVM include paths"
  grep -q "^${REPO_ROOT}/rtl/i2c_slave_top.v$" "${filelist_arg}" || \
    fail "generated filelist did not absolutize RTL source paths"
}

test_failure_exit_propagates() {
  local result_base="${TMP_ROOT}/result_fail"
  local rc

  set +e
  (
    cd "${TMP_ROOT}"
    PATH="${FAKE_BIN}:${PATH}" \
      RESULT_BASE="${result_base}" \
      FSDB_ENABLE=0 \
      FAKE_VCS_RC=1 \
      bash "${RUN_UVM}" i2c_smoke_test 456 >/dev/null
  )
  rc=$?
  set -e

  [[ "${rc}" -ne 0 ]] || fail "run_uvm returned success for a failed VCS run"
  grep -q ',FAIL,' "${result_base}/regression_runs.csv" || \
    fail "failed run was not recorded as FAIL in regression_runs.csv"
}

test_pass_fsdbs_remain_unique() {
  local result_base="${TMP_ROOT}/result_fsdb"
  local verdi_home="${TMP_ROOT}/verdi"
  local pass_dir="${result_base}/i2c_smoke_test/wave/pass"
  local count

  mkdir -p "${verdi_home}/share/PLI/VCS/LINUX64"
  : > "${verdi_home}/share/PLI/VCS/LINUX64/novas.tab"
  : > "${verdi_home}/share/PLI/VCS/LINUX64/pli.a"

  for _ in 1 2; do
    (
      cd "${TMP_ROOT}"
      PATH="${FAKE_BIN}:${PATH}" \
        RESULT_BASE="${result_base}" \
        VERDI_HOME="${verdi_home}" \
        FSDB_ENABLE=1 \
        FSDB_REQUIRE=1 \
        FAKE_VCS_RC=0 \
        bash "${RUN_UVM}" i2c_smoke_test 777 >/dev/null
    )
  done

  count=$(find "${pass_dir}" -maxdepth 1 -type f -name '*.fsdb' | wc -l | tr -d ' ')
  [[ "${count}" -eq 2 ]] || fail "expected 2 unique PASS FSDBs, found ${count}"
  [[ ! -e "${pass_dir}/i2c_smoke_test.fsdb" ]] || \
    fail "PASS FSDBs should keep run-unique names, not overwrite ${pass_dir}/i2c_smoke_test.fsdb"
}

test_cwd_independent_filelist
test_failure_exit_propagates
test_pass_fsdbs_remain_unique

echo "[TEST][PASS] run_uvm harness checks passed"
