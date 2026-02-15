# Infrastructure Lab

![Docker](https://img.shields.io/badge/Docker-2496ED?style=flat-square&logo=docker&logoColor=white)
![Task](https://img.shields.io/badge/Taskfile-29BEB0?style=flat-square&logo=task&logoColor=white)
![License](https://img.shields.io/badge/license-MIT-green?style=flat-square)

本專案旨在提供一套可快速啟動的本地 Docker 基礎設施環境。

專案中的技術選型主要反映了我個人的實務經驗與學習路徑。例如，選擇 **SQL Server** 是因其為我工作上的主力且偏好的關聯式資料庫；而在 NoSQL 領域，則選用目前接觸最多且為主流的 **Elasticsearch** 作為代表。這份配置主要作為我個人開發與研究時的通用基底。

## 🚀 快速開始 (Quick Start)

### 0. 先決條件 (Prerequisites)

本專案使用 [Task](https://taskfile.dev/) 作為指令管理工具，請依據您的作業系統安裝：

- **Linux / WSL**:
  ```bash
  sh -c "$(curl --location [https://taskfile.dev/install.sh](https://taskfile.dev/install.sh))" -- -d -b /usr/local/bin
  ```

- **Windows (Winget)**:
  ```powershell
  winget install Task.Task
  ```


- **Node.js (NPM)**:
  ```bash
  npm install -g @go-task/cli
  ```



### 1. 初始化環境 (Initialize)

自動建立所需目錄、網路設定與機密檔案：

```bash
task init

```

### 2. 啟動服務 (Start Services)

啟動所有定義在 stack 中的服務：

```bash
task up

```

> **建議**：啟動完成後，請先閱讀 **[服務使用指南 (Service Usage Guide)]()**，內含各服務的 Default 帳密、網址與對應工具。

若僅需啟動特定服務 (e.g., redis)：

```bash
task up SERVICE=redis

```

### 3. 檢視狀態 (Check Status)

查看容器運作狀態：

```bash
task ps

```

### 4. 常用指令 (Commands)

詳細指令說明請參閱 **[指令速查 (Commands)]()**。常用範例：

- `task logs`：查看日誌
- `task backup`：執行備份
- `task clean`：清理容器與孤立資源

## 🛠️ 核心服務 (Key Services)

| 服務 | 連接埠 | 類型 | 說明 |
| --- | --- | --- | --- |
| **SQL Server** | `1433` | RDBMS | 關聯式資料庫 |
| **Elasticsearch** | `9200` | NoSQL | 搜尋與分析引擎 |
| **Mosquitto** | `1883` | MQTT | MQTT Broker |
| **RabbitMQ** | `15672` | Queue | 訊息佇列 (管理介面) |
| **Redis** | `6379` | Cache | 快取與訊息 Broker |
| **Azurite** | `10000` | Emulator | Azure Storage 本地模擬器 |
| **Keycloak** | `8180` | IAM | 身分認證與授權服務 |
| **SearXNG** | `8080` | Search | 隱私搜尋引擎 |

## 📚 文件索引 (Documentation)

- **[架構總覽 (Architecture)]()**
服務列表、Port 對照與專案目錄結構說明。
- **[指令速查 (Commands)]()**
完整的 Taskfile 指令說明。
- **[服務使用指南 (Service Usage)]()**
服務啟動後的實際操作方式（連接字串、帳號密碼來源）。
- **[疑難排解 (Troubleshooting)]()**
常見錯誤排除與解決方案。

> **備註**：本專案文字檔統一使用 LF 換行；若看到 `CRLF will be replaced by LF` 警告，請參閱 [疑難排解第 3 節]()。

## 📝 License

This project is MIT [licensed]().
