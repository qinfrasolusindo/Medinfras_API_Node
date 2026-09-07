import { z } from 'zod';
import { BusinessLayerContext } from '../business-layers/types';

/**
 * One MCP tool, as a plain config object - same philosophy as
 * BusinessLayerDefinition on the REST side. Drop a new `<name>.tool.ts`
 * file in mcp/tools/ and it's picked up automatically (see mcp/tools/index.ts).
 */
export interface McpToolDefinition<TArgs = any> {
  /** Tool name, as seen by MCP clients. */
  name: string;

  /** Human-readable description shown to the MCP client / LLM. */
  description: string;

  /** Zod raw shape describing the tool's input arguments. */
  inputSchema: z.ZodRawShape;

  /**
   * Does the work. Has the same getBusinessLayer/toJson/toJsonList helpers
   * as REST business-layer operations - reuse the same .NET bridge, don't
   * reimplement it here.
   */
  handler: (args: TArgs, ctx: BusinessLayerContext) => Promise<unknown>;
}
