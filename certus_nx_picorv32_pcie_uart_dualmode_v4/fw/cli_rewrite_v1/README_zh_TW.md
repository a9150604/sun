# OSFP CLI REWRITE v1

這是依原 interactive CLI 的命令功能，從原始碼重新實作的獨立韌體。原 interactive.hex、既有 v6 韌體與 RTL 保持原樣。

可直接使用的映像：本專案 firmware/osfp_cli_rewrite_v1.hex。

## Radiant 使用

1. 沿用目前可燒錄的含 PicoRV32 工程與原 PDC／clock／reset。支援 certus_nx_picorv32_uart_standalone_top 及 certus_nx_picorv32_uart_cpu_diag_top 的共通 MMIO；不需加入新的 RTL。
2. 將 FIRMWARE_HEX 設為 **firmware/osfp_cli_rewrite_v1.hex**，確認 synthesis 能找到檔案。原始碼資料夾中的 C／S／Python 是重建工具，Radiant 使用產生好的 HEX。
3. 系統仍需 32 KiB RAM；Top 的 CLK_HZ 必須符合實際 clock。韌體會讀取 IO_CLK 計算 heartbeat 與 timeout。115200 鮑率由原 UART RTL／Top 設定，不由此 HEX 改變。
4. 重新 synthesis、map、PAR、產生並燒錄 bitstream。HEX 是 RAM 初始化內容，會隨新 bitstream 載入。
5. Tera Term 設為 115200、8N1、Flow control=None、local echo 關閉。正確新版本開機標示：

       OSFP CLI REWRITE v1 (RV32I WORD IO)
       Type help for commands. Numbers are hex; delay is decimal ms.
       osfp>

若繼續使用 CPU 診斷 Top，LED 仍是該 Top 的事件配置；選正式 standalone Top 時，LED0 是 firmware heartbeat，其餘是原測試狀態。低電位點亮的板請維持 LED_ACTIVE_LOW=1，並使用已修正 LED mask 的 Top。

若 Enter 有新的 prompt，但字母沒有顯示或命令沒有結果，可使用獨立的 [RXTRACE 輸入觀測版](RXTRACE_zh_TW.md) 取得讀到的原始字元。一般版 HEX 保持不變。

## 首次板端測試

先單按 A，應立即回顯 A；再按 Enter 會回覆 ERR unknown command 並重新顯示 osfp>。接著測試：

    status
    help

空白 Enter 也會換行並重印 prompt。Backspace 與 Delete 都會在畫面刪除上一字元；CR、LF、CRLF 皆支援，CRLF 只執行一次。

## 命令

除 delay 使用十進位毫秒外，數值皆為十六進位，可加 0x 前綴。命令使用小寫。

| 命令 | 功能／範圍 |
|---|---|
| help | 顯示命令 |
| status | local owner、channel、地址、資料、IRQ、clock、timeout、RX／掉字計數 |
| id | 讀取 AXI ID 與版本，需 CPU 擁有 I2C |
| mode cpu / mode pcie | 要求切換 I2C AXI owner；250 ms 等待期限 |
| ch 0..3 | 選擇 channel |
| dev 01..7F | 設定該 channel 的 7-bit I2C 地址 |
| reg 00..FF / data 00..FF | 選擇預設 register／data |
| read [reg] | Direct Read |
| unlock / lock | 解鎖／鎖定寫入；reset 後預設鎖定 |
| write [reg] [data] | Direct Write，需先 unlock |
| writeverify [reg] [data] | 讀原值、測試寫入、讀回、恢復並驗證原值 |
| pollset <slot> <reg> | slot 0..7 的輪詢 register |
| pollgap <hex> | gap 0000..FFFF |
| poll | 執行兩次 index wrap 的 poll cycle check，讀出八組 shadow |
| timeout <hex ms> | Direct 操作期限 0A..1388（10..5000 ms） |
| delay <decimal ms> | 等待 0..600000 ms，期間仍接收 UART 與維持 heartbeat |

預設 channel=0、device=50、register=00、data=00、direct timeout=500 ms、poll gap=1000（十進位）、poll register=00..07。poll 使用固定 2000 ms 期限。

Write 與 Writeverify 僅適用於已確認可讀寫、可恢復的普通 register；維持原專案的 7E／7F bank/page 選擇寫入限制。Writeverify 若嘗試過測試寫入，後續即使失敗仍會嘗試恢復，並另列 restore_rc。

Poll 的 index wrap 與 sticky AUTOVALID 只能提供循環進展資訊，無法保證每個 shadow 新鮮或每個 slot ACK。輸出不會把每個 slot 標成獨立 PASS。控制器 timeout 也無法解除 AXI transaction 本身的硬體 stall。

## 新實作

- 全新 startup、platform、UART queue、command parser 與 I2C driver，不呼叫原 interactive 韌體程式。
- RV32I／ilp32，不需要 M 或 C 指令擴充；輸入字元與狀態儲存在 uint32_t 陣列／變數。
- 所有資料讀寫為對齊 32-bit LW／SW；文字 byte 由 volatile aligned LW 加位移取出，不使用 LB／LBU／LH／LHU／SB／SH。
- 所有 literal 輸出均有明確長度；輸入 token 以位置與長度表示，不用 NUL 掃描。
- 開機不存取 AXI／I2C，只初始化軟體地址；boot、echo、help、status 主要依賴 local MMIO。
- TX 等待期間持續服務 RX，把收到的字元移入 127 字元可用的軟體 ring。
- 每行最多 96 個字元。過長行整行丟棄，不執行截斷命令；硬體 overrun 或 queue drop 會清除受損輸入並要求重新按 Enter。
- 啟動時設定 SP=0x8000 與 GP，按 word 清除 BSS；linker 保留至少 4 KiB stack。
- 所有可變設定由啟動程式重新初始化；即使只按 CPU Reset、RAM 未重新載入 HEX，也會恢復預設值與寫入鎖定。

## 原始碼與建置

需要 Python 3，以及支援 RV32I／ilp32 的 GNU RISC-V bare-metal GCC/binutils（例如 riscv64-unknown-elf-* 或 riscv-none-elf-*）。從專案根目錄執行：

    python fw/cli_rewrite_v1/build.py

工具不在 PATH 時：

    python fw/cli_rewrite_v1/build.py --cc /path/to/riscv64-unknown-elf-gcc

Windows 也可指定 riscv-none-elf-gcc.exe 的完整路徑。腳本會找同一套 objcopy、objdump、nm 與 size；可用 --help 查看個別 override。編譯時會稽核實際 .text：若出現非 RV32I、M／C 或 byte／halfword 記憶體指令就拒絕產生 release HEX。

產出：

- firmware/osfp_cli_rewrite_v1.hex：8192 行、每行 32-bit little-endian word，共 32 KiB RAM 映像。
- build/cli_rewrite_v1/：ELF、BIN、MAP、disassembly、manifest。
- 本資料夾 release_manifest.json：已提供 HEX 的工具鏈、source hashes、映像 SHA256 與稽核資訊。

## 驗證範圍

- 發布版 HEX SHA256：1030f723833afa74bd3a38060cbb333d14be42d2bf75e04c4a767fcb576cae4e。
- GCC 14.2.0／binutils 2.44；2339 條 RV32I 指令，無 M／C 指令及 byte／halfword load/store，無未解析符號。
- Code 9356 bytes、rodata 1864 bytes、data 0 bytes、BSS 1036 bytes，保留至少 4096 bytes stack。
- 真機器碼＋理想 MMIO 模型：19 組測試通過，包含全部命令、參數錯誤、I2C 模型的讀寫／還原／NACK／timeout／poll、UART 佇列與資料遺失處理，以及保留 RAM 的 warm reset。
- 真 CPU／UART TX 實際串列線解碼：125 MHz／115200 通過新 banner、單 A 在 Enter 前即回顯、Enter 回應與第二 prompt，RX=2、trap=0、無 overrun。
- 125 MHz／1 Mbaud 完整 UART 回歸：634 個解碼字元、7 次 prompt，通過 status、空 Enter、CRLF、BS／DEL；RX=28、trap=0、無 overrun。兩組均核對上述同一個發布 HEX。

重跑軟體模型：

    python fw/cli_rewrite_v1/tests/test_firmware.py

重跑真 CPU／UART 線模擬（需另備官方 PicoRV32 與 Icarus）：

    python fw/cli_rewrite_v1/tests/run_rtl.py --picorv32 third_party/picorv32.v --baud 115200 --smoke
    python fw/cli_rewrite_v1/tests/run_rtl.py --picorv32 third_party/picorv32.v --baud 1000000

RTL 測試採官方 PicoRV32 ef203c2b0a3fb793280f5114941416c425c5b461，僅在暫存模擬複本將 I2C master 三處 enum 三元式改為等價 if/else 以相容 Icarus；原 RTL 不變。

模型不代表真實 I2C 電氣行為。本韌體仍需使用者在實際 Radiant 工程與開發板驗證；重新實作韌體不代表底層 CPU／RAM 實作的所有問題都已解決。
