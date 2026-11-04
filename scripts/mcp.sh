#!/bin/bash
# ==============================================================================
# infra-lab MCP Server 的建置、啟動與 Client 設定
#
# repo 路徑只由本腳本的位置推算，Client 設定只需要指向這個檔案：
#   build   以 .NET SDK 容器發布 self-contained 執行檔，主機只需要 Docker
#   run     啟動 MCP Server (stdio)，供 MCP Client 呼叫；未指定子命令時的預設值
#   config  依目前機器的 distro 與路徑輸出 Client 設定
# ==============================================================================
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")"/.. && pwd)"
PUBLISH_DIR="$ROOT/tools/mcp/publish"
BIN="$PUBLISH_DIR/InfraLab.Mcp"

# 讀取 .env 的單一鍵值；不 source 整份 .env，避免 run 模式在 stdout 輸出任何內容
# 找不到鍵時輸出空字串並以成功結束，讓呼叫端套用預設值；在 set -e 下用 grep 會因無匹配而中止
env_value() {
    [ -f "$ROOT/.env" ] || return 0
    awk -v key="$1" '
        index($0, key "=") == 1 { value = substr($0, length(key) + 2) }
        END { gsub(/["\r]/, "", value); print value }
    ' "$ROOT/.env"
}

cmd_run() {
    # stdout 是 MCP 的 JSON-RPC 通道，錯誤訊息只能寫到 stderr
    if [ ! -x "$BIN" ]; then
        echo "[ERROR] MCP server is not built: $BIN. Run 'task mcp:build' first." >&2
        exit 1
    fi
    exec "$BIN" --root "$ROOT" "$@"
}

cmd_build() {
    local rid sdk_tag
    # shellcheck source=common.sh
    source "$ROOT/scripts/common.sh"
    check_docker || exit 1

    case "$(uname -m)" in
        x86_64 | amd64)  rid="linux-x64" ;;
        aarch64 | arm64) rid="linux-arm64" ;;
        *)
            log_error "Unsupported architecture: $(uname -m)"
            exit 1
            ;;
    esac
    sdk_tag="$(env_value DOTNET_SDK_TAG)"
    sdk_tag="${sdk_tag:-10.0}"

    log_info "Publishing InfraLab.Mcp ($rid) with mcr.microsoft.com/dotnet/sdk:$sdk_tag ..."
    # 以目前使用者的 UID/GID 執行，產出的檔案不會屬於 root；
    # NuGet 快取放在 tools/mcp/.nuget，重複建置不必重新下載套件
    docker run --rm \
        --user "$(id -u):$(id -g)" \
        -e HOME=/tmp \
        -e DOTNET_CLI_HOME=/tmp \
        -e DOTNET_CLI_TELEMETRY_OPTOUT=1 \
        -e DOTNET_NOLOGO=1 \
        -e DOTNET_SKIP_WORKLOAD_INTEGRITY_CHECK=1 \
        -e NUGET_PACKAGES=/src/.nuget/packages \
        -v "$ROOT/tools/mcp:/src" \
        -w /src \
        "mcr.microsoft.com/dotnet/sdk:$sdk_tag" \
        dotnet publish InfraLab.Mcp/InfraLab.Mcp.csproj \
            -c Release \
            -r "$rid" \
            --self-contained \
            -p:PublishSingleFile=true \
            -p:DebugType=None \
            -o /src/publish \
            -v q

    [ -x "$BIN" ] || { log_error "Publish finished but $BIN was not found."; exit 1; }
    log_ok "MCP server built: $BIN"
}

cmd_config() {
    local distro="${WSL_DISTRO_NAME:-}"
    local script="$ROOT/scripts/mcp.sh"

    # 輸出的 JSON 與 PowerShell／cmd 指令都以雙引號包住路徑，路徑本身含 " 或 \ 時無法正確表達，直接拒絕
    case "$ROOT" in
        *'"'* | *'\'*)
            echo "[ERROR] The repo path contains a double quote or backslash, which the generated client settings cannot express: $ROOT" >&2
            echo "        Move or clone infra-lab to a path without these characters, then run 'task mcp:config' again." >&2
            exit 1
            ;;
    esac

    echo "MCP Server settings for this machine (root: $ROOT)"
    echo ""
    echo "[Claude Code in this environment]"
    echo "  Start Claude Code in $ROOT; the repo's .mcp.json runs scripts/mcp.sh."
    echo ""

    if [ -n "$distro" ]; then
        echo "[Claude Code on Windows]"
        # 路徑加上雙引號，repo 位於含空白的目錄時，複製到 PowerShell 或 cmd 仍是單一引數
        echo "  claude mcp add infra-lab --scope user -- wsl.exe -d \"$distro\" -e bash \"$script\""
        echo ""
        echo "[Claude Desktop on Windows] claude_desktop_config.json:"
        cat <<EOF
  {
    "mcpServers": {
      "infra-lab": {
        "command": "wsl.exe",
        "args": ["-d", "$distro", "-e", "bash", "$script"]
      }
    }
  }
EOF
    else
        echo "[Other MCP clients]"
        echo "  command: bash"
        echo "  args:    [\"$script\"]"
    fi

    if [ ! -x "$BIN" ]; then
        echo ""
        echo "[WARN] MCP server is not built yet. Run 'task mcp:build'."
    fi
}

usage() {
    cat <<EOF
Usage: $0 [run|build|config]
  run      Start the MCP server over stdio (default)
  build    Publish a self-contained binary using a .NET SDK container
  config   Print MCP client settings for this machine
EOF
}

main() {
    local cmd="${1:-run}"
    [ "$#" -gt 0 ] && shift
    case "$cmd" in
        run)    cmd_run "$@" ;;
        build)  cmd_build ;;
        config) cmd_config ;;
        -h | --help | help) usage ;;
        *)      usage >&2; exit 1 ;;
    esac
}

main "$@"
