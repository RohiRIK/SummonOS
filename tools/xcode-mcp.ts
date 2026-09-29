#!/usr/bin/env bun
// Call one Xcode MCP tool through `xcrun mcpbridge` without an MCP client.
// For sessions where the `xcode` MCP server is not loaded (background jobs).
//
//   bun tools/xcode-mcp.ts list
//   bun tools/xcode-mcp.ts <ToolName> '<json args>' [--out dir]
//
// Text results print to stdout. Image results are saved as PNG files in --out
// (default: ./build/previews) and their paths are printed.

import { mkdirSync, writeFileSync } from "node:fs";
import { join } from "node:path";

const [tool, rawArgs = "{}", ...rest] = process.argv.slice(2);
if (!tool) {
  process.stderr.write("usage: xcode-mcp.ts list | <ToolName> '<json args>' [--out dir]\n");
  process.exit(2);
}
const outFlag = rest.indexOf("--out");
const outDir = outFlag >= 0 ? rest[outFlag + 1] : "build/previews";

const proc = Bun.spawn(["xcrun", "mcpbridge"], { stdin: "pipe", stdout: "pipe", stderr: "inherit" });
const send = (msg: object) => {
  proc.stdin.write(`${JSON.stringify(msg)}\n`);
  proc.stdin.flush();
};

const request = tool === "list"
  ? { jsonrpc: "2.0", id: 2, method: "tools/list" }
  : { jsonrpc: "2.0", id: 2, method: "tools/call", params: { name: tool, arguments: JSON.parse(rawArgs) } };

send({ jsonrpc: "2.0", id: 1, method: "initialize", params: { protocolVersion: "2025-06-18", capabilities: {}, clientInfo: { name: "xcode-mcp.ts", version: "1" } } });

type Content = { type: string; text?: string; data?: string; mimeType?: string };
type Reply = { id?: number; result?: { tools?: { name: string }[]; content?: Content[]; isError?: boolean }; error?: { message: string } };

const decoder = new TextDecoder();
let buffer = "";
let exitCode = 1;
for await (const chunk of proc.stdout) {
  buffer += decoder.decode(chunk);
  let nl: number;
  while ((nl = buffer.indexOf("\n")) >= 0) {
    const line = buffer.slice(0, nl);
    buffer = buffer.slice(nl + 1);
    if (!line.trim()) continue;
    if (process.env.XCODE_MCP_DEBUG) process.stderr.write(`<< ${line.slice(0, 300)}\n`);
    const reply = JSON.parse(line) as Reply;
    if (reply.id === 1) {
      send({ jsonrpc: "2.0", method: "notifications/initialized" });
      send(request);
      continue;
    }
    if (reply.id !== 2) continue;
    exitCode = handle(reply);
    proc.kill();
  }
}
process.exit(exitCode);

function handle(reply: Reply): number {
  if (reply.error) {
    process.stderr.write(`error: ${reply.error.message}\n`);
    return 1;
  }
  if (reply.result?.tools) {
    process.stdout.write(reply.result.tools.map((t) => t.name).join("\n") + "\n");
    return 0;
  }
  const content = reply.result?.content ?? [];
  content.forEach((item, i) => {
    if (item.type === "image" && item.data) {
      mkdirSync(outDir, { recursive: true });
      const file = join(outDir, `${tool}-${Date.now()}-${i}.png`);
      writeFileSync(file, Buffer.from(item.data, "base64"));
      process.stdout.write(`image: ${file}\n`);
    } else if (item.text) {
      process.stdout.write(item.text + "\n");
    }
  });
  return reply.result?.isError ? 1 : 0;
}
