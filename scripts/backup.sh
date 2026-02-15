#!/bin/bash
set -e

# ==============================================================================
# 1. 基礎配置與環境初始化
# ==============================================================================
SCRIPT_DIR="$(cd "$(dirname "$0")"/.. && pwd)"
source "$SCRIPT_DIR/scripts/common.sh"
cd "$SCRIPT_DIR"
load_env
setup_logging

# 設定備份目錄與時間戳記
BACKUP_DIR="./backups"
TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
TARGET_DIR="$BACKUP_DIR/$TIMESTAMP"
mkdir -p "$TARGET_DIR"

print_header "BACKUP START"
log_info "Start Time: $(date +"%Y-%m-%d %H:%M:%S")"
log_info "Backup ID: $TIMESTAMP"

# ==============================================================================
# 2. SQL Server 備份 (整合備份與收集邏輯)
# ==============================================================================
if docker ps --format '{{.Names}}' | grep -q "^sql-server$"; then
    log_info "Snapshotting SQL Server..."

    # 取得資料庫清單（排除系統庫：master, tempdb, model, msdb）
    dbs=$(docker exec sql-server /opt/mssql-tools18/bin/sqlcmd \
        -S 127.0.0.1 -U sa -P "$COMMON_PASSWORD" -C -h -1 -W \
        -Q "SET NOCOUNT ON; SELECT name FROM sys.databases WHERE name NOT IN ('master','tempdb','model','msdb')" | tr -d '\r')

    for db in $dbs; do
        if [ -z "$db" ]; then continue; fi
        
        log_info "  - Processing database: $db"
        BAK_FILE="${db}_$TIMESTAMP.bak"
        CONTAINER_BAK_PATH="/var/opt/mssql/backup/$BAK_FILE"

        # 執行備份 (使用 COPY_ONLY 以免破壞現有備份計畫)
        docker exec sql-server /opt/mssql-tools18/bin/sqlcmd \
            -S 127.0.0.1 -U sa -P "$COMMON_PASSWORD" -C \
            -Q "BACKUP DATABASE [$db] TO DISK = '$CONTAINER_BAK_PATH' WITH COPY_ONLY, STATS = 10" >/dev/null

        if docker cp "sql-server:$CONTAINER_BAK_PATH" "$TARGET_DIR/" 2>/dev/null; then
            log_info "    [OK] Collected: $BAK_FILE"
            # 清理容器內暫存檔
            docker exec sql-server rm "$CONTAINER_BAK_PATH"
        else
            log_error "    [FAILED] Could not collect $BAK_FILE"
        fi
    done
else
    log_warn "SQL Server container not found or stopped. Skipping."
fi

# ==============================================================================
# 3. Redis 備份
# ==============================================================================
if docker ps --format '{{.Names}}' | grep -q "^redis$"; then
    log_info "Snapshotting Redis..."

    # 穩定路徑：容器內 SAVE 後，直接 docker cp 取回 dump.rdb
    if docker exec redis redis-cli --no-auth-warning -a "$COMMON_PASSWORD" SAVE >/dev/null 2>&1 \
        && docker cp "redis:/data/dump.rdb" "$TARGET_DIR/redis_dump.rdb" >/dev/null 2>&1; then
        log_info "    [OK] Redis dump collected."
    else
        log_error "    [FAILED] Redis backup failed (SAVE+CP)."
        exit 1
    fi
else
    log_warn "Redis container not found or stopped. Skipping."
fi

# ==============================================================================
# 4. 資料卷備份 (Tarball)
# ==============================================================================
log_info "Creating volume tarball..."
if docker run --rm -v "$SCRIPT_DIR:/workspace" -w /workspace alpine \
    tar -czf "$TARGET_DIR/volumes.tar.gz" \
    --exclude='*/compose.yml' --exclude='*.env' \
    datastores messaging services tools setup observability 2>/dev/null; then
    # 將容器 root 產生的檔案 ownership 還給目前使用者
    docker run --rm -v "$SCRIPT_DIR:/workspace" -w /workspace alpine \
        chown -R "$(id -u):$(id -g)" "$TARGET_DIR" >/dev/null 2>&1 || true
    log_info "Volume backup created: $TARGET_DIR/volumes.tar.gz"
else
    log_error "Volume tarball backup failed."
    exit 1
fi

# ==============================================================================
# 5. 後端清理與權限修正
# ==============================================================================
log_info "Cleaning up old backups (keeping last 5)..."
# 排除目前正在處理的目錄，並刪除舊資料夾
ls -d "$BACKUP_DIR"/*/ 2>/dev/null | sort -r | tail -n +6 | xargs rm -rf 2>/dev/null || true

# 修正擁有權（確保目前使用者可讀取 Docker 產出的檔案）
chown -R "$(id -u):$(id -g)" "$TARGET_DIR" 2>/dev/null || true

log_info "Backup contents:"
ls -lh "$TARGET_DIR"

log_done "Backup completed: $TARGET_DIR"
