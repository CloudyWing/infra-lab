namespace InfraLab.Mcp;

/// <summary>
/// 單一容器的狀態，供 <c>lab_status</c> 以 JSON 回傳。
/// </summary>
/// <param name="Service">Compose 服務名稱。</param>
/// <param name="Container">容器名稱。</param>
/// <param name="State">容器狀態，例如 <c>running</c>、<c>exited</c>。</param>
/// <param name="Health">Healthcheck 結果；未設定 Healthcheck 時為空字串。</param>
/// <param name="Status">Docker 顯示的狀態文字。</param>
public sealed record ServiceStatus(string Service, string Container, string State, string Health, string Status);
