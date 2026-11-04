namespace InfraLab.Mcp;

/// <summary>
/// 單一容器的資源用量，供 <c>lab_stats</c> 以 JSON 回傳。
/// </summary>
/// <param name="Container">容器名稱。</param>
/// <param name="Cpu">CPU 使用率，例如 <c>1.25%</c>。</param>
/// <param name="Memory">記憶體用量與上限，例如 <c>120MiB / 512MiB</c>。</param>
/// <param name="MemoryPercent">記憶體使用率。</param>
public sealed record ContainerStats(string Container, string Cpu, string Memory, string MemoryPercent);
