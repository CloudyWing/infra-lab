namespace InfraLab.Mcp;

/// <summary>
/// infra-lab 的執行設定。
/// </summary>
/// <param name="Root">infra-lab 專案根目錄的絕對路徑。</param>
public sealed record LabOptions(string Root) {
    /// <summary>
    /// 依序由 <c>--root</c> 參數、<c>INFRA_LAB_ROOT</c> 環境變數與目前目錄決定專案根目錄。
    /// </summary>
    /// <param name="args">程式啟動參數。</param>
    /// <returns>已確認為 infra-lab 根目錄的設定。</returns>
    /// <exception cref="InvalidOperationException">決定的目錄缺少 <c>compose.yml</c> 或 <c>scripts/lab.sh</c> 時。</exception>
    public static LabOptions Resolve(string[] args) {
        string? root = null;

        int index = Array.IndexOf(args, "--root");
        if (index >= 0 && index + 1 < args.Length) {
            root = args[index + 1];
        }

        root ??= Environment.GetEnvironmentVariable("INFRA_LAB_ROOT");
        root ??= Directory.GetCurrentDirectory();
        root = Path.GetFullPath(root);

        if (!File.Exists(Path.Combine(root, "compose.yml"))
            || !File.Exists(Path.Combine(root, "scripts", "lab.sh"))
        ) {
            throw new InvalidOperationException(
                $"'{root}' is not the infra-lab root (compose.yml or scripts/lab.sh not found). "
                    + "Pass --root <path> or set INFRA_LAB_ROOT."
            );
        }

        return new LabOptions(root);
    }
}
