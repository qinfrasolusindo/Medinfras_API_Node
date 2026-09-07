import { createApp } from "./app";
import { env } from "./config/env";
import { logger } from "./core/logger";

async function mainApp(): Promise<void> {
  const app = await createApp();

  app.listen(env.PORT, () => {
    logger.info(`Medinfras API listening on http://localhost:${env.PORT}`);
    logger.info(
      `Swagger docs: http://localhost:${env.PORT}/medinfras/api/docs`,
    );
    console.log(`Medinfras API listening on http://localhost:${env.PORT}`);

    console.log(
      `Swagger docs:            http://localhost:${env.PORT}/medinfras/api/docs`,
    );
  });
}

mainApp();

process.on("unhandledRejection", (reason) => {
  logger.error("Unhandled promise rejection", reason);
});

process.on("uncaughtException", (err) => {
  logger.error("Uncaught exception", err);
  process.exit(1);
});
