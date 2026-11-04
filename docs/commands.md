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
| `task ps-all` | **查看全部容器 (All Containers)** | 包含已停止與一次性容器（`init-permissions`、`setup`）。 |
| `task stats` | **資源使用量 (Resource Usage)** | 顯示本專案容器目前的 CPU 與記憶體用量。 |
| `task validate` | **設定驗證 (Validate)** | 驗證解析後的 Compose 設定；需先執行 `task init`。 |
| `task lab:verify` | **綜合驗證 (Verify)** | 依序執行 `validate`、`doctor`、`ps-all`、`stats`。 |
| `task` / `task --list` | **查看指令清單 (List Tasks)** | 列出所有可用指令。 |

## 4. 按需啟停 (Service Groups & Modes)

不需要全部服務時，可只啟動需要的群組，以減少記憶體用量。群組與組合定義在 `scripts/lab.sh`，執行 `task lab:list` 可查看最新清單。

### 4.1 指令

| 指令 | 說明 |
| --- | --- |
| `task lab:list` | 列出群組、組合與每次都會保留的群組。 |
| `task lab:up G="sql cache"` | **累加啟動**指定群組，已在執行的服務不受影響。 |
| `task lab:api` / `lab:api-full` / `lab:search` / `lab:cache` / `lab:monitor` | **累加啟動**預先定義的組合。 |
| `task lab:switch MODE=api` | **切換**：停止不在組合內的服務，再啟動組合。MODE 錯誤時直接失敗，不會停止任何服務。 |
| `task lab:stop` | 停止全部服務，**保留容器與資料**（不同於 `task down` 會移除容器）。 |
| `task lab:mem G="sql cache"` / `task lab:mem MODE=api` | 計算記憶體 Limit 總額，並與 Docker 可用記憶體比較；不帶參數時計算全部服務。 |

### 4.2 群組

| 群組 | 服務 | 最小記憶體 |
| --- | --- | ---: |
| `sql` | SQL Server | 2048 MiB |
| `cache` | Redis | 128 MiB |
| `cache-ui` | RedisInsight、Redis Exporter | 288 MiB |
| `mq` | RabbitMQ | 512 MiB |
| `mqtt` | Mosquitto | 32 MiB |
| `search` | Elasticsearch | 1536 MiB |
| `search-ui` | Kibana（會自動帶起 `search`） | 1024 MiB |
| `storage` | Azurite | 192 MiB |
| `auth` | Keycloak | 1360 MiB |
| `logs` | Seq | 768 MiB |
| `mail` | Mailpit | 64 MiB |
| `monitor` | Uptime Kuma、Dozzle（含 Socket Proxy） | 352 MiB |
| `websearch` | SearXNG | 256 MiB |
| `dev` | VS Code 編輯容器 | 1024 MiB |

### 4.3 組合

| 組合 | 群組 | 記憶體（含 `dev`） |
| --- | --- | ---: |
| `api` | `sql` `cache` `mq` `mail` | 3776 MiB |
| `api-full` | `api` + `auth` `logs` | 5904 MiB |
| `search` | `search` `search-ui` | 3584 MiB |
| `cache` | `cache` `cache-ui` | 1440 MiB |
| `monitor` | `logs` `monitor` | 2144 MiB |
| 全部（`task up`） | 全部群組 | 9584 MiB |

> `dev`（VS Code 編輯容器）預設在每次啟動與切換時都會保留，確保隨時可以 Attach。若不需要，可在指令前加上 `LAB_KEEP=`，例如 `LAB_KEEP= task lab:api`。

### 4.4 範例

```bash
# 只啟動 .NET API 需要的服務
task lab:api

# 在原有服務上，再加入 Elasticsearch 與 Kibana
task lab:search

# 只保留監控相關服務，釋放其他服務的記憶體
task lab:switch MODE=monitor

# 停止全部服務，保留資料
task lab:stop
```

## 5. 記憶體配置 (Memory Limits)

每個服務的 Memory Limit 都在 `.env` 以 `*_MEM_LIMIT` 設定，預設值的依據見 5.1。負載較高時直接調高 `.env` 的數值即可，不需修改 `compose.yml`。

- `memswap_limit` 與 Memory Limit 相同，記憶體不足時會被 OOM Kill，而不是改用 Swap 默默變慢。
- WSL2 預設只分配主機 50% 的記憶體給 Docker。若 `task lab:mem` 顯示總額超過 Docker 可用記憶體，請調高 `%UserProfile%\.wslconfig` 的 `memory=`，或降低 `.env` 的數值。
- `task doctor` 會檢查全部服務的 Limit 總額是否超過 Docker 可用記憶體。

### 5.1 預設值依據

有官方最低規格的服務依官方規格設定；官方只提供正式環境規格、或沒有公布規格的服務，採本機低負載的最小值。官方文件查閱日期：2026-11-04。

| 服務 | 預設 Limit | 官方規格 | 依據 |
| --- | ---: | --- | --- |
| SQL Server | 2048 MiB | 最低 2 GB | [Microsoft Learn](https://learn.microsoft.com/en-us/sql/linux/install-upgrade/setup?view=sql-server-ver17#system-requirements) |
| Keycloak | 1360 MiB | 基本用量 1250 MB，Limit 範例 1360 MB | [Keycloak Sizing](https://www.keycloak.org/high-availability/multi-cluster/concepts-memory-and-cpu-sizing) |
| VS Code 編輯容器 | 1024 MiB | 最低 1 GB，建議 2 GB | [VS Code Dev Containers](https://code.visualstudio.com/docs/devcontainers/containers#_system-requirements) |
| Elasticsearch | 1536 MiB | 無最低規格；Heap 不超過容器記憶體 50%，官方 Docker 範例使用 `-m 1GB`。實測 1 GB 用量達 98%，調為 1536 MiB，Heap 維持 512 MB | [JVM settings](https://www.elastic.co/docs/reference/elasticsearch/jvm-settings)、[Docker](https://www.elastic.co/docs/deploy-manage/deploy/self-managed/install-elasticsearch-docker-basic) |
| Kibana | 1024 MiB | 無一般最低規格（2 GB 僅針對付費進階功能） | [Kibana memory](https://www.elastic.co/docs/deploy-manage/production-guidance/kibana-configure-memory) |
| RabbitMQ | 512 MiB | 正式環境 4 GiB；節點需隨時保留至少 256 MiB 可用 | [Production Checklist](https://www.rabbitmq.com/docs/production-checklist) |
| Seq | 768 MiB | 輕量負載 3.5 GB（以 Windows 主機為例） | [Seq System Requirements](https://datalust.co/docs/system-requirements) |
| 其他服務 | 32–256 MiB | 無官方規格 | Redis、RedisInsight、Azurite、Mosquitto、SearXNG、Uptime Kuma、Dozzle、Mailpit、docker-socket-proxy |
