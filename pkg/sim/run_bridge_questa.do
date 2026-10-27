# Package root, no PicoRV32 source needed
vlib work
vlog -sv rtl/user_design/i2c4_pkg.sv \
 rtl/user_design/i2c_master_byte.sv \
 rtl/user_design/i2c_device_ctrl.sv \
 rtl/user_design/axil_i2c4_regs.sv \
 rtl/soc/native_to_axil_master.v sim/tb_native_axil_bridge.sv
vsim work.tb_native_axil_bridge
run -all
