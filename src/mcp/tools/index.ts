import fs from "fs";
import path from "path";
import { McpToolDefinition } from "../types";

const TOOL_FILE_PATTERN = /\.tool\.(ts|js)$/;

async function loadTools(): Promise<McpToolDefinition[]> {
  const files = fs
    .readdirSync(__dirname)
    .filter((file) => TOOL_FILE_PATTERN.test(file));

  return Promise.all(
    files.map(async (file) => {
      const mod = await import(path.join(__dirname, file));
      return (mod.default ?? mod) as McpToolDefinition;
    }),
  );
}

/**
 * Every *.tool.ts file in this folder, loaded automatically. To add a new
 * MCP tool: drop a new `<name>.tool.ts` file next to this one, following
 * get-patient-history.tool.ts as a template. Nothing else needs to change.
 */
export const mcpTools: Promise<McpToolDefinition[]> = loadTools();
