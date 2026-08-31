import { businessLayers } from '../business-layers';

/**
 * Every business layer already describes itself (name, summary, example)
 * in its definition object, so the Swagger spec is generated from that
 * registry instead of scanning JSDoc comments across N route files. Add a
 * business layer -> its docs appear automatically.
 */
export function buildSwaggerSpec() {
  const paths: Record<string, unknown> = {};

  for (const def of businessLayers) {
    paths[`/medinfras/api/${def.name}`] = {
      post: {
        tags: [def.name],
        summary: def.summary ?? `Call BusinessLayer.${def.method}`,
        requestBody: {
          required: true,
          content: {
            'application/json': {
              schema: { type: 'object' },
              example: def.example ?? {},
            },
          },
        },
        responses: {
          200: {
            description: 'Success',
            content: {
              'application/json': {
                schema: {
                  type: 'object',
                  properties: {
                    success: { type: 'boolean', example: true },
                    message: { type: 'string', example: 'OK' },
                    data: {},
                  },
                },
              },
            },
          },
          400: { description: 'Validation error' },
          500: { description: '.NET bridge or business-layer error' },
        },
      },
    };
  }

  return {
    openapi: '3.0.0',
    info: {
      title: 'Medinfras API',
      version: '1.0.0',
      description:
        'REST API gateway exposing Medinfras .NET business layers over HTTP. Every business layer is mounted at /medinfras/api/{businessLayerName}.',
    },
    servers: [{ url: '/', description: 'Current server' }],
    paths,
  };
}
