# 架構總覽 (Architecture Overview)

## 基礎設施元件 (Infrastructure Components)

## 服務清單 (Service List)

### 基礎設定 (Setup - Foundations)

| 服務 | Port | 說明 |
| ---- | ---- | ---- |
| **Init Permissions** | N/A | 啟動前修正 Volume 權限，確保跨平台可寫入。 |

### 可觀測性 (Observability)

| 服務 | Port | 說明 |
| ---- | ---- | ---- |
| **Seq** | 5340/5341 | 結構化日誌伺服器 (Web/Ingest)。 |
| **Uptime Kuma** | 3001 | 服務監控與警報。 |
| **Dozzle** | 8280 | 容器日誌檢視器。 |

### 核心資料儲存 (Datastores)

| 服務 | Port | 說明 |
| ---- | ---- | ---- |
| **SQL Server** | 1433 | 主要關聯式資料庫 (Latest 2025)。 |
| **Elasticsearch** | 9200 | 搜尋與分析引擎 (v9.3)。 |
| **Kibana** | 5601 | Elasticsearch 資料視覺化。 |
| **Redis** | 6379 | 快取與訊息 broker (v8.6)。 |
| **RedisInsight** | 5540 | Redis GUI 管理工具。 |
| **Redis Exporter** | 9121 | Redis Prometheus Exporter。 |
| **Azurite** | 10000-10002 | Azure Storage Emulator (v3.35)。 |

### 訊息與佇列 (Messaging)

| 服務 | Port | 說明 |
| ---- | ---- | ---- |
| **Mosquitto** | 1883/9002 | MQTT Broker (v2.0)。 |
| **RabbitMQ** | 5672/15672 | 進階訊息佇列 (AMQP v4.0)。 |

### 應用服務 (Services)

| 服務 | Port | 說明 |
| ---- | ---- | ---- |
| **Keycloak** | 8180 | 身分認證與存取管理 (IAM)。 |
| **SearXNG** | 8080 | 隱私搜尋引擎 (Metasearch)。 |

### 開發工具 (Dev Utilities)

| 服務 | Port | 說明 |
| ---- | ---- | ---- |
| **Mailpit** | 1025/8025 | Email 測試工具 (SMTP/Web)。 |
| **VS Code Editor** | N/A | Dev Container (Port-less, mounted)。 |

## 安全與網路 (Security & Network)

- **網路**: `${COMPOSE_PROJECT_NAME}_shared_net` (Bridge 模式)
- **機密資訊 (Secrets)**: 透過檔案掛載 (`secrets/`) 與 `.env` 管理。
- **User IDs**: 固定 UID (例如 MSSQL 使用 10001) 以確保權限一致性。
- **Init Permissions**: 使用 `setup/init-permissions` 容器自動修正跨平台權限問題。

### 權限責任分工 (Permission Responsibilities)

- **目的**：避免 `init.sh`、`init-permissions`、服務 `entrypoint` 三方重複改權限而互相覆寫。

#### 責任矩陣

| 階段 | 負責元件 | 處理目標 | 不應處理 |
| --- | --- | --- | --- |
| 初始化 (手動執行 `task init`) | `scripts/init.sh` | 建立目錄、建立預設設定檔、確保開發者可編輯檔案 | 不做服務 UID 的長期 `chown -R`（避免和執行期打架） |
| 啟動前校正 (Compose 啟動鏈) | `setup/init-permissions/compose.yml` | Host 端資料目錄權限（如 `data/`、`log/`） | 不覆寫 `config/*.sh` owner，不處理開發者需編輯檔案 |
| 容器啟動時 | 服務 `entrypoint.sh` | 容器 runtime 檔案（如 Mosquitto 的 `passwd`、`mosquitto.db`）最小必要權限 | 不回寫 Host 開發設定檔 owner |

#### 邊界規則（本專案）

- `init-permissions` 只修正可持久化資料路徑：`data/`、`log/`。
- `config/` 目錄下的腳本（例如 `entrypoint.sh`）保持為開發者可編輯。
- 若某檔案在容器內會動態生成（例如 `passwd`），由服務 entrypoint 在啟動時保證可用權限。
- 初始化預設設定採「模板檔 + `envsubst` 渲染」，避免在 `init.sh` 內用 heredoc/sed 直接改設定內容。

#### 模板渲染規則（Template Rendering）

- 模板來源統一放在 `scripts/templates/`（受 Git 管理，不放在 volume 資料夾）。
- 執行 `task init` 時，`scripts/init.sh` 會把模板渲染/複製到各服務 `volumes/config/`。
- 容器只讀取 `volumes/config/` 的實際檔案，不直接讀 `scripts/templates/`。
- `volumes/` 可能被清空（例如 purge），因此**不要**把 template 放在 `volumes/` 下。
- 若 `volumes/config` 檔案遺失或毀損，執行 `task init` 可重新生成。

#### 衝突判斷（看到「寫入失敗／被覆寫」時）

1. 先檢查檔案 owner 是否被改成服務 UID（例如 `1883`）。
2. 若是，先檢查 `setup/init-permissions/compose.yml` 是否誤處理到 `config/`。
3. 再檢查服務 entrypoint 是否對同一路徑做 `chown/chmod` 回寫。
4. 修正原則：同一路徑只保留一個責任來源。

> 實際案例與排錯步驟請參閱 `docs/troubleshooting.md` 的「設定檔寫入失敗/覆寫」章節。

## 目錄結構 (Directory Structure)

```text
infra-lab/
├── .env                # 設定變數
├── Taskfile.yml        # 自動化指令
├── compose.yml         # 核心 Docker Compose 定義檔
├── scripts/            # 工具腳本 (init, backup, cleanup)
├── docs/               # 專案文件
├── secrets/            # 機密檔案 (Git-ignored)
├── logs/               # 操作日誌 (Git-ignored)
├── backups/            # 備份檔案 (Git-ignored)
├── setup/              # [基礎] 初始化與權限設定 (Init Permissions)
├── observability/      # [監控] 可觀測性 (Seq, Uptime Kuma, Dozzle)
├── datastores/         # [核心] 資料庫服務 (SQL, Redis, Elastic, Azurite)
├── messaging/          # [核心] 訊息佇列 (RabbitMQ, Mosquitto)
├── services/           # [應用] 應用服務 (Keycloak, SearXNG)
└── tools/              # [工具] 開發工具 (Mailpit, VSCode)
```
