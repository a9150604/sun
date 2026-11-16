#!/usr/bin/env bash
set -euo pipefail
script_dir=$(cd "$(dirname "$0")" && pwd)
diag_dir=$(cd "$script_dir/.." && pwd)
project_dir=${PROJECT_DIR:-"$diag_dir/../.."}
iverilog_bin=${IVERILOG_BIN:-iverilog}
vvp_bin=${VVP_BIN:-vvp}
iverilog_flags=()
if [[ -n ${IVERILOG_BASE:-} ]]; then
  iverilog_flags=(-B "$IVERILOG_BASE")
fi
build_dir=$(mktemp -d "${TMPDIR:-/tmp}/led-polarity.XXXXXX")
trap 'rm -rf "$build_dir"' EXIT
"$iverilog_bin" "${iverilog_flags[@]}" -g2012 -s tb_led_polarity \
  -o "$build_dir/test.vvp" \
  "$script_dir/tb_led_polarity.sv" \
  "$project_dir/rtl/soc/certus_nx_picorv32_uart_standalone_top.sv" \
  "$diag_dir/certus_nx_picorv32_uart_cpu_diag_top.sv"
"$vvp_bin" "$build_dir/test.vvp"
