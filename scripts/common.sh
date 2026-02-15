#!/bin/bash
# ==========================================
# Infrastructure Lab - 共用函式庫
# ==========================================

# ------------------------------------------
# 日誌函式
# ------------------------------------------

setup_logging() {
    mkdir -p logs
    LOG_FILE="logs/script-$(date +"%Y-%m-%d").log"
    # 僅初始化檔案，不使用 exec 接管輸出，以確保變數擷取功能正常
    touch "$LOG_FILE"
}

log_info() {
    local msg="[INFO] $(date +'%H:%M:%S') $1"
    echo -e "\033[36m$msg\033[0m" # 青色
    if [ -n "${LOG_FILE:-}" ]; then
        echo "$msg" >> "$LOG_FILE"
    fi
}

log_warn() {
    local msg="[WARN] $(date +'%H:%M:%S') $1"
    echo -e "\033[33m$msg\033[0m" # 黃色
    if [ -n "${LOG_FILE:-}" ]; then
        echo "$msg" >> "$LOG_FILE"
    fi
}

log_error() {
    local msg="[ERROR] $(date +'%H:%M:%S') $1"
    echo -e "\033[31m$msg\033[0m" # 紅色
    if [ -n "${LOG_FILE:-}" ]; then
        echo "$msg" >> "$LOG_FILE"
    fi
}

log_ok() {
    local msg="[OK] $(date +'%H:%M:%S') $1"
    echo -e "\033[32m$msg\033[0m" # 綠色
    if [ -n "${LOG_FILE:-}" ]; then
        echo "$msg" >> "$LOG_FILE"
    fi
}

log_done() {
    local msg="[DONE] $(date +'%H:%M:%S') $1"
    echo -e "\033[35m$msg\033[0m" # 紫色
    if [ -n "${LOG_FILE:-}" ]; then
        echo "$msg" >> "$LOG_FILE"
    fi
}

# ------------------------------------------
# 環境變數管理
# ------------------------------------------

clean_crlf() {
    echo "$1" | tr -d '\r'
}

load_env() {
    local env_file="${1:-.env}"

    if [ ! -f "$env_file" ]; then
        log_warn "Environment file not found: $env_file"
        return 1
    fi

    log_info "Loading environment from: $env_file"

    # 1. 建立暫存檔處理格式
    # 2. 移除 CRLF 換行符號
    # 3. 移除註解行與空行
    # 4. 針對未加引號的變數補上雙引號，確保 source 穩定性
    local tmp_env
    tmp_env=$(mktemp)
    
    sed 's/\r$//' "$env_file" | \
    grep -v '^#' | \
    grep -v '^$' | \
    sed 's/=\([^"].*\)$/="\1"/' > "$tmp_env"
    
    set -a
    source "$tmp_env"
    set +a
    
    rm -f "$tmp_env"
    return 0
}

# ------------------------------------------
# 驗證工具
# ------------------------------------------

command_exists() {
    command -v "$1" >/dev/null 2>&1
}

port_available() {
    local port="$1"
    # 優先使用 Bash 內建 TCP 檢測，若環境不支援則回退至 nc
    if (echo > /dev/tcp/localhost/"$port") >/dev/null 2>&1; then
        return 1 # Port is occupied
    else
        # 額外使用 nc 檢查（若存在）以確保準確度
        if command_exists nc; then
            ! nc -z localhost "$port" 2>/dev/null
        else
            return 0 # 假設可用
        fi
    fi
}

ensure_dir() {
    local dir_path="$1"
    if [ ! -d "$dir_path" ]; then
        mkdir -p "$dir_path"
        log_info "Created directory: $dir_path"
    fi
}

# ------------------------------------------
# 系統檢查與輔助
# ------------------------------------------

print_header() {
    echo "=========================================="
    [ -n "$1" ] && echo "  $1"
    echo "=========================================="
}

check_docker() {
    if ! command_exists docker; then
        log_error "Docker is not installed"
        return 1
    fi

    if ! docker ps >/dev/null 2>&1; then
        log_error "Docker daemon is not running"
        return 1
    fi

    return 0
}