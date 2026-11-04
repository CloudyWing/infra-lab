#!/bin/bash
# ==============================================================================
# 服務群組與情境組合
#
# 群組 (Group) 與組合 (Mode) 只在這個檔案定義，Taskfile 只負責呼叫。
# 不使用 Bash 4 的 Associative Array，以相容 macOS 內建的 Bash 3.2。
# ==============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")"/.. && pwd)"
cd "$SCRIPT_DIR"
source "$SCRIPT_DIR/scripts/common.sh"

# ------------------------------------------
# 原子群組：每個群組都包含它在執行期需要的依賴
# ------------------------------------------
GROUP_NAMES="sql cache cache-ui mq mqtt search search-ui storage auth logs mail monitor websearch dev"

group_services() {
    case "$1" in
        sql)       echo "sql-server" ;;
        cache)     echo "redis" ;;
        cache-ui)  echo "redisinsight redis-exporter" ;;
        mq)        echo "rabbitmq" ;;
        mqtt)      echo "mosquitto" ;;
        search)    echo "elasticsearch" ;;
        search-ui) echo "kibana" ;;
        storage)   echo "azurite" ;;
        auth)      echo "keycloak" ;;
        logs)      echo "seq" ;;
        mail)      echo "mailpit" ;;
        monitor)   echo "uptime-kuma dozzle dozzle-socket-proxy" ;;
        websearch) echo "searxng" ;;
        dev)       echo "vscode-editor" ;;
        *)         return 1 ;;
    esac
}

group_desc() {
    case "$1" in
        sql)       echo "SQL Server" ;;
        cache)     echo "Redis" ;;
        cache-ui)  echo "RedisInsight + Redis Exporter (needs cache)" ;;
        mq)        echo "RabbitMQ (with Management UI)" ;;
        mqtt)      echo "Mosquitto" ;;
        search)    echo "Elasticsearch" ;;
        search-ui) echo "Kibana (starts search automatically)" ;;
        storage)   echo "Azurite" ;;
        auth)      echo "Keycloak" ;;
        logs)      echo "Seq" ;;
        mail)      echo "Mailpit" ;;
        monitor)   echo "Uptime Kuma + Dozzle" ;;
        websearch) echo "SearXNG" ;;
        dev)       echo "VS Code editor container" ;;
    esac
}

# ------------------------------------------
# 情境組合：由群組組成
# ------------------------------------------
MODE_NAMES="api api-full search cache monitor"

mode_groups() {
    case "$1" in
        api)      echo "sql cache mq mail" ;;
        api-full) echo "sql cache mq mail auth logs" ;;
        search)   echo "search search-ui" ;;
        cache)    echo "cache cache-ui" ;;
        monitor)  echo "logs monitor" ;;
        *)        return 1 ;;
    esac
}

# 每次啟動與切換時都會保留的群組；設為空字串可停用 (例如：LAB_KEEP= task lab:api)
LAB_KEEP="${LAB_KEEP-dev}"

# 只執行一次就結束的服務，不計入常駐記憶體
ONE_SHOT_SERVICES="init-permissions setup"

# ------------------------------------------
# 共用函式
# ------------------------------------------
# 輸出到 stderr：die 常在 $(...) 內被呼叫，避免訊息被當成回傳值吞掉
die() {
    log_error "$1" >&2
    exit 1
}

contains() {
    local needle="$1"; shift
    local item
    for item in "$@"; do
        [ "$item" = "$needle" ] && return 0
    done
    return 1
}

# 去除重複並保留順序
uniq_words() {
    local out="" word
    for word in "$@"; do
        # shellcheck disable=SC2086
        contains "$word" $out || out="$out $word"
    done
    echo $out
}

# 群組清單 -> 服務清單；任何一個名稱錯誤都會失敗，且不輸出任何服務
resolve_groups() {
    local services="" group
    [ "$#" -gt 0 ] || die "No group specified. Available groups: $GROUP_NAMES"
    for group in "$@"; do
        services="$services $(group_services "$group")" \
            || die "Unknown group: '$group'. Available groups: $GROUP_NAMES"
    done
    # shellcheck disable=SC2086
    uniq_words $services
}

resolve_mode() {
    local groups
    groups="$(mode_groups "${1:-}")" \
        || die "Unknown MODE: '${1:-}'. Available modes: $MODE_NAMES"
    # shellcheck disable=SC2086
    resolve_groups $groups
}

keep_services() {
    [ -n "$LAB_KEEP" ] || return 0
    # shellcheck disable=SC2086
    resolve_groups $LAB_KEEP
}

require_init() {
    [ -f .env ] || die ".env not found. Run 'task init' first."
    check_docker || exit 1
}

# 從解析後的 Compose 設定讀取每個服務的 Memory Limit (bytes)
# 輸出格式：<service> <bytes>
memory_limits() {
    docker compose config 2>/dev/null | awk '
        /^[^ ]/            { in_services = ($0 == "services:"); next }
        !in_services       { next }
        /^  [^ ][^:]*:$/   { svc = $1; sub(":", "", svc); in_limits = 0; next }
        /^        limits:$/ { in_limits = 1; next }
        /^        [^ ]/    { in_limits = 0 }
        in_limits && /^          memory:/ {
            val = $2; gsub("\"", "", val); print svc, val
        }
    '
}

# 計算服務清單的 Memory Limit 總額 (bytes)，並列出明細
sum_memory() {
    local limits svc bytes total=0
    limits="$(memory_limits)"
    for svc in "$@"; do
        contains "$svc" $ONE_SHOT_SERVICES && continue
        bytes="$(echo "$limits" | awk -v s="$svc" '$1 == s { print $2 }')"
        if [ -z "$bytes" ]; then
            printf "  %-22s %8s\n" "$svc" "(no limit)" >&2
            continue
        fi
        printf "  %-22s %6d MiB\n" "$svc" "$((bytes / 1048576))" >&2
        total=$((total + bytes))
    done
    echo "$total"
}

all_services() {
    docker compose config --services 2>/dev/null
}

# 檢查服務清單的記憶體總額是否超過 Docker 可用記憶體
check_memory() {
    local total docker_total
    total="$(sum_memory "$@")"
    docker_total="$(docker info --format '{{.MemTotal}}' 2>/dev/null || echo 0)"
    echo "  ----------------------------------------" >&2
    printf "  %-22s %6d MiB\n" "Total limit" "$((total / 1048576))" >&2
    if [ "$docker_total" -gt 0 ]; then
        printf "  %-22s %6d MiB\n" "Docker memory" "$((docker_total / 1048576))" >&2
        if [ "$total" -gt "$docker_total" ]; then
            log_warn "Total memory limit exceeds Docker available memory."
            log_warn "On WSL2, raise 'memory=' in %UserProfile%\\.wslconfig, or lower *_MEM_LIMIT in .env."
            return 1
        fi
    fi
    return 0
}

start_services() {
    local services="$1"
    log_info "Starting: $services"
    # shellcheck disable=SC2086
    check_memory $services || log_warn "Continuing anyway; containers may be OOM-killed under load."
    # shellcheck disable=SC2086
    docker compose up -d $services
}

# ------------------------------------------
# 指令
# ------------------------------------------
cmd_list() {
    local group mode
    echo "Groups (task lab:up G=\"<group> ...\"):"
    for group in $GROUP_NAMES; do
        printf "  %-10s %-45s [%s]\n" "$group" "$(group_desc "$group")" "$(group_services "$group")"
    done
    echo ""
    echo "Modes (task lab:<mode> / task lab:switch MODE=<mode>):"
    for mode in $MODE_NAMES; do
        printf "  %-10s %s\n" "$mode" "$(mode_groups "$mode")"
    done
    echo ""
    echo "Always kept: ${LAB_KEEP:-(none)}"
}

cmd_up() {
    local services
    require_init
    services="$(resolve_groups "$@")"
    start_services "$(uniq_words $services $(keep_services))"
}

cmd_mode_up() {
    local services
    require_init
    services="$(resolve_mode "${1:-}")"
    start_services "$(uniq_words $services $(keep_services))"
}

cmd_switch() {
    local target running to_stop="" svc
    # 先驗證 MODE，錯誤時直接結束，不會停止任何服務
    target="$(resolve_mode "${1:-}")"
    require_init
    target="$(uniq_words $target $(keep_services))"

    running="$(docker compose ps --services --status running 2>/dev/null || true)"
    for svc in $running; do
        # shellcheck disable=SC2086
        contains "$svc" $target || to_stop="$to_stop $svc"
    done

    if [ -n "$to_stop" ]; then
        log_info "Stopping services not in mode '$1':$to_stop"
        # shellcheck disable=SC2086
        docker compose stop $to_stop
    else
        log_info "No services to stop."
    fi
    start_services "$target"
}

cmd_mem_groups() {
    local services
    require_init
    if [ "$#" -eq 0 ] || [ "$1" = "all" ]; then
        services="$(all_services)"
    else
        services="$(resolve_groups "$@")"
    fi
    echo "Memory limits:"
    # shellcheck disable=SC2086
    check_memory $services
}

cmd_mem_mode() {
    local services
    services="$(resolve_mode "${1:-}")"
    require_init
    echo "Memory limits (mode '$1' + kept groups):"
    # shellcheck disable=SC2086
    check_memory $(uniq_words $services $(keep_services))
}

usage() {
    cat <<EOF
Usage: $0 <command> [args]
  list                 List groups and modes
  up <group>...        Start groups (additive)
  mode-up <mode>       Start a mode (additive)
  switch <mode>        Stop services outside the mode, then start the mode
  mem [group...|all]   Show memory limits of groups (default: all)
  mem-mode <mode>      Show memory limits of a mode
EOF
}

main() {
    local cmd="${1:-}"
    [ "$#" -gt 0 ] && shift
    case "$cmd" in
        list)     cmd_list ;;
        up)       cmd_up "$@" ;;
        mode-up)  cmd_mode_up "$@" ;;
        switch)   cmd_switch "$@" ;;
        mem)      cmd_mem_groups "$@" ;;
        mem-mode) cmd_mem_mode "$@" ;;
        *)        usage; exit 1 ;;
    esac
}

main "$@"
