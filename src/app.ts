import cors from "cors";
import express, { Express } from "express";
import swaggerUi from "swagger-ui-express";
import { router as businessLayerRouter } from "./routes/business-layer.router";
import { errorHandler } from "./middlewares/error-handler.middleware";
import { notFoundHandler } from "./middlewares/not-found.middleware";
import { buildSwaggerSpec } from "./swagger/swagger";

const API_PREFIX = "/medinfras/api";

export async function createApp(): Promise<Express> {
  const app = express();

  app.use(cors());
  app.use(express.json());

  app.get(`${API_PREFIX}/health`, (_req, res) => {
    res.json({ success: true, message: "Medinfras API is up" });
  });

  app.use(
    `${API_PREFIX}/docs`,
    swaggerUi.serve,
    swaggerUi.setup(await buildSwaggerSpec()),
  );

  // Every business layer becomes POST /medinfras/api/{name} here.
  app.use(API_PREFIX, businessLayerRouter);

  // Keep these two last: 404 for unmatched routes, then the error handler.
  app.use(notFoundHandler);
  app.use(errorHandler);

  return app;
}
