using InfraLab.Mcp;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Hosting;
using Microsoft.Extensions.Logging;

HostApplicationBuilder builder = Host.CreateApplicationBuilder(args);

// stdout 專供 MCP 協定的 JSON-RPC 使用，所有 Log 一律寫到 stderr
builder.Logging.AddConsole(options => options.LogToStandardErrorThreshold = LogLevel.Trace);

builder.Services.AddSingleton(LabOptions.Resolve(args));
builder.Services.AddSingleton<LabRunner>();

builder.Services
    .AddMcpServer()
    .WithStdioServerTransport()
    .WithTools<LabTools>();

await builder.Build().RunAsync();
