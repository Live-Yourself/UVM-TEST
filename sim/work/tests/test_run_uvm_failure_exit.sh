#!/bin/bash
set -euo pipefail

TEST_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
WORK_DIR=$(cd "${TEST_DIR}/.." && pwd)
SIM_DIR=$(cd "${WORK_DIR}/.." && pwd)
REPO_ROOT=$(cd "${SIM_DIR}/.." && pwd)

TMP_DIR=$(mktemp -d)
RESULT_DIR="${SIM_DIR}/sim_result"
BACKUP_DIR="${TMP_DIR}/sim_result_backup"
FAKE_BIN="${TMP_DIR}/bin"
VCS_ARGS_FILE="${TMP_DIR}/vcs_args.txt"
VCS_LOG_TARGET_FILE="${TMP_DIR}/vcs_log_path.txt"

restore_results() {
  rm -rf "${RESULT_DIR}"
  if [[ -d "${BACKUP_DIR}" ]]; then
    cp -a "${BACKUP_DIR}" "${RESULT_DIR}"
  fi
  rm -rf "${TMP_DIR}"
}
trap restore_results EXIT

if [[ -d "${RESULT_DIR}" ]]; then
  cp -a "${RESULT_DIR}" "${BACKUP_DIR}"
fi

mkdir -p "${FAKE_BIN}"
cat > "${FAKE_BIN}/vcs" <<'EOF'
#!/bin/bash
set -euo pipefail

printf '%s\n' "$@" > "${VCS_ARGS_FILE}"

log_file=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    -l)
      shift
      log_file="${1:-}"
      ;;
  esac
  shift || true
done

if [[ -n "${log_file}" ]]; then
  mkdir -p "$(dirname "${log_file}")"
  {
    echo "UVM_ERROR @ 0: uvm_test_top [FAKE_FAIL] forced failure"
    echo "functional_coverage=0.00% samples=1"
  } > "${log_file}"
  printf '%s\n' "${log_file}" > "${VCS_LOG_TARGET_FILE}"
fi

exit 7
EOF
chmod +x "${FAKE_BIN}/vcs"

export PATH="${FAKE_BIN}:${PATH}"
export VCS_ARGS_FILE
export VCS_LOG_TARGET_FILE

set +e
(cd "${REPO_ROOT}" && FSDB_ENABLE=0 bash "${WORK_DIR}/run_uvm.sh" runner_failure_exit_test 123)
rc=$?
set -e

if [[ "${rc}" -eq 0 ]]; then
  echo "[FAIL] run_uvm.sh returned success for a failing VCS run"
  exit 1
fi

run_db="${RESULT_DIR}/regression_runs.csv"
last_row=$(awk -F, '$2=="runner_failure_exit_test"{row=$0} END{print row}' "${run_db}")
if [[ "${last_row}" != *",FAIL,"* ]]; then
  echo "[FAIL] regression DB did not record the fake run as FAIL"
  echo "       row=${last_row}"
  exit 1
fi

filelist_arg=$(awk 'prev=="-f"{print; exit} {prev=$0}' "${VCS_ARGS_FILE}")
if [[ -z "${filelist_arg}" || ! -f "${filelist_arg}" ]]; then
  echo "[FAIL] VCS did not receive a generated filelist"
  echo "       filelist=${filelist_arg}"
  exit 1
fi

if [[ "${filelist_arg}" != "${RESULT_DIR}/runner_failure_exit_test/misc/work_"*"/filelist_abs.f" ]]; then
  echo "[FAIL] generated filelist was not placed in the per-run work directory"
  echo "       filelist=${filelist_arg}"
  exit 1
fi

if awk 'index($0, "/home/huhh/uvm_auto_regression"){bad=1} END{exit bad ? 0 : 1}' "${filelist_arg}"; then
  echo "[FAIL] generated filelist still contains developer-local absolute paths"
  exit 1
fi

if ! awk -v root="${REPO_ROOT}" 'index($0, root "/sim/uvm/if/i2c_if.sv"){found=1} END{exit found ? 0 : 1}' "${filelist_arg}"; then
  echo "[FAIL] generated filelist does not point at this checkout"
  exit 1
fi

echo "[PASS] run_uvm failure exit and filelist path handling"
