import dotenv from 'dotenv';

dotenv.config();

export const env = {
  PORT: Number(process.env.PORT) || 3000,
  NODE_ENV: process.env.NODE_ENV || 'development',
  DOTNET_DLL_PATH: process.env.DOTNET_DLL_PATH || '',
  DOTNET_RUNTIME: process.env.DOTNET_RUNTIME || 'net472',
};

if (!env.DOTNET_DLL_PATH) {
  // We don't throw here so the server can still boot (e.g. to serve /docs),
  // but every business-layer call will fail fast with a clear error until this is set.
  // eslint-disable-next-line no-console
  console.warn(
    '[WARN] DOTNET_DLL_PATH is not set. Copy .env.example to .env and set it before calling any business-layer endpoint.'
  );
}
