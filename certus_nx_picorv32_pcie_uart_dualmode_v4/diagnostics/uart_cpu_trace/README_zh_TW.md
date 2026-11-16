# CPU 與 UART 整合診斷

前一階段板端 UART 硬體回送已通過：有 UART RX DIAG、A 可回傳、LED1/2/3 亮、LED4/7 熄。本階段保留原 PicoRV32、RAM、UART、AXI/I2C 與 interactive.hex，利用額外 LED 事件找出資料停在哪一步。

## 已找到的 LED 反相錯誤

原 standalone top 的 LED_ACTIVE_LOW 是 32-bit integer，卻使用「{8{LED_ACTIVE_LOW}}」產生 LED mask。設為 1 時，256-bit 串接截取成 8 bits 後是 0x01，只有 LED0 反相，LED1～7 沒有反相。對低電位點亮的 LED，CPU trap=0 也可能讓 LED7 亮。

已改用「{8{LED_ACTIVE_LOW != 0}}」，先轉成 1-bit 再複製，值 1 時 mask 正確為 0xFF。正式 standalone top 與本診斷 top 都修正。這可解釋先前 LED7 與持續 heartbeat 的矛盾，只修正顯示，不等於已解決 UART 輸入問題。

## 加入 Radiant

1. 從原本「含 CPU、會顯示 osfp>」的工程另存診斷副本，保留原 FPGA、系統 clock/reset、PDC、PicoRV32 與所有原 RTL。不要從前一階段的純 UART 回送工程開始。
2. 加入本資料夾的三份 RTL：
   - certus_nx_picorv32_uart_cpu_diag_top.sv
   - pcie_i2c4_top_cpu_diag_fabric.sv
   - picorv32_cpu_axil_uart_diag.v
3. Top Module 改為 **certus_nx_picorv32_uart_cpu_diag_top**。外部 ports 名稱與原 standalone top 相同；核對原 PDC 的外部腳位約束是否套用，任何舊內部階層約束需配合新 top 調整。
4. 仍使用原 rtl/soc 的 uart_rx_byte.v 與 uart_tx_mmio.v，各只加入一份。原正常模組與新診斷模組名稱不同，可並存。
5. 設定 CLK_HZ 為真實系統 clock（預設 125000000），BAUD=115200，LED_ACTIVE_LOW=1，FIRMWARE_HEX="firmware/interactive.hex"（最後兩者預設已符合使用者設定）。I2C_CLK_DIV 與原 standalone top 相同，預設 625。
6. 重新 synthesis、map、PAR、bitstream 並燒錄。請記錄此工程與原 CPU 工程的實際 clock、worst slack／WNS、TNS／未滿足路徑數；負 slack 代表該時序要求未達成。修改 CLK_HZ 參數本身不會改變實體 clock。

本版開機仍顯示原 CLI 與 osfp>，不插入額外 UART banner，以保持受測 UART／韌體路徑。到 prompt 後 LED6 應亮，可用來辨識診斷 LED 配置；reset 後不要在開機訊息尚未完成前打字。

## 測試與 LED 意義

先記錄 osfp> 出現後、尚未打字時 LED0～7 狀態，再慢速按一次 **A**（先不要按 Enter），觀察有無回顯並記錄 LED。LED1～6 是事件保持，發生後保持到 reset；它們不代表事件目前仍持續發生。

| LED | 診斷意義 |
|---|---|
| 0 | 原韌體寫入的 heartbeat，正常約每 250 ms 切換；不是上一版的獨立硬體 heartbeat |
| 1 | 同步後的 RX 曾出現低電位 |
| 2 | UART RX 曾有有效 byte（rx_valid） |
| 3 | CPU 曾完成讀 RX data：0x10000018 |
| 4 | 首次讀 RX data 後，曾有資料交給 UART TX；不保證內容就是同一個 A |
| 5 | 曾有 RX overrun |
| 6 | CPU 曾完成讀 RX status：0x1000001C；不保證目前仍持續輪詢 |
| 7 | 直接顯示 cpu_trap，不與軟體 LED7 位元 OR |

正常且沒有開機雜訊的預期：

- 按鍵前：LED0 規律閃爍、LED6 亮，LED1～5 與 LED7 熄滅。
- 按 A 後：A 回顯、LED1～4 與 LED6 亮、LED5/7 熄滅、LED0 繼續閃爍。

## 判讀

| 結果 | 下一步 |
|---|---|
| LED6 未亮 | CPU 尚未完成讀 RX status。確認 prompt 完整、診斷 top 已燒入，並觀察 trap／PC／memory bus |
| LED1 亮、LED2 未亮 | 訊號已到診斷邏輯，但未形成有效 UART byte；看 RX 波形、clock／BAUD、reset 與此工程 timing |
| LED2 亮、LED3 未亮 | RX 收妥資料，但 CPU 未完成讀 data。觀察 RXSTATUS 回傳值、PC、mem_valid／ready |
| LED3 亮、LED4 未亮 | CPU 已讀 data，但沒有後續 UART TX handshake；觀察讀回字元、程式分支與 tx_ready |
| LED4 亮、A 沒回顯 | CPU 讀取後曾輸出，但內容／接收顯示不符；比對讀到的 byte、送出的 byte 與 TX 波形 |
| LED5 亮 | 已溢位；reset 後等完整 prompt 再單按一次 A，並記錄溢位出現的時間 |
| LED7 亮 | raw cpu_trap 為 1。以 trap 上升沿擷取 PC、指令與 memory transaction |
| LED7 亮且 LED0 長時間持續閃爍 | 對官方 PicoRV32 不符合 trap 後停止執行的行為；核對同一次測試的 LED mapping、reset、實際燒錄 RTL／CPU 版本，直接量測訊號 |
| 全部正常且 A 回顯 | 新診斷版能工作；比對原工程的 RTL／HEX、Top、參數、實際燒錄版本與 timing，不能直接認定原韌體有 bug |

請回報 **按 A 前／後的 LED0～7、有無 A 回顯**，以及原 CPU 工程的實際 clock 與 worst slack／WNS。

## 可用的 Reveal 觀測點

從新 top 的 u_soc.u_cpu_subsystem 觀察 cpu_trap、rx_valid、rx_data、diag_rx_read_done、diag_rx_status_done、tx_fire、mem_valid、mem_ready、mem_addr、mem_rdata。若使用官方 PicoRV32，可觀察 u_cpu.reg_pc；指令名稱依實際 CPU RTL 版本核對。

## 修改範圍與驗證限制

三份檔案複製自 a9150604/sun commit 85ecea1ba67bf9a05e400c4ac9f064cfd222bcf5 的原 SoC。模組改名；CPU wrapper 加入同步與事件保持，將實體 LED 改為診斷配置。IO_LED (0x10000010) 的 CPU 回讀仍保留原本 normal_leds，CPU／RAM／UART／AXI 交易與韌體不作功能修改。診斷 top 的預設 LED 極性與 firmware 路徑配合使用者板端設定，並修正上述 integer LED mask 錯誤。

新增觀察邏輯仍會影響扇出、資源配置與實體 timing；模擬通過不等於使用者板端 synthesis／PAR／timing closure 或功能已通過。原版在先前的官方 PicoRV32 模擬已能收字元，本階段目的是取得板端證據，不是宣告已修復根因。

驗證結果：

- UART／MMIO／事件保持：40 項檢查通過，使用 CPU bus stub；包含真實 UART RX 注入、模擬 TX 線解碼、已完成讀取才記錄、status 不 pop、data 讀取 pop、溢位、reset，以及 IO_LED 原 readback／software LED7 與 raw trap 分離。
- LED 極性：1024 項檢查通過，涵蓋所有 256 種 led_raw、active_low=0/1、正式與診斷兩個 top。明確重現舊 mask=0x01、修正 mask=0xFF。
- 真 CPU＋原 HEX 快速整合回歸：125 MHz、1,000,000 baud。開機到 osfp>；baseline 僅 LED6 亮；serial A 正常回顯且 LED1/2/3/4/6 亮、5/7 熄；再 CR 正常返回 prompt。無 trap／overrun。此項刻意加快 UART 鮑率減少模擬時間，板端預設仍為 115200；TX 文字在 tx_fire 握手點記錄。
- 先前原 UART RX 的 125 MHz／115200 模擬與使用者硬體回送實板已通過。本輪尚未在使用者板上執行 CPU 診斷 top，也未宣稱 Radiant timing 通過。

整合模擬補入官方 PicoRV32 ef203c2b0a3fb793280f5114941416c425c5b461，無法代替核對使用者實際 CPU 檔案；I2C master 三處 enum 三元式僅在模擬相容複本改為等價 if/else，原始設計未修改。

LED 回歸測試在 sim/。安裝 Icarus 後，從專案根目錄執行 bash diagnostics/uart_cpu_trace/sim/run_led_polarity_test.sh；此測試以 stub fabric 驗證兩個真 top 的 LED 輸出，不執行 CPU。sim/ 內檔案不用加入 Radiant synthesis。
