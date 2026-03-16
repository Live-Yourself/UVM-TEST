set -euo pipefail

TEST_NAME=${1:-i2c_smoke_test}
CDIR=$(pwd)

FSDB_PATH="$CDIR/../sim_result/${TEST_NAME}/wave/${TEST_NAME}.fsdb"

CMD=(
  verdi
  -sv
  -ntb_opts uvm-1.2
  -f filelist_vdi.f
  -top tb_uvm_top
)

if [[ -f "$FSDB_PATH" ]]; then
  CMD+=( -ssf "$FSDB_PATH" )
fi

"${CMD[@]}"
