#!/bin/bash
set -u

SCRIPT_DIR="$(cd "$(dirname "$0")"/.. && pwd)"
source "$SCRIPT_DIR/scripts/common.sh"

setup_logging
load_env 2>/dev/null || true

DO_FIX=0
CURRENT_UID="$(id -u)"
CURRENT_GID="$(id -g)"

for arg in "$@"; do
    case "$arg" in
        --fix)
            DO_FIX=1
            ;;
        -h|--help)
            echo "Usage: $0 [--fix]"
            echo "  --fix  Automatically repair non-writable core directories"
            exit 0
            ;;
        *)
            echo "Unknown argument: $arg"
            echo "Usage: $0 [--fix]"
            exit 1
            ;;
    esac
done

FAILURES=0
WARNINGS=0

pass() {
    log_ok "$1"
}

warn() {
    log_warn "$1"
    WARNINGS=$((WARNINGS + 1))
}

fail() {
    log_error "$1"
    FAILURES=$((FAILURES + 1))
}

repair_dir_writable() {
    local target="$1"
    local parent
    parent="$(dirname "$target")"

    docker run --rm -v "$SCRIPT_DIR:/workspace" -w /workspace alpine sh -c \
        "mkdir -p '$target' && chown -R $CURRENT_UID:$CURRENT_GID '$parent' '$target' && chmod u+rwx '$parent' '$target'" >/dev/null 2>&1
}

check_file_exists() {
    local target="$1"
    local label="$2"

    if [ -f "$target" ]; then
        pass "$label: $target"
    else
        fail "$label missing: $target"
    fi
}

check_file_nonempty() {
    local target="$1"
    local label="$2"

    if [ -s "$target" ]; then
        pass "$label is non-empty: $target"
    else
        fail "$label is empty: $target"
    fi
}

check_file_exists_warn() {
    local target="$1"
    local label="$2"

    if [ -f "$target" ]; then
        pass "$label: $target"
    else
        warn "$label missing: $target (run: task init)"
    fi
}

check_password_sync() {
    local env_pass="${COMMON_PASSWORD:-}"
    local secret_file="secrets/common_password.txt"
    local secret_pass

    if [ ! -f "$secret_file" ]; then
        warn "Password secret missing: $secret_file (run: task init)"
        return
    fi

    secret_pass="$(cat "$secret_file" 2>/dev/null || true)"
    if [ -z "$secret_pass" ]; then
        fail "Password secret is empty: $secret_file"
        return
    fi

    if [ -n "$env_pass" ] && [ "$env_pass" != "$secret_pass" ]; then
        warn "COMMON_PASSWORD and secrets/common_password.txt mismatch"
    else
        pass "COMMON_PASSWORD and secret file are synchronized"
    fi
}

check_dir_writable_or_service_owned() {
    local target="$1"
    local service_uid="$2"
    local service_gid="$3"
    local probe="$target/.doctor_write_test"
    local current_uid
    local current_gid

    if mkdir -p "$target" 2>/dev/null && touch "$probe" 2>/dev/null; then
        rm -f "$probe"
        pass "Writable directory: $target"
        return 0
    fi

    current_uid="$(stat -c '%u' "$target" 2>/dev/null || echo '')"
    current_gid="$(stat -c '%g' "$target" 2>/dev/null || echo '')"

    if [ "$current_uid" = "$service_uid" ] && [ "$current_gid" = "$service_gid" ]; then
        pass "Service-owned directory (expected): $target (${service_uid}:${service_gid})"
        return 0
    fi

    if [ "$DO_FIX" -eq 1 ]; then
        warn "Directory not writable and ownership unexpected: $target (attempting auto-fix)"
        if repair_dir_writable "$target" && mkdir -p "$target" 2>/dev/null && touch "$probe" 2>/dev/null; then
            rm -f "$probe"
            pass "Auto-fixed writable directory: $target"
            return 0
        fi
        fail "Directory still invalid after auto-fix: $target"
    else
        fail "Directory invalid: $target (neither writable nor service-owned by ${service_uid}:${service_gid})"
    fi
}

check_runtime_permissions() {
    local cookie_mode

    if [ "$(docker ps -q -f name=^rabbitmq$)" ]; then
        cookie_mode="$(docker exec rabbitmq sh -c 'if [ -f /var/lib/rabbitmq/.erlang.cookie ]; then stat -c %a /var/lib/rabbitmq/.erlang.cookie; else echo NONE; fi' 2>/dev/null || true)"
        if [ "$cookie_mode" = "NONE" ] || [ "$cookie_mode" = "400" ] || [ "$cookie_mode" = "600" ]; then
            pass "RabbitMQ cookie permission check passed"
        else
            if [ "$DO_FIX" -eq 1 ]; then
                warn "RabbitMQ cookie permission invalid (mode=$cookie_mode), attempting auto-fix"
                docker compose run --rm init-permissions >/dev/null 2>&1 || true
                docker compose restart rabbitmq >/dev/null 2>&1 || true
                cookie_mode="$(docker exec rabbitmq sh -c 'if [ -f /var/lib/rabbitmq/.erlang.cookie ]; then stat -c %a /var/lib/rabbitmq/.erlang.cookie; else echo NONE; fi' 2>/dev/null || true)"
                if [ "$cookie_mode" = "NONE" ] || [ "$cookie_mode" = "400" ] || [ "$cookie_mode" = "600" ]; then
                    pass "RabbitMQ cookie permission auto-fixed"
                else
                    fail "RabbitMQ cookie permission check failed (mode=$cookie_mode)"
                fi
            else
                fail "RabbitMQ cookie permission check failed (mode=$cookie_mode). Run: docker compose run --rm init-permissions && task restart S=rabbitmq"
            fi
        fi
    fi

    if [ "$(docker ps -q -f name=^mosquitto$)" ]; then
        if docker exec mosquitto sh -c 'test -x /mosquitto/config/entrypoint.sh' >/dev/null 2>&1; then
            pass "Mosquitto entrypoint is present and executable"
        else
            if [ "$DO_FIX" -eq 1 ]; then
                warn "Mosquitto entrypoint missing, attempting auto-fix"
                bash scripts/init.sh >/dev/null 2>&1 || true
                docker compose restart mosquitto >/dev/null 2>&1 || true
                if docker exec mosquitto sh -c 'test -x /mosquitto/config/entrypoint.sh' >/dev/null 2>&1; then
                    pass "Mosquitto entrypoint auto-fixed"
                else
                    fail "Mosquitto entrypoint missing or not executable after auto-fix"
                fi
            else
                fail "Mosquitto entrypoint missing or not executable. Run: task init && task restart S=mosquitto"
            fi
        fi
    fi
}

check_dir_writable() {
    local target="$1"
    local probe="$target/.doctor_write_test"

    if mkdir -p "$target" 2>/dev/null && touch "$probe" 2>/dev/null; then
        rm -f "$probe"
        pass "Writable directory: $target"
        return 0
    fi

    if [ "$DO_FIX" -eq 1 ]; then
        warn "Directory not writable: $target (attempting auto-fix)"
        if repair_dir_writable "$target" && mkdir -p "$target" 2>/dev/null && touch "$probe" 2>/dev/null; then
            rm -f "$probe"
            pass "Auto-fixed writable directory: $target"
            return 0
        fi
        fail "Directory still not writable after auto-fix: $target"
    else
        warn "Directory not writable: $target (run: task init or task doctor-fix)"
    fi
}

print_header "INFRA DOCTOR"
log_info "Start Time: $(date +"%Y-%m-%d %H:%M:%S")"
if [ "$DO_FIX" -eq 1 ]; then
    log_info "Auto-fix mode: ENABLED"
fi

if command_exists task; then
    pass "Task CLI is available"
else
    fail "Task CLI not found"
fi

if command_exists docker; then
    pass "Docker CLI is available"
else
    fail "Docker CLI not found"
fi

if docker ps >/dev/null 2>&1; then
    pass "Docker daemon is running"
else
    fail "Docker daemon is not running"
fi

check_file_exists ".env" "Environment file"
check_file_exists "compose.yml" "Compose root file"
check_file_exists "scripts/templates/mosquitto.conf.template" "Mosquitto config template"
check_file_exists "scripts/templates/mosquitto-entrypoint.sh.template" "Mosquitto entrypoint template"
check_file_exists "scripts/templates/rabbitmq.conf.template" "RabbitMQ config template"
check_file_nonempty "scripts/templates/mosquitto-entrypoint.sh.template" "Mosquitto entrypoint template"
check_file_nonempty "scripts/templates/rabbitmq.conf.template" "RabbitMQ config template"

if [ -f ".env" ]; then
    if grep -Eq '^COMPOSE_PROJECT_NAME=.+' .env; then
        pass "COMPOSE_PROJECT_NAME is defined in .env"
    else
        fail "COMPOSE_PROJECT_NAME is missing in .env"
    fi

    if grep -Eq '^COMMON_PASSWORD=.+' .env; then
        pass "COMMON_PASSWORD is defined in .env"
    else
        warn "COMMON_PASSWORD is empty or missing in .env"
    fi
fi

check_password_sync

if [ -f "compose.yml" ]; then
    include_paths=$(awk '/- path:/{print $3}' compose.yml)
    if [ -z "$include_paths" ]; then
        warn "No include paths found in compose.yml"
    else
        while IFS= read -r include_path; do
            [ -z "$include_path" ] && continue
            check_file_exists "$include_path" "Compose include"
        done <<< "$include_paths"
    fi
fi

if docker compose config >/dev/null 2>&1; then
    pass "docker compose config validation passed"
else
    fail "docker compose config validation failed"
fi

if grep -q '/target/mosquitto/config' setup/init-permissions/compose.yml; then
    warn "init-permissions currently touches mosquitto/config (should prefer data/log only)"
else
    pass "init-permissions scope is limited to data/log for Mosquitto"
fi

check_file_exists_warn "messaging/mosquitto/volumes/config/mosquitto.conf" "Mosquitto generated config"
check_file_exists_warn "messaging/mosquitto/volumes/config/entrypoint.sh" "Mosquitto generated entrypoint"
check_file_exists_warn "messaging/rabbitmq/volumes/config/rabbitmq.conf" "RabbitMQ generated config"

check_dir_writable_or_service_owned "datastores/sqlserver/volumes" "10001" "0"
check_dir_writable "messaging/mosquitto/volumes"
check_dir_writable "messaging/rabbitmq/volumes"
check_dir_writable "observability/seq/volumes"
check_dir_writable "secrets"

check_runtime_permissions

if [ "$FAILURES" -eq 0 ]; then
    log_done "Doctor check passed with $WARNINGS warning(s)."
    exit 0
else
    log_error "Doctor check failed: $FAILURES error(s), $WARNINGS warning(s)."
    exit 1
fi
