import { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
import { BusinessLayerContext } from "../business-layers/types";
import { getBusinessLayer, toJson, toJsonList } from "../core/dotnet-bridge";
import { mcpTools } from "./tools";

const context: BusinessLayerContext = { getBusinessLayer, toJson, toJsonList };

/**
 * Creates a fresh McpServer with every tool from mcp/tools/ registered.
 * Called once per SSE connection (see mcp-server.ts), which is the pattern
 * the SDK's own examples use for multi-client SSE servers.
 */
export async function createMcpServer(): Promise<McpServer> {
  const server = new McpServer({ name: "medinfras-mcp", version: "1.0.0" });

  for (const tool of await mcpTools) {
    const handleCall = async (args: unknown) => {
      try {
        const result = await tool.handler(args, context);
        return {
          content: [
            { type: "text" as const, text: JSON.stringify(result, null, 2) },
          ],
        };
      } catch (err) {
        return {
          isError: true,
          content: [
            { type: "text" as const, text: `Error: ${(err as Error).message}` },
          ],
        };
      }
    };

    // Registering tools from a runtime-built array (rather than a single
    // static call) defeats TS's ability to infer server.tool()'s generic
    // overloads without excessive type instantiation - `as any` here just
    // opts this dynamic-registration loop out of that inference, it
    // doesn't weaken validation (zod still validates args at runtime).
    (server.tool as any)(
      tool.name,
      tool.description,
      tool.inputSchema,
      handleCall,
    );
  }

  return server;
}
