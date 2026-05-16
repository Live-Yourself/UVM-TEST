#!/bin/bash
set -euo pipefail

TEST_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
SOURCE_WORK=$(cd "${TEST_DIR}/.." && pwd)
TMP_DIR=$(mktemp -d)
trap 'rm -rf "${TMP_DIR}"' EXIT

FAKE_REPO="${TMP_DIR}/repo"
FAKE_WORK="${FAKE_REPO}/sim/work"
FAKE_BIN="${TMP_DIR}/bin"
FAKE_VERDI="${TMP_DIR}/verdi"

mkdir -p \
  "${FAKE_WORK}" \
  "${FAKE_BIN}" \
  "${FAKE_VERDI}/share/PLI/VCS/LINUX64" \
  "${FAKE_REPO}/sim/uvm/if" \
  "${FAKE_REPO}/sim/uvm/item" \
  "${FAKE_REPO}/sim/uvm/seq" \
  "${FAKE_REPO}/sim/uvm/agent" \
  "${FAKE_REPO}/sim/uvm/env" \
  "${FAKE_REPO}/sim/uvm/test" \
  "${FAKE_REPO}/sim/uvm/pkg" \
  "${FAKE_REPO}/sim/tb" \
  "${FAKE_REPO}/rtl" \
  "${TMP_DIR}/outside"

cp "${SOURCE_WORK}/run_uvm.sh" "${SOURCE_WORK}/run_summarize.sh" "${SOURCE_WORK}/filelist.f" "${FAKE_WORK}/"

touch \
  "${FAKE_VERDI}/share/PLI/VCS/LINUX64/novas.tab" \
  "${FAKE_VERDI}/share/PLI/VCS/LINUX64/pli.a" \
  "${FAKE_REPO}/sim/uvm/if/i2c_if.sv" \
  "${FAKE_REPO}/sim/uvm/pkg/i2c_pkg.sv" \
  "${FAKE_REPO}/sim/tb/tb_uvm_top.sv" \
  "${FAKE_REPO}/rtl/scl_sda_filter.v" \
  "${FAKE_REPO}/rtl/i2c_shift_reg.v" \
  "${FAKE_REPO}/rtl/reg_file.v" \
  "${FAKE_REPO}/rtl/i2c_rx_fsm.v" \
  "${FAKE_REPO}/rtl/i2c_slave_top.v"

cat > "${FAKE_BIN}/date" <<'EOF'
#!/bin/bash
case "${1:-}" in
  +%Y%m%d_%H%M%S)
    echo "20260516_200123"
    ;;
  "+%F %T")
    echo "2026-05-16 20:01:23"
    ;;
  *)
    /bin/date "$@"
    ;;
esac
EOF

cat > "${FAKE_BIN}/vcs" <<'EOF'
#!/bin/bash
set -euo pipefail

filelist=""
log_file=""
cm_dir=""
fsdb_file=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    -f)
      filelist="$2"
      shift 2
      ;;
    -l)
      log_file="$2"
      shift 2
      ;;
    -cm_dir)
      cm_dir="$2"
      shift 2
      ;;
    +FSDB_FILE=*)
      fsdb_file="${1#+FSDB_FILE=}"
      shift
      ;;
    *)
      shift
      ;;
  esac
done

if [[ ! -f "${filelist}" ]]; then
  echo "missing generated filelist: ${filelist}" >&2
  exit 10
fi

while IFS= read -r line; do
  [[ -z "${line}" ]] && continue
  if [[ "${line}" == *"/home/huhh/"* ]]; then
    echo "developer-local path leaked into generated filelist: ${line}" >&2
    exit 11
  fi
  if [[ "${line}" == +incdir+* ]]; then
    path="${line#+incdir+}"
  else
    path="${line}"
  fi
  if [[ "${path}" != "${EXPECT_REPO_ROOT}"/* ]]; then
    echo "generated filelist path is not checkout-absolute: ${line}" >&2
    exit 12
  fi
done < "${filelist}"

mkdir -p "$(dirname "${log_file}")"
if [[ -n "${cm_dir}" ]]; then
  mkdir -p "${cm_dir}.vdb"
fi
if [[ -n "${fsdb_file}" ]]; then
  mkdir -p "$(dirname "${fsdb_file}")"
  echo "fake fsdb ${FAKE_VCS_RESULT}" > "${fsdb_file}"
fi

if [[ "${FAKE_VCS_RESULT}" == "pass" ]]; then
  {
    echo "UVM_INFO @ 0: reporter [TEST_DONE] pass"
    echo "functional_coverage=100% samples=1"
  } > "${log_file}"
else
  {
    echo "UVM_ERROR @ 0: reporter [TESTFAIL] injected failure"
    echo "functional_coverage=100% samples=1"
  } > "${log_file}"
fi
EOF

cat > "${FAKE_BIN}/urg" <<'EOF'
#!/bin/bash
exit 0
EOF

chmod +x "${FAKE_BIN}/date" "${FAKE_BIN}/vcs" "${FAKE_BIN}/urg"

run_fake_uvm() {
  local result="$1"
  local fsdb_enable="${2:-0}"
  (
    cd "${TMP_DIR}/outside"
    PATH="${FAKE_BIN}:${PATH}" \
      EXPECT_REPO_ROOT="${FAKE_REPO}" \
      FAKE_VCS_RESULT="${result}" \
      VERDI_HOME="${FAKE_VERDI}" \
      FSDB_ENABLE="${fsdb_enable}" \
      FSDB_REQUIRE="${fsdb_enable}" \
      bash "${FAKE_WORK}/run_uvm.sh" i2c_smoke_test 123
  )
}

if run_fake_uvm fail 0; then
  echo "run_uvm.sh returned success for a log containing UVM_ERROR" >&2
  exit 1
fi

if ! grep -q ',i2c_smoke_test,123,fixed,FAIL,' "${FAKE_REPO}/sim/sim_result/regression_runs.csv"; then
  echo "failed run was not recorded as FAIL" >&2
  exit 1
fi

if ! run_fake_uvm pass 1; then
  echo "run_uvm.sh returned failure for a passing fake simulation" >&2
  exit 1
fi
if ! run_fake_uvm pass 1; then
  echo "second passing run failed" >&2
  exit 1
fi

if ! grep -q ',i2c_smoke_test,123,fixed,PASS,' "${FAKE_REPO}/sim/sim_result/regression_runs.csv"; then
  echo "passing run was not recorded as PASS" >&2
  exit 1
fi

unique_logs=$(awk -F, 'NR>1{logs[$11]=1} END{print length(logs)}' "${FAKE_REPO}/sim/sim_result/regression_runs.csv")
if [[ "${unique_logs}" -ne 3 ]]; then
  echo "same-seed runs reused a log path" >&2
  exit 1
fi

fsdb_count=$(find "${FAKE_REPO}/sim/sim_result/i2c_smoke_test/wave/pass" -maxdepth 1 -name '*.fsdb' | wc -l | tr -d ' ')
if [[ "${fsdb_count}" -ne 2 ]]; then
  echo "passing FSDB files were overwritten" >&2
  exit 1
fi

echo "test_run_uvm.sh: PASS"
