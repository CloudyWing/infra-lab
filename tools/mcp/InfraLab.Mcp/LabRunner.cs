using System.Diagnostics;
using System.Text;
using System.Text.RegularExpressions;
using Microsoft.Extensions.Logging;

namespace InfraLab.Mcp;

/// <summary>
/// 在 infra-lab 根目錄執行外部指令。
/// </summary>
/// <remarks>
/// 參數一律經由 <see cref="ProcessStartInfo.ArgumentList"/> 傳遞，不經過 Shell，避免指令注入。
/// </remarks>
public sealed partial class LabRunner : IDisposable {
    private readonly LabOptions options;
    private readonly ILogger<LabRunner> logger;

    /// <summary>
    /// 會改變環境狀態的操作一次只執行一個，避免 switch 與 up 互相干擾。
    /// </summary>
    private readonly SemaphoreSlim mutationLock = new(1, 1);

    /// <summary>
    /// 初始化 <see cref="LabRunner"/> 類別的新執行個體。
    /// </summary>
    /// <param name="options">infra-lab 的執行設定。</param>
    /// <param name="logger">記錄執行指令的 Logger。</param>
    public LabRunner(LabOptions options, ILogger<LabRunner> logger) {
        this.options = options;
        this.logger = logger;
    }

    /// <summary>
    /// 執行 <c>scripts/lab.sh</c>。
    /// </summary>
    /// <param name="args">傳給 <c>lab.sh</c> 的參數。</param>
    /// <param name="timeout">逾時時間。</param>
    /// <param name="cancellationToken">取消權杖。</param>
    /// <returns>指令執行結果。</returns>
    public Task<CommandResult> RunLabScriptAsync(
        IEnumerable<string> args,
        TimeSpan timeout,
        CancellationToken cancellationToken
    ) {
        return RunAsync("bash", ["scripts/lab.sh", .. args], timeout, cancellationToken);
    }

    /// <summary>
    /// 執行 <c>docker compose</c>。
    /// </summary>
    /// <param name="args">接在 <c>docker compose</c> 之後的參數。</param>
    /// <param name="timeout">逾時時間。</param>
    /// <param name="cancellationToken">取消權杖。</param>
    /// <returns>指令執行結果。</returns>
    public Task<CommandResult> RunComposeAsync(
        IEnumerable<string> args,
        TimeSpan timeout,
        CancellationToken cancellationToken
    ) {
        return RunAsync("docker", ["compose", .. args], timeout, cancellationToken);
    }

    /// <summary>
    /// 以互斥方式執行會改變環境狀態的操作。
    /// </summary>
    /// <typeparam name="TResult">操作的回傳型別。</typeparam>
    /// <param name="action">要執行的操作。</param>
    /// <param name="cancellationToken">取消權杖。</param>
    /// <returns>操作的回傳值。</returns>
    public async Task<TResult> MutateAsync<TResult>(Func<Task<TResult>> action, CancellationToken cancellationToken) {
        await mutationLock.WaitAsync(cancellationToken);
        try {
            return await action();
        } finally {
            mutationLock.Release();
        }
    }

    /// <summary>
    /// 在專案根目錄執行外部指令，收集 stdout 與 stderr。
    /// </summary>
    /// <param name="fileName">執行檔名稱。</param>
    /// <param name="args">指令參數。</param>
    /// <param name="timeout">逾時時間；逾時會終止整個 Process Tree。</param>
    /// <param name="cancellationToken">取消權杖。</param>
    /// <returns>指令執行結果。</returns>
    public async Task<CommandResult> RunAsync(
        string fileName,
        IEnumerable<string> args,
        TimeSpan timeout,
        CancellationToken cancellationToken
    ) {
        ProcessStartInfo startInfo = new(fileName) {
            WorkingDirectory = options.Root,
            RedirectStandardOutput = true,
            RedirectStandardError = true,
            RedirectStandardInput = true,
            UseShellExecute = false,
            StandardOutputEncoding = Encoding.UTF8,
            StandardErrorEncoding = Encoding.UTF8
        };
        foreach (string arg in args) {
            startInfo.ArgumentList.Add(arg);
        }

        // 關閉 Compose 的進度動畫與顏色，讓輸出適合文字閱讀
        startInfo.Environment["COMPOSE_ANSI"] = "never";
        startInfo.Environment["COMPOSE_PROGRESS"] = "plain";
        startInfo.Environment["NO_COLOR"] = "1";

        LogCommand(fileName, string.Join(' ', startInfo.ArgumentList));

        using Process process = new() { StartInfo = startInfo };
        StringBuilder output = new();
        Lock outputLock = new();
        process.OutputDataReceived += (_, e) => AppendLine(e.Data);
        process.ErrorDataReceived += (_, e) => AppendLine(e.Data);

        process.Start();
        process.StandardInput.Close();
        process.BeginOutputReadLine();
        process.BeginErrorReadLine();

        using CancellationTokenSource timeoutSource
            = CancellationTokenSource.CreateLinkedTokenSource(cancellationToken);
        timeoutSource.CancelAfter(timeout);
        bool isTimedOut = false;
        try {
            await process.WaitForExitAsync(timeoutSource.Token);
        } catch (OperationCanceledException) when (!cancellationToken.IsCancellationRequested) {
            isTimedOut = true;
            KillProcessTree(process);
        } catch (OperationCanceledException) {
            KillProcessTree(process);
            throw;
        }

        if (!isTimedOut) {
            // 無參數的 WaitForExit 會等到非同步讀取的輸出全部收完
            process.WaitForExit();
        }

        // 保留完整輸出：lab_status 等 Tool 需要解析每一行 JSON，截斷只在回傳給 Client 時處理
        string text;
        lock (outputLock) {
            text = AnsiEscapePattern().Replace(output.ToString(), "").TrimEnd();
        }

        int exitCode = isTimedOut ? -1 : process.ExitCode;
        return new CommandResult(exitCode, text, isTimedOut);

        void AppendLine(string? line) {
            if (line is null) {
                return;
            }

            lock (outputLock) {
                output.AppendLine(line);
            }
        }
    }

    [LoggerMessage(Level = LogLevel.Information, Message = "Run: {FileName} {Arguments}")]
    private partial void LogCommand(string fileName, string arguments);

    private static void KillProcessTree(Process process) {
        try {
            process.Kill(entireProcessTree: true);
        } catch (InvalidOperationException) {
            // Process 已經結束，不需處理
        }
    }

    /// <summary>
    /// 比對 ANSI CSI 控制序列，例如色碼 <c>ESC[31m</c>。
    /// </summary>
    [GeneratedRegex(@"\x1B\[[0-9;?]*[A-Za-z]")]
    private static partial Regex AnsiEscapePattern();

    /// <inheritdoc/>
    public void Dispose() {
        mutationLock.Dispose();
    }
}
