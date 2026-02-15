# 服務使用指南 (Service Usage Guide)

本文件提供 `task up` 後的實際使用方式，重點包含：

- 服務入口網址 / Port
- 需要使用的客戶端工具
- 帳號密碼與設定來源

## 0. 使用前先確認

1. 先執行 `task init`（首次）與 `task up`。
2. 用 `task ps` 確認核心服務至少為 `running`（若有 healthcheck，建議為 `healthy`）。
3. 若有登入失敗，先檢查：
   - `.env` 的 `COMMON_PASSWORD`。
   - `secrets/common_password.txt`。

> 本專案多數服務密碼使用同一組，來源為 `COMMON_PASSWORD`（並由 `task init` 同步到 `secrets/common_password.txt`）。
>
> Mosquitto / RabbitMQ 的 `volumes/config` 檔案為「執行時產生檔」：來源模板位於 `scripts/templates/`，由 `task init` 生成到各服務 `volumes/config/`。

## 1. Web 介面服務（開瀏覽器即可）

| 服務 | 入口 | 登入資訊 | 說明 |
| --- | --- | --- | --- |
| **Kibana** | http://localhost:5601 | 帳號 `elastic` / 密碼=`COMMON_PASSWORD` | Elasticsearch 視覺化與查詢。 |
| **RedisInsight** | http://localhost:5540 | 首次進入依畫面建立本機登入；連 Redis 時使用密碼=`COMMON_PASSWORD` | Redis GUI 管理工具。 |
| **RabbitMQ Management** | http://localhost:15672 | 帳號 `admin` / 密碼=`COMMON_PASSWORD` | Queue/Exchange/Binding 管理。 |
| **Keycloak** | http://localhost:8180 | 帳號 `admin` / 密碼=`COMMON_PASSWORD` | IAM 管理與 OIDC/SAML 設定。 |
| **SearXNG** | http://localhost:8080 | 無 | 直接可用的搜尋聚合介面。 |
| **Mailpit** | http://localhost:8025 | 無 | 測試信件收件匣。SMTP 位址見下節。 |
| **Seq** | http://localhost:5340 | 帳號 `admin` / 密碼=`COMMON_PASSWORD`（首次管理員密碼） | 結構化日誌搜尋與查詢。 |
| **Uptime Kuma** | http://localhost:3001 | 首次啟動需在 UI 建立管理者帳號 | 服務可用性監控。 |
| **Dozzle** | http://localhost:8280 | 無 | 容器日誌即時瀏覽。 |

## 2. 需客戶端工具的服務

| 服務 | 連線資訊 | 驗證資訊 | 建議工具 |
| --- | --- | --- | --- |
| **SQL Server** | `localhost:1433` | User: `sa` / Password: `COMMON_PASSWORD` | SSMS |
| **Elasticsearch** | `http://localhost:9200` | User: `elastic` / Password: `COMMON_PASSWORD` | Kibana Dev Tools |
| **Redis** | `localhost:6379` | Password: `COMMON_PASSWORD` | RedisInsight |
| **Azurite** | `localhost:10000/10001/10002` | 使用 SDK 連線字串 | Azure Storage Explorer |
| **Mosquitto (MQTT)** | `localhost:1883` | User: `admin` / Password: `COMMON_PASSWORD` | MQTT Explorer |
| **RabbitMQ (AMQP)** | `localhost:5672` | User: `admin` / Password: `COMMON_PASSWORD` | RabbitMQ Management (Web) |
| **Mailpit SMTP** | `localhost:1025` | 無驗證（預設） | 應用程式 SMTP 設定 |

## 3. 各服務快速上手

### SQL Server

- Host: `localhost`
- Port: `1433`
- Login: `sa`
- Password: `COMMON_PASSWORD`
- 建議工具：**SSMS** (SQL Server Management Studio)。
- Encrypt: 建議 `True`（本地測試可依客戶端設定調整）

### Redis / RedisInsight

1. 開啟 http://localhost:5540。
2. 新增資料庫連線：Host `redis`（容器內）或 `localhost`（主機端），Port `6379`。
3. 勾選 Authentication 並填入 `COMMON_PASSWORD`。

### Elasticsearch / Kibana

- Kibana 登入：`elastic` + `COMMON_PASSWORD`。
- 註：`kibana_system` 僅供 Kibana 內部連結 Elasticsearch 使用，不支援 UI 登入。

### Mosquitto

- `mosquitto` 啟動時會由 entrypoint 以 `admin` + `COMMON_PASSWORD` 建立密碼檔。
- 建議直接使用 **MQTT Explorer**：
  - Host：`localhost`
  - Port：`1883`
  - Username：`admin`
  - Password：`COMMON_PASSWORD`

### RabbitMQ

本專案 `task init` 會嘗試建立預設使用者 `admin`（若已存在則更新密碼）。

- 建議直接使用 **RabbitMQ Management (Web)**：http://localhost:15672
- 登入資訊：`admin` / `COMMON_PASSWORD`
- AMQP 連線資訊（給應用程式）：`localhost:5672`

### Keycloak

- 管理入口：http://localhost:8180
- 帳號：`admin`
- 密碼：`COMMON_PASSWORD`

### Uptime Kuma / Seq

- Uptime Kuma 首次需在 UI 建立自己的管理帳號。
- Seq 首次管理員密碼由 `SEQ_FIRSTRUN_ADMINPASSWORD=${COMMON_PASSWORD}` 設定。

## 4. 帳密與安全建議

- 請勿將 `.env` 與 `secrets/` 內容提交到版本控制。
- 若要更換共用密碼：
  1. 修改 `.env` 的 `COMMON_PASSWORD`
  2. 更新 `secrets/common_password.txt`
  3. `task down && task up`
- 變更後若服務仍登入失敗，先 `task restart SERVICE=<service-name>` 再測試。
- 若遇到服務資料卷權限錯誤（例如 RabbitMQ/Mosquitto/SQL Server 啟動異常），先執行：
  - `docker compose run --rm init-permissions`
  - `task restart S=<service-name>`
- 若遇到 `entrypoint.sh` / `*.conf` 遺失（例如 purge 後），執行 `task init` 會從 `scripts/templates/` 自動重建到 `volumes/config/`。

## 5. 建議使用順序

1. 先開 `http://localhost:3001`（Uptime Kuma）看服務是否可達。
2. 再開 `http://localhost:8280`（Dozzle）看是否有錯誤日誌。
3. 依需求進入目標服務（例如 SQL、Redis、RabbitMQ 管理介面）。
4. 若遇到問題，回到 [疑難排解](./troubleshooting.md)。

## 6. 進階（CLI）

> 本節提供進階維運指令；若只需日常使用，優先依上方 GUI/工具流程操作。

### SQL Server：快速查詢

```bash
docker exec sql-server /opt/mssql-tools18/bin/sqlcmd -S 127.0.0.1 -U sa -P "$(cat secrets/common_password.txt)" -C -Q "SELECT @@VERSION"
docker exec sql-server /opt/mssql-tools18/bin/sqlcmd -S 127.0.0.1 -U sa -P "$(cat secrets/common_password.txt)" -C -Q "SELECT name FROM sys.databases"
```

### Redis：連線與檢查

```bash
docker exec redis redis-cli --no-auth-warning -a "$(cat secrets/common_password.txt)" ping
docker exec redis redis-cli --no-auth-warning -a "$(cat secrets/common_password.txt)" info server
```

### Elasticsearch / Kibana：健康與索引概覽

```bash
docker exec elasticsearch curl -s -u elastic:"$(cat secrets/common_password.txt)" http://localhost:9200/_cluster/health?pretty
docker exec elasticsearch curl -s -u elastic:"$(cat secrets/common_password.txt)" http://localhost:9200/_cat/indices?v
```

### Mosquitto：發佈/訂閱測試

```bash
docker exec mosquitto sh -c 'mosquitto_sub -h 127.0.0.1 -p 1883 -u admin -P "$(cat /run/secrets/mq_password)" -t demo/test -C 1 > /tmp/mqtt.out & sleep 1; mosquitto_pub -h 127.0.0.1 -p 1883 -u admin -P "$(cat /run/secrets/mq_password)" -t demo/test -m hello; wait; cat /tmp/mqtt.out'
```

### RabbitMQ：重建/更新 admin 帳號（必要時）

```bash
docker exec rabbitmq rabbitmqctl add_user admin "$(cat secrets/common_password.txt)" || docker exec rabbitmq rabbitmqctl change_password admin "$(cat secrets/common_password.txt)"
docker exec rabbitmq rabbitmqctl set_user_tags admin administrator
docker exec rabbitmq rabbitmqctl set_permissions -p / admin ".*" ".*" ".*"
docker exec rabbitmq rabbitmqctl list_queues
```
