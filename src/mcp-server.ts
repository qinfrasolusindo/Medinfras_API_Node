import { SSEServerTransport } from '@modelcontextprotocol/sdk/server/sse.js';
import cors from 'cors';
import express, { Request, Response } from 'express';
import { env } from './config/env';
import { createMcpServer } from './mcp/server';

const app = express();
app.use(cors());

// Multiple clients can connect at once; each SSE connection gets its own
// transport, keyed by the sessionId the SDK generates.
const transports: Record<string, SSEServerTransport> = {};

app.get('/medinfras/mcp/sse', async (_req: Request, res: Response) => {
  const transport = new SSEServerTransport('/medinfras/mcp/messages', res);
  transports[transport.sessionId] = transport;

  res.on('close', () => {
    delete transports[transport.sessionId];
  });

  const server = createMcpServer();
  await server.connect(transport);
});

// Note: express.json() is intentionally NOT applied globally to this app -
// the SDK's transport.handlePostMessage reads the raw body itself.
app.post('/medinfras/mcp/messages', async (req: Request, res: Response) => {
  const sessionId = req.query.sessionId as string | undefined;
  const transport = sessionId ? transports[sessionId] : undefined;

  if (!transport) {
    res.status(400).send('No active SSE connection for this sessionId. Connect to GET /medinfras/mcp/sse first.');
    return;
  }

  await transport.handlePostMessage(req, res);
});

app.listen(env.MCP_PORT, () => {
  // eslint-disable-next-line no-console
  console.log(`Medinfras MCP (SSE) server listening on http://localhost:${env.MCP_PORT}`);
  // eslint-disable-next-line no-console
  console.log(`Connect MCP clients to:      http://localhost:${env.MCP_PORT}/medinfras/mcp/sse`);
});
