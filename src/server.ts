import { createApp } from './app';
import { env } from './config/env';

const app = createApp();

app.listen(env.PORT, () => {
  // eslint-disable-next-line no-console
  console.log(`Medinfras API listening on http://localhost:${env.PORT}`);
  // eslint-disable-next-line no-console
  console.log(`Swagger docs:            http://localhost:${env.PORT}/medinfras/api/docs`);
});
