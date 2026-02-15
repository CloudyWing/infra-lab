#!/bin/bash
set -e

# ==============================================================================
# 1. 環境初始化
# ==============================================================================
SCRIPT_DIR="$(cd "$(dirname "$0")"/.. && pwd)"
source "$SCRIPT_DIR/scripts/common.sh"

# 載入環境變數以取得專案名稱與網路名稱
load_env 2>/dev/null || true
# 優先級：環境變數 > 預設值
PROJECT_NAME="${COMPOSE_PROJECT_NAME:-infra-lab}"
NETWORK_NAME="${PROJECT_NAME}_shared_net"

# ==============================================================================
# 2. 清理邏輯定義
# ==============================================================================

# 清理容器與網路（保留資料卷）
clean_containers() {
    setup_logging
    print_header "CLEAN CONTAINERS"
    
    log_info "Stopping and removing containers for project: $PROJECT_NAME..."
    # 使用 --remove-orphans 確保連同不在 compose 檔案中的殘留容器一併清理
    docker compose down --remove-orphans
    
    log_done "Containers and networks removed. Data volumes are preserved."
}

# 完全清除（含資料卷與設定檔案）
purge_all() {
    log_warn "!!! WARNING: This will DESTROY all containers, networks, and DATA VOLUMES !!!"
    read -p "Are you absolutely sure? [y/N]: " confirm
    
    if [[ ! "$confirm" =~ ^[yY]([eE][sS])?$ ]]; then
        log_info "Purge cancelled by user."
        return 0
    fi
    
    setup_logging
    print_header "FULL SYSTEM PURGE"
    
    # 1. 先停掉容器並刪除 Compose 定義的 Volumes
    log_info "Stopping containers and removing compose volumes..."
    docker compose down -v --remove-orphans || true
    
    # 2. 清理宿主機上的實體目錄 (利用 Docker 解決 root 權限問題)
    # 優化點：明確指定專案路徑，避免誤刪其他目錄
    log_info "Cleaning host volume directories and secrets..."
    docker run --rm -v "$SCRIPT_DIR:/workspace" -w /workspace alpine sh -c \
        "find . -maxdepth 3 -type d -name 'volumes' -exec rm -rf {} +; rm -rf secrets/*.txt"
    
    # 3. 強制移除共享網路 (避免因其他容器佔用導致的殘留)
    log_info "Finalizing network cleanup: $NETWORK_NAME"
    docker network rm "$NETWORK_NAME" 2>/dev/null || true
    
    log_done "Purge complete. All infrastructure data has been reset."
}

# 清理歷史日誌
clean_logs() {
    local days="$1"
    local removed_count
    ensure_dir "logs"
    
    if [ -z "$days" ]; then
        log_info "Purging ALL script logs in ./logs/..."
        removed_count=$(find logs -name "script-*.log" -type f | wc -l)
        find logs -name "script-*.log" -type f -delete
        log_done "Script logs cleared: $removed_count file(s)."
    else
        if ! [[ "$days" =~ ^[0-9]+$ ]]; then
            log_error "Invalid DAYS value: $days (must be a non-negative integer)"
            return 1
        fi
        log_info "Cleaning script logs older than $days days..."
        # 使用 -mtime 進行精確過濾
        removed_count=$(find logs -name "script-*.log" -type f -mtime +"$days" | wc -l)
        find logs -name "script-*.log" -type f -mtime +"$days" -delete
        log_done "Old script logs cleared: $removed_count file(s)."
    fi
}

# ==============================================================================
# 3. 命令路由 (Main)
# ==============================================================================

case "${1:-}" in
    containers)
        clean_containers
        ;;
    purge)
        purge_all
        ;;
    logs)
        clean_logs "${2:-}"
        ;;
    *)
        echo "Infrastructure Lab - Cleanup Utility"
        echo "-------------------------------------"
        echo "Usage: $0 {containers|purge|logs [DAYS]}"
        echo ""
        echo "Commands:"
        echo "  containers  - Stop and remove containers (keeps data)"
        echo "  purge       - DESTROY everything (containers, networks, data volumes)"
        echo "  logs [DAYS] - Remove script logs (all, or older than X days)"
        exit 1
        ;;
esac