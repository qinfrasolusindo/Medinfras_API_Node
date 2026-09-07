import { businessLayers } from "../business-layers";

/**
 * Every operation already describes itself (route, summary, example) in
 * its definition object, so the Swagger spec is generated from that
 * registry instead of scanning JSDoc comments across N route files. Add a
 * business layer or operation -> its docs appear automatically.
 */
export async function buildSwaggerSpec() {
  const paths: Record<string, unknown> = {};

  for (const def of await businessLayers) {
    for (const op of def.operations) {
      paths[`/medinfras/api/${def.name}/${op.route}`] = {
        post: {
          tags: [def.name],
          summary: op.summary ?? `${def.name}/${op.route}`,
          requestBody: {
            required: true,
            content: {
              "application/json": {
                schema: { type: "object" },
                example: op.example ?? {},
              },
            },
          },
          responses: {
            200: {
              description: "Success",
              content: {
                "application/json": {
                  schema: {
                    type: "object",
                    properties: {
                      success: { type: "boolean", example: true },
                      message: { type: "string", example: "OK" },
                      data: {},
                    },
                  },
                },
              },
            },
            400: { description: "Validation error" },
            500: { description: ".NET bridge or business-layer error" },
          },
        },
      };
    }
  }

  return {
    openapi: "3.0.0",
    info: {
      title: "Medinfras API",
      version: "1.0.0",
      description:
        "REST API gateway exposing Medinfras .NET business layers over HTTP. Every business layer group is mounted at /medinfras/api/{groupName}/{operation}.",
    },
    servers: [{ url: "/", description: "Current server" }],
    paths,
  };
}
