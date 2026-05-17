#!/bin/bash
set -euo pipefail

TEST_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
SCRIPT_DIR=$(cd "${TEST_DIR}/.." && pwd)
REPO_ROOT=$(cd "${SCRIPT_DIR}/../.." && pwd)
TMP_ROOT=$(mktemp -d)

cleanup() {
  rm -rf "${TMP_ROOT}"
}
trap cleanup EXIT

fail() {
  echo "[FAIL] $*" >&2
  exit 1
}

FAKE_BIN="${TMP_ROOT}/bin"
mkdir -p "${FAKE_BIN}"

cat > "${FAKE_BIN}/vcs" <<'STUB_VCS'
#!/bin/bash
set -euo pipefail

: "${VCS_ARGS_LOG:?}"
printf '%s\n' "$@" >> "${VCS_ARGS_LOG}"

log_file=""
cm_dir=""
fsdb_file=""
prev=""

for arg in "$@"; do
  case "${prev}" in
    -l) log_file="${arg}" ;;
    -cm_dir) cm_dir="${arg}" ;;
  esac
  prev="${arg}"

  case "${arg}" in
    +FSDB_FILE=*) fsdb_file="${arg#+FSDB_FILE=}" ;;
  esac
done

[[ -n "${log_file}" ]] || { echo "missing -l log path" >&2; exit 2; }
mkdir -p "$(dirname "${log_file}")"

if [[ "${STUB_UVM_ERROR:-0}" == "1" ]]; then
  {
    echo "UVM_ERROR test.sv(1) @ 0: reporter [SCB] forced failure"
    echo "UVM_INFO test.sv(2) @ 0: reporter [SCB_FCOV] functional_coverage=10.00% samples=1"
    echo "UVM_INFO test.sv(3) @ 0: reporter [SCB_BUCKET2] legal_wr=1 legal_rd=0 illegal_wr=0 illegal_rd=0 ack_all=1 ack_nack=0 rd_match=0"
  } > "${log_file}"
else
  {
    echo "UVM_INFO test.sv(1) @ 0: reporter [SCB_FCOV] functional_coverage=10.00% samples=1"
    echo "UVM_INFO test.sv(2) @ 0: reporter [SCB_BUCKET] addr_low=1 addr_mid=0 addr_high=0 len_single=1 len_short=0 len_burst=0 illegal_read=0"
    echo "UVM_INFO test.sv(3) @ 0: reporter [SCB_BUCKET2] legal_wr=1 legal_rd=0 illegal_wr=0 illegal_rd=0 ack_all=1 ack_nack=0 rd_match=0"
  } > "${log_file}"
fi

if [[ -n "${cm_dir}" ]]; then
  mkdir -p "${cm_dir}.vdb"
fi

if [[ -n "${fsdb_file}" ]]; then
  mkdir -p "$(dirname "${fsdb_file}")"
  echo "stub fsdb" > "${fsdb_file}"
fi

exit "${STUB_VCS_RC:-0}"
STUB_VCS

cat > "${FAKE_BIN}/urg" <<'STUB_URG'
#!/bin/bash
set -euo pipefail

report_dir=""
prev=""
for arg in "$@"; do
  if [[ "${prev}" == "-report" ]]; then
    report_dir="${arg}"
  fi
  prev="${arg}"
done

if [[ -n "${report_dir}" ]]; then
  mkdir -p "${report_dir}"
fi
STUB_URG

chmod +x "${FAKE_BIN}/vcs" "${FAKE_BIN}/urg"

PASS_RESULTS="${TMP_ROOT}/pass_results"
PASS_ARGS="${TMP_ROOT}/pass_vcs.args"
if ! (
  cd "${TMP_ROOT}"
  PATH="${FAKE_BIN}:${PATH}" \
  RESULT_BASE="${PASS_RESULTS}" \
  FSDB_ENABLE=0 \
  VCS_ARGS_LOG="${PASS_ARGS}" \
  bash "${SCRIPT_DIR}/run_uvm.sh" i2c_smoke_test 123
); then
  fail "run_uvm failed for a clean stubbed run"
fi

filelist_arg=$(awk 'prev=="-f"{print; exit} {prev=$0}' "${PASS_ARGS}")
[[ -n "${filelist_arg}" ]] || fail "vcs was not passed a filelist"
[[ -f "${filelist_arg}" ]] || fail "generated filelist does not exist: ${filelist_arg}"
grep -Fq "${REPO_ROOT}/sim/uvm/if/i2c_if.sv" "${filelist_arg}" || \
  fail "generated filelist does not contain checkout-absolute source paths"
if grep -Fq "/home/huhh/uvm_auto_regression" "${filelist_arg}"; then
  fail "generated filelist leaked developer-local absolute paths"
fi

FAIL_RESULTS="${TMP_ROOT}/fail_results"
FAIL_ARGS="${TMP_ROOT}/fail_vcs.args"
if (
  cd "${TMP_ROOT}"
  PATH="${FAKE_BIN}:${PATH}" \
  RESULT_BASE="${FAIL_RESULTS}" \
  FSDB_ENABLE=0 \
  STUB_UVM_ERROR=1 \
  VCS_ARGS_LOG="${FAIL_ARGS}" \
  bash "${SCRIPT_DIR}/run_uvm.sh" i2c_smoke_test 456
); then
  fail "run_uvm returned success despite UVM_ERROR in the log"
fi

VERDI_ROOT="${TMP_ROOT}/verdi"
mkdir -p "${VERDI_ROOT}/share/PLI/VCS/LINUX64"
touch "${VERDI_ROOT}/share/PLI/VCS/LINUX64/novas.tab"
touch "${VERDI_ROOT}/share/PLI/VCS/LINUX64/pli.a"

FSDB_RESULTS="${TMP_ROOT}/fsdb_results"
for idx in 1 2; do
  if ! (
    cd "${TMP_ROOT}"
    PATH="${FAKE_BIN}:${PATH}" \
    RESULT_BASE="${FSDB_RESULTS}" \
    FSDB_ENABLE=1 \
    FSDB_REQUIRE=1 \
    VERDI_HOME="${VERDI_ROOT}" \
    VCS_ARGS_LOG="${TMP_ROOT}/fsdb_${idx}.args" \
    bash "${SCRIPT_DIR}/run_uvm.sh" i2c_smoke_test 777
  ); then
    fail "run_uvm failed for stubbed FSDB run ${idx}"
  fi
done

pass_wave_dir="${FSDB_RESULTS}/i2c_smoke_test/wave/pass"
shopt -s nullglob
fsdb_files=("${pass_wave_dir}"/*.fsdb)
shopt -u nullglob
[[ "${#fsdb_files[@]}" -eq 2 ]] || fail "expected 2 unique PASS FSDBs, found ${#fsdb_files[@]}"
[[ ! -e "${pass_wave_dir}/i2c_smoke_test.fsdb" ]] || fail "PASS FSDB used non-unique test-name target"

echo "[PASS] run_uvm stub behavior"
