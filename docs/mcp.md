# MCP Server (InfraLab.Mcp)

`tools/mcp/InfraLab.Mcp` 是以 .NET 10 與官方 C# SDK（`ModelContextProtocol`）撰寫的 MCP Server，讓 Claude Code、Claude Desktop 等 MCP Client 可以查詢與啟停 infra-lab 的服務。

## 1. 設計原則

- **只開放白名單操作**：查詢、啟動、停止、重啟。不開放 `down`、`clean`、`purge`、`backup`、`init`、`doctor-fix` 等會移除容器、刪除資料或修改設定的操作，這些仍需由人執行 `task`。
- **群組與組合只定義一次**：MCP 直接呼叫 `scripts/lab.sh`，不重複維護群組清單。
- **不經過 Shell**：參數以 `ArgumentList` 傳給 `bash`、`docker`，名稱只允許小寫英數與 `-`，服務名稱另外比對 `docker compose config --services`。
- **會改變狀態的操作一次只執行一個**，避免 `switch` 與 `up` 互相干擾。
- **Log 內容視為不可信資料**：`lab_logs` 的說明會提醒 Client 不要執行 Log 裡出現的指示。

## 2. Tools

| Tool | 類型 | 說明 |
| --- | --- | --- |
| `lab_list` | 唯讀 | 列出群組、組合與每次保留的群組。 |
| `lab_status` | 唯讀 | 以 JSON 列出所有容器的狀態與 Health。 |
| `lab_stats` | 唯讀 | 以 JSON 列出 CPU 與記憶體用量。 |
| `lab_logs` | 唯讀 | 查看單一服務最後 N 行 Log（1–1000，預設 100）。 |
| `lab_mem` | 唯讀 | 計算群組或組合的記憶體 Limit 總額。 |
| `lab_doctor` | 唯讀 | 執行環境健檢（不含自動修復）。 |
| `lab_up` | 啟動 | 累加啟動群組。 |
| `lab_start_mode` | 啟動 | 累加啟動組合。 |
| `lab_switch` | 會停止服務 | 切換組合；MODE 錯誤時不會停止任何服務。 |
| `lab_stop` | 會停止服務 | 停止指定服務或全部服務，保留容器與資料。 |
| `lab_restart` | 會停止服務 | 重啟單一服務。 |

會停止服務的 Tool 標示為 `destructiveHint: true`，唯讀 Tool 標示為 `readOnlyHint: true`，Client 可據此決定是否在執行前要求確認。

## 3. 建置

在 WSL（或 Linux / macOS）中執行：

```bash
task mcp:build
```

建置在 `mcr.microsoft.com/dotnet/sdk` 容器中進行，主機只需要 Docker，不需要安裝 .NET SDK。產出的 self-contained 執行檔位於 `tools/mcp/publish/InfraLab.Mcp`，執行時也不需要 .NET Runtime。

- SDK 映像的 Tag 由 `.env` 的 `DOTNET_SDK_TAG` 指定，預設為 `10.0`。
- NuGet 套件快取在 `tools/mcp/.nuget`，重複建置不必重新下載。
- 依 `uname -m` 選擇 `linux-x64` 或 `linux-arm64`。

## 4. 設定 Client

MCP Server 必須在能執行 `docker`、`bash` 與 `scripts/lab.sh` 的環境中執行，也就是 infra-lab 所在的 WSL。

所有 Client 都透過 `scripts/mcp.sh` 啟動 Server。腳本依自身位置推算 repo 根目錄，再以 `--root` 傳給 Server，因此 repo 路徑只需要在 Client 設定中出現一次，執行檔位置與 TargetFramework 都不寫進 Client 設定。

### 4.1 產生設定

```bash
task mcp:config
```

依目前機器的 WSL distro（`$WSL_DISTRO_NAME`）與 repo 路徑，輸出下列各 Client 的設定。換電腦或搬移 repo 後重新執行即可。repo 路徑含雙引號或反斜線時，產生的設定無法正確表達該路徑，`task mcp:config` 會直接報錯並結束，請將 repo 放在不含這兩種字元的目錄。

### 4.2 Claude Code（在 WSL 中執行）

repo 根目錄已附 `.mcp.json`，內容為 `bash scripts/mcp.sh`，在 infra-lab 目錄啟動 Claude Code 時會詢問是否啟用 `infra-lab` MCP Server。

### 4.3 Claude Code（Windows）

執行 `task mcp:config` 輸出的 `claude mcp add` 指令，格式如下：

```bash
claude mcp add infra-lab --scope user -- wsl.exe -d <distro> -e bash <repo>/scripts/mcp.sh
```

### 4.4 Claude Desktop（Windows）

將 `task mcp:config` 輸出的 JSON 加入 `claude_desktop_config.json`，格式如下：

```json
{
  "mcpServers": {
    "infra-lab": {
      "command": "wsl.exe",
      "args": ["-d", "<distro>", "-e", "bash", "<repo>/scripts/mcp.sh"]
    }
  }
}
```

- `-d <distro>` 指定 infra-lab 所在的 distro。主機有多個 distro 時，省略會進入預設 distro。
- `-e` 不經過 Login Shell，執行檔是 self-contained，不依賴 `PATH` 中的 `dotnet`。

## 5. 專案根目錄

Server 依下列順序決定 infra-lab 根目錄，找不到 `compose.yml` 或 `scripts/lab.sh` 時會直接結束：

1. `--root <path>` 參數，`scripts/mcp.sh` 一律以這個方式傳入
2. `INFRA_LAB_ROOT` 環境變數
3. 目前目錄

## 6. 新電腦佈置

```bash
git clone https://github.com/CloudyWing/infra-lab.git
cd infra-lab
task bootstrap
```

`task bootstrap` 依序執行 `init`、`doctor`、`mcp:build`、`mcp:config`，結束時不啟動任何服務。之後依需要以 `task lab:*` 啟動群組，或由 MCP Client 呼叫 `lab_up`、`lab_start_mode` 啟動。
