namespace InfraLab.Mcp;

/// <summary>
/// 外部指令的執行結果。
/// </summary>
/// <param name="ExitCode">結束代碼；逾時時為 -1。</param>
/// <param name="Output">合併 stdout 與 stderr，已移除 ANSI 色碼的完整輸出，未截斷。</param>
/// <param name="IsTimedOut">若指令因逾時被終止則為 <see langword="true" />；否則為 <see langword="false" />。</param>
public sealed record CommandResult(int ExitCode, string Output, bool IsTimedOut) {
    /// <summary>
    /// 取得一個值，用以指出指令是否在時限內以結束代碼 0 完成。
    /// </summary>
    public bool IsSucceeded => ExitCode == 0 && !IsTimedOut;
}
