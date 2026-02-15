# 疑難排解指南 (Troubleshooting Guide)

## 0. 先做快速診斷 (Quick Diagnosis)

遇到問題時，建議先執行以下指令再進行手動排查：

- `task doctor`：檢查 Docker、Compose、`.env`、目錄與寫入權限。
- `task doctor-fix`：在檢查時自動修復核心目錄寫入權限。
- `task ps`：查看服務是否為 `running`/`healthy`。

---

## 常見問題 (Common Issues)

### 1. Volume 出現 "Permission Denied"

- **徵狀：** SQL Server、Mosquitto、RabbitMQ、Seq 等服務無法啟動或存取資料。
- **原因：** Linux/WSL 上的 Docker Volume 需要對應服務 UID/GID；重建或跨機搬移後，`data/log` 目錄權限可能不一致。
- **解決方案（標準流程）：**
  1. 執行 `docker compose run --rm init-permissions`（修復服務資料卷權限）。
  2. 執行 `task restart S=<service-name>`（重啟目標服務）。
  3. 執行 `task ps S=<service-name>` 與 `task compose-logs S=<service-name>` 檢查狀態。
  4. 若是「開發者本機無法編輯檔案」而非服務資料卷問題，再執行 `task doctor-fix`。

### 2. Port 衝突 (Port Conflicts)

- **徵狀：** `Error starting userland proxy: listen tcp4 0.0.0.0:1433: bind: address already in use`
- **原因：** 該 Port 已被其他服務 (或本機執行個體) 佔用。
- **解決方案：**
  1. 停止本機服務 (例如本機 SQL Server)。
  2. 檢查佔用情形：
     - Windows：`netstat -ano | findstr 1433`
     - Linux/WSL：`ss -tunlp | grep :1433`
  3. 必要時修改 `.env` 中的 Port 對應設定。

### 3. 跨平台換行符號與腳本限制 (Cross-Platform EOL & Script Limits)

- **徵狀：** `warning: in the working copy of '...', CRLF will be replaced by LF...`

- **原因與限制：**
  本專案為確保 Shell Scripts (`.sh`) 在 Linux/WSL/Docker 容器內可正確執行，所有文字檔案必須使用 LF (Unix-style) 換行。
  若混用 CRLF，可能出現 `\r: command not found` 等錯誤。

- **解決方案：**
  1. Git 警告代表 `.gitattributes` 正在把 CRLF 轉為 LF，屬於正常行為。
  2. 請勿在專案新增 `.ps1` 腳本，統一使用 `.sh`。
  3. 請確認編輯器行尾為 LF 後再 `git add`、`commit`。

### 4. 設定檔「寫入失敗 / 一直被覆寫」(Write Failed / Overwritten)

- **徵狀：** 編輯 `messaging/mosquitto/volumes/config/entrypoint.sh` 時，出現寫入失敗，或改完很快又被改回去。
- **原因：** 權限修復流程若同時處理 `config` 與 `data/log`，可能把 `config` 檔案擁有者改成服務 UID，導致開發者帳號無法寫入。
- **修正原則：**
  1. `setup/init-permissions/compose.yml` 只處理資料目錄（`data/`、`log/`）。
  2. `config` 下可編輯腳本保留為開發者可寫。
  3. Runtime 檔案（例如 `passwd`）由服務 entrypoint 在容器內修正權限。
- **建議檢查：**
  - `ls -l messaging/mosquitto/volumes/config/entrypoint.sh`
  - 確認 owner 為目前開發者，而非服務 UID（例如 `1883`）。

### 5. 維護後 RabbitMQ 管理指令失效 (Permission Regression)

- **徵狀：** 服務看似正常，但 `docker exec rabbitmq rabbitmqctl ...` 失敗，或提示 cookie 權限錯誤。
- **常見觸發：** 調整 `init-permissions`、手動清理 `messaging/rabbitmq/volumes`、或跨機搬移資料後。
- **確認方式：**
  1. 先檢查狀態：`task ps S=rabbitmq`。
  2. 再檢查 CLI：`docker exec rabbitmq rabbitmqctl list_queues`。
  3. 若 CLI 報權限相關錯誤，視為資料卷權限回歸。
- **標準處理：**
  1. 執行 `docker compose run --rm init-permissions`（修復資料卷 owner/mode）。
  2. 執行 `task restart S=rabbitmq`。
  3. 再次驗證 `rabbitmqctl` 是否可用。

### 6. 維護後 Mosquitto 啟動失敗 (Template/Config Regression)

- **徵狀：** Mosquitto 重啟循環，或日誌顯示找不到 `entrypoint.sh` / config 檔案。
- **常見觸發：** 清空 `volumes`、修改初始化流程、或調整模板路徑後未重新生成執行時檔案。
- **確認方式：**
  1. `task ps S=mosquitto` 查看是否持續重啟。
  2. `task compose-logs S=mosquitto` 檢查缺檔訊息。
  3. `ls -l messaging/mosquitto/volumes/config` 確認 `entrypoint.sh`、`mosquitto.conf` 是否存在。
- **標準處理：**
  1. 執行 `task init`（由 `scripts/templates/` 重建 `volumes/config`）。
  2. 執行 `task restart S=mosquitto`。
  3. 重新檢查 `ps` 與 `compose-logs`。

---

## 診斷指令 (Diagnostic Commands)

關於檢查服務狀態、閱讀日誌等操作，請參閱 [**指令速查 (Commands)**](commands.md)。
