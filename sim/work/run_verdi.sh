#!/bin/bash
set -euo pipefail

# Usage:
#   bash run_verdi.sh [UVM_TESTNAME]
# Example:
#   bash run_verdi.sh i2c_smoke_test

TEST_NAME=${1:-i2c_smoke_test}
SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
CDIR="$SCRIPT_DIR"

FSDB_PATH="$CDIR/../sim_result/${TEST_NAME}/wave/${TEST_NAME}.fsdb"
FILELIST_PATH="$CDIR/uvm_filelist.f"

if [[ ! -f "$FILELIST_PATH" ]]; then
  echo "[ERROR] filelist not found: $FILELIST_PATH"
  exit 1
fi

# Important:
# 1) Must run from sim/work so relative paths in uvm_filelist.f are valid.
# 2) Must pass -ntb_opts uvm-1.2 so uvm_pkg/uvm_macros.svh can be resolved.

CMD=(
  verdi
  -sv
  -ntb_opts uvm-1.2
  -f "$FILELIST_PATH"
  -top tb_uvm_top
)

if [[ -f "$FSDB_PATH" ]]; then
  CMD+=( -ssf "$FSDB_PATH" )
fi

"${CMD[@]}"
