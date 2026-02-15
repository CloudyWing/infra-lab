# 指令參考手冊 (Command Reference)

## 0. 先決條件 (Prerequisite)

本專案使用 [Task](https://taskfile.dev/) 管理所有操作，請確保已安裝 `task` 指令。
若遇到 `CRLF/LF` 或 `\r: command not found` 問題，請先參閱 [疑難排解第 3 節](troubleshooting.md#3-跨平台換行符號與腳本限制-cross-platform-eol--script-limits)。

## 1. 生命週期管理 (Lifecycle Management)

| 指令 | 功能 | 說明 |
| --- | --- | --- |
| `task init` | **初始化環境 (Initialize Environment)** | 建立目錄、網路與機密檔案。**請最先執行此指令。** |
| `task up` | **啟動服務 (Start Services)** | 啟動所有定義的服務。可指定 `SERVICE=name`（或 `S=name`）啟動特定服務。 |
| `task down` | **停止服務 (Stop Services)** | 停止全部服務；可指定 `SERVICE=name`（或 `S=name`）僅停止單一服務。 |
| `task restart` | **重啟服務 (Restart Services)** | 重啟全部服務；可指定 `SERVICE=name`（或 `S=name`）僅重啟單一服務。 |

## 2. 維護操作 (Maintenance)

| 指令 | 功能 | 說明 |
| --- | --- | --- |
| `task clean` | **清理容器 (Clean Containers)** | 移除容器與網路，但**保留資料 Volume**。 |
| `task clean-script-logs` | **清理腳本日誌 (Script Logs)** | 不帶參數刪除全部 `logs/script-*.log`；帶 `DAYS=n`（或 `D=n`）只刪除 n 天前日誌。 |
| `task purge` | **⚠️ 徹底清除 (Purge Everything)** | 銷毀容器、網路及**所有資料**。 |
| `task backup` | **資料備份 (Backup Data)** | 對 SQL Server、Redis 及 **Volumes** 進行快照備份。 |
| `task compose-logs` | **查看容器串流日誌 (Compose Logs)** | 追蹤 `docker compose logs -f`，不加參數會顯示 Dozzle 連結。 |

## 3. 驗證與監控 (Validation & Monitoring)

| 指令 | 功能 | 說明 |
| --- | --- | --- |
| `task smoke` | **全流程冒煙測試 (Smoke Test)** | 一鍵執行 `init/up/ps/backup/down/doctor-fix/doctor`。 |
| `task doctor` | **環境健檢 (Doctor)** | 檢查 `.env`、Docker、Compose include 路徑與核心目錄可寫入權限。 |
| `task doctor-fix` | **健檢並修復 (Doctor Fix)** | 在健檢時自動修復核心目錄不可寫入權限，再次驗證結果。 |
| `task ps` | **查看狀態 (Check Status)** | 顯示全部服務狀態；可指定 `SERVICE=name`（或 `S=name`）僅查看單一服務。 |
| `task` / `task --list` | **查看指令清單 (List Tasks)** | 列出所有可用指令。 |
