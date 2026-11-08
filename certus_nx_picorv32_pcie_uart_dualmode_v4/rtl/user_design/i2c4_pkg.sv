`timescale 1ns/1ps
package i2c4_pkg;
  parameter int AXIL_ADDR_W = 16;
  parameter int AXIL_DATA_W = 32;
  parameter int I2C_DEV_NUM = 4;
  parameter int I2C_REG_NUM = 8;
  parameter logic [31:0] ID_VALUE      = 32'h4932_4334; // "I2C4"
  parameter logic [31:0] VERSION_VALUE = 32'h0002_0000; // SystemVerilog version

  typedef enum logic [4:0] {
    I2C_ST_IDLE,
    I2C_ST_START_A,
    I2C_ST_START_B,
    I2C_ST_LOAD_BYTE,
    I2C_ST_BIT_LOW,
    I2C_ST_BIT_HIGH,
    I2C_ST_ACK_LOW,
    I2C_ST_ACK_HIGH,
    I2C_ST_RX_LOW,
    I2C_ST_RX_HIGH,
    I2C_ST_MACK_LOW,
    I2C_ST_MACK_HIGH,
    I2C_ST_RESTART_A,      // Repeated-start prepare: SCL low, SDA released
    I2C_ST_RESTART_B,      // Repeated-start setup:   SCL high, SDA high
    I2C_ST_RESTART_C,      // Repeated-start event:   SCL high, SDA falling
    I2C_ST_STOP_A,
    I2C_ST_STOP_B,
    I2C_ST_DONE
  } i2c_mst_state_e;

  typedef enum logic [2:0] {
    I2C_PH_ADDR_W,
    I2C_PH_REG,
    I2C_PH_WDATA,
    I2C_PH_ADDR_R,
    I2C_PH_RDATA
  } i2c_phase_e;

  typedef enum logic [2:0] {
    DEV_ST_IDLE,
    DEV_ST_GAP,
    DEV_ST_START_AUTO,
    DEV_ST_START_DIR,
    DEV_ST_WAIT,
    DEV_ST_SAVE
  } dev_ctrl_state_e;

  typedef enum logic {
    OP_AUTO = 1'b0,
    OP_DIR  = 1'b1
  } op_src_e;
endpackage
