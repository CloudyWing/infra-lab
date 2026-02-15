#!/bin/bash
set -e

# ==============================================================================
# 1. 環境初始化與共用函式載入
# ==============================================================================
SCRIPT_DIR="$(cd "$(dirname "$0")"/.. && pwd)"
source "$SCRIPT_DIR/scripts/common.sh"

# 常數設定
DEFAULT_PASSWORD="Dev@InfraLab2026"

# 載入環境變數 (忽略初次執行時不存在 .env 的錯誤)
load_env 2>/dev/null || true

# 預設備援密碼（後續會依 .env 覆蓋）
FINAL_PASS="${COMMON_PASSWORD:-$DEFAULT_PASSWORD}"

# 專案設定（優先使用環境變數）
PROJECT_NAME="${COMPOSE_PROJECT_NAME:-infra-lab}"
NETWORK_NAME="${PROJECT_NAME}_shared_net"

ensure_writable_dir() {
    local target_dir="$1"
    local probe_file
    probe_file="$target_dir/.init_write_probe"

    if mkdir -p "$target_dir" 2>/dev/null && touch "$probe_file" 2>/dev/null; then
        rm -f "$probe_file" 2>/dev/null || true
        return 0
    fi

    log_warn "  [SKIP] Not writable: $target_dir (run: task doctor-fix)"

    return 1
}

render_template() {
    local template_file="$1"
    local target_file="$2"
    local var_spec="${3:-}"

    if [ ! -f "$template_file" ]; then
        log_warn "Template missing: $template_file"
        return 1
    fi

    if [ -z "$var_spec" ]; then
        cp "$template_file" "$target_file"
        return 0
    fi

    if command -v envsubst >/dev/null 2>&1; then
        if envsubst "$var_spec" < "$template_file" > "$target_file"; then
            return 0
        fi
        log_warn "Template render failed: $template_file -> $target_file"
        return 1
    fi

    log_warn "envsubst not found, fallback render: $template_file"
    if perl -pe 's/\$\{COMMON_PASSWORD\}/$ENV{COMMON_PASSWORD}/g' "$template_file" > "$target_file"; then
        if grep -q '\${[A-Za-z_][A-Za-z0-9_]*}' "$target_file"; then
            log_warn "Template has unresolved variables: $target_file"
            return 1
        fi
        return 0
    fi

    return 1
}

setup_logging

print_header "PREPARE SETUP"
log_info "Start Time: $(date +"%Y-%m-%d %H:%M:%S")"
log_info "Starting environment initialization..."

# ==============================================================================
# 2. Docker 基礎建設
# ==============================================================================

# 建立 Docker 共享網路
if [ -z "$(docker network ls --filter name=^${NETWORK_NAME}$ --format="{{ .Name }}")" ]; then
    log_info "Creating shared network: $NETWORK_NAME"
    docker network create "$NETWORK_NAME"
else
    log_ok "Network $NETWORK_NAME already exists."
fi

# 建立專案目錄結構
log_info "Synchronizing directory structure..."
while IFS= read -r dir; do
    [ -z "$dir" ] && continue
    existed=0
    [ -d "$dir" ] && existed=1

    if ensure_writable_dir "$dir"; then
        if [ "$existed" -eq 0 ]; then
            log_info "  [NEW] $dir"
        fi
    else
        log_warn "  [SKIP] Cannot access or create: $dir"
    fi
done <<'EOF'
secrets
datastores/sqlserver/volumes/data
datastores/sqlserver/volumes/log
datastores/sqlserver/volumes/backup
datastores/elastic/volumes/elasticsearch/data
datastores/redis/volumes/data
datastores/redis/volumes/insight
datastores/azurite/volumes/data
messaging/mosquitto/volumes/data
messaging/mosquitto/volumes/log
messaging/mosquitto/volumes/config
messaging/rabbitmq/volumes/data
messaging/rabbitmq/volumes/log
messaging/rabbitmq/volumes/config
services/searxng/volumes/searxng
services/keycloak/volumes/data
observability/seq/volumes/data
tools/vscode
EOF

# ==============================================================================
# 3. 配置檔案與機密管理
# ==============================================================================

# 處理環境變數檔 (.env)
if [ ! -f .env ]; then
    if [ -f .env.example ]; then
        log_info "Initializing .env from example..."
        cp .env.example .env
        # 使用 Perl 替換預設密碼
        perl -i -pe "s/COMMON_PASSWORD=.*/COMMON_PASSWORD=${DEFAULT_PASSWORD}/" .env
        log_ok "Auto-configured .env with default password."
    else
        log_warn ".env.example missing, manual configuration required."
    fi
else
    log_ok ".env already exists."
fi

# 處理機密檔案 (secrets/common_password.txt)
# 若發現意外目錄則移除，確保路徑為檔案
[ -d "secrets/common_password.txt" ] && rm -rf "secrets/common_password.txt"

if [ ! -f secrets/common_password.txt ]; then
    log_info "Generating secret: common_password.txt"
    # 重新加載一次環境變數以取得最新密碼
    load_env 2>/dev/null || true
    FINAL_PASS="${COMMON_PASSWORD:-$DEFAULT_PASSWORD}"
    
    # 寫入密碼檔案 (不帶換行符)
    printf "%s" "$FINAL_PASS" > secrets/common_password.txt
    chmod 600 secrets/common_password.txt 2>/dev/null || true
    log_ok "Password file secured."
fi

# ==============================================================================
# 4. 服務特定配置 (Mosquitto / RabbitMQ)
# ==============================================================================

MOSQUITTO_CONF="messaging/mosquitto/volumes/config/mosquitto.conf"
MOSQUITTO_ENTRY="messaging/mosquitto/volumes/config/entrypoint.sh"
MOSQUITTO_CONF_TEMPLATE="scripts/templates/mosquitto.conf.template"
MOSQUITTO_ENTRY_TEMPLATE="scripts/templates/mosquitto-entrypoint.sh.template"
RABBITMQ_CONF="messaging/rabbitmq/volumes/config/rabbitmq.conf"
RABBITMQ_CONF_TEMPLATE="scripts/templates/rabbitmq.conf.template"

log_info "Checking Mosquitto configurations..."

if [ ! -f "$MOSQUITTO_CONF" ]; then
    if render_template "$MOSQUITTO_CONF_TEMPLATE" "$MOSQUITTO_CONF"; then
        log_ok "Mosquitto config generated."
    else
        log_warn "Cannot write Mosquitto config: $MOSQUITTO_CONF"
    fi
fi

if [ ! -f "$MOSQUITTO_ENTRY" ]; then
    if render_template "$MOSQUITTO_ENTRY_TEMPLATE" "$MOSQUITTO_ENTRY"; then
        chmod +x "$MOSQUITTO_ENTRY" 2>/dev/null || true
        log_ok "Mosquitto entrypoint script ready."
    else
        log_warn "Cannot write Mosquitto entrypoint: $MOSQUITTO_ENTRY"
    fi
fi

log_info "Checking RabbitMQ configurations..."

# 避免歷史錯誤狀況：rabbitmq.conf 被建立成目錄
if [ -d "$RABBITMQ_CONF" ]; then
    rm -rf "$RABBITMQ_CONF"
fi

export COMMON_PASSWORD="$FINAL_PASS"
if render_template "$RABBITMQ_CONF_TEMPLATE" "$RABBITMQ_CONF" '${COMMON_PASSWORD}'; then
    log_ok "RabbitMQ config rendered from template."
else
    log_warn "Cannot write RabbitMQ config: $RABBITMQ_CONF"
fi

# ==============================================================================
# 5. 服務初始帳號與權限設定 (Post-Init Setup)
# ==============================================================================

# 檢查 Docker 是否運行，若有則嘗試預建帳號
if check_docker >/dev/null 2>&1; then
    # 若容器已在運行，則嘗試建立帳號（例如 RabbitMQ）
    if [ "$(docker ps -q -f name=^rabbitmq$)" ]; then
        log_info "Setting up initial RabbitMQ user (admin)..."
        if docker exec rabbitmq rabbitmqctl add_user admin "$FINAL_PASS" >/dev/null 2>&1; then
            log_ok "RabbitMQ admin user created."
        elif docker exec rabbitmq rabbitmqctl change_password admin "$FINAL_PASS" >/dev/null 2>&1; then
            log_ok "RabbitMQ admin password updated."
        else
            log_warn "RabbitMQ admin user setup failed (create/update)."
        fi

        if docker exec rabbitmq rabbitmqctl set_user_tags admin administrator >/dev/null 2>&1; then
            log_ok "RabbitMQ admin tag set."
        else
            log_warn "RabbitMQ set_user_tags failed."
        fi

        if docker exec rabbitmq rabbitmqctl set_permissions -p / admin ".*" ".*" ".*" >/dev/null 2>&1; then
            log_ok "RabbitMQ admin permissions set."
        else
            log_warn "RabbitMQ set_permissions failed."
        fi

        if docker exec rabbitmq rabbitmqctl authenticate_user admin "$FINAL_PASS" >/dev/null 2>&1; then
            log_ok "RabbitMQ admin authentication verified."
        else
            log_warn "RabbitMQ admin authentication verification failed."
        fi
    fi
fi

# ==============================================================================
# 6. 最終權限修正
# ==============================================================================
# 確保所有 secrets 目錄下的 txt 檔案具備正確權限
chmod 600 secrets/*.txt 2>/dev/null || true

log_done "Infrastructure initialization complete!"