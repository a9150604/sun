# Open Questa in package root (directory containing firmware.hex).
# 1) First run scripts/get_picorv32.ps1 (or copy upstream picorv32.v).
# 2) Precompiled firmware.hex already supplied; can rebuild it.
if {![file exists third_party/picorv32.v]} { error "Missing third_party/picorv32.v" }
vlib work
vlog -sv +acc \
  rtl/user_design/i2c4_pkg.sv \
  rtl/user_design/i2c_master_byte.sv \
  rtl/user_design/i2c_device_ctrl.sv \
  rtl/user_design/axil_i2c4_regs.sv \
  third_party/picorv32.v \
  rtl/soc/native_to_axil_master.v \
  rtl/soc/uart_tx_mmio.v \
  rtl/soc/msi_source_controller.v \
  rtl/soc/axil_master_mode_mux.sv \
  rtl/soc/picorv32_cpu_axil_uart.v \
  rtl/soc/pcie_i2c4_top_cpu_fabric.sv \
  rtl/soc/certus_nx_picorv32_qsfp_standalone_top.sv \
  sim/i2c_slave_model.sv sim/tb_soc.sv
vsim -voptargs=+acc work.tb_soc
run -all
