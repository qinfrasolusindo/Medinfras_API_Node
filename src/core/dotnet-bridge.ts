import { env } from '../config/env';
import { AppError } from './app-error';

/**
 * Thin, lazy-loaded wrapper around node-api-dotnet.
 *
 * Every business-layer service should go through `getBusinessLayer()`
 */
type DotnetAssembly = any;

let assembly: DotnetAssembly | null = null;
let loadingPromise: Promise<DotnetAssembly> | null = null;

async function loadAssembly(): Promise<DotnetAssembly> {
  if (assembly) return assembly;

  if (!env.DOTNET_DLL_PATH) {
    throw new AppError(
      500,
      'DOTNET_DLL_PATH is not configured. Set it in your .env file (see .env.example).'
    );
  }
  const dotnetModule = await import(`node-api-dotnet/${env.DOTNET_RUNTIME}`);
  const dotnet = dotnetModule.default ?? dotnetModule;

  try {
    dotnet.load(env.DOTNET_DLL_PATH);
  } catch (err) {
    throw new AppError(
      500,
      `Failed to load .NET DLL at "${env.DOTNET_DLL_PATH}": ${(err as Error).message}`
    );
  }
  
  assembly = dotnet.QIS.Medinfras.Data.Service;
  return assembly;
}

/**
 * Returns the loaded assembly, loading it on first use and reusing it
 * afterwards. Concurrent callers during the very first load share the same
 * in-flight promise instead of racing to load the DLL twice.
 */
async function getAssembly(): Promise<DotnetAssembly> {
  if (assembly) return assembly;
  if (!loadingPromise) {
    loadingPromise = loadAssembly().finally(() => {
      loadingPromise = null;
    });
  }
  return loadingPromise;
}

/** Returns the `BusinessLayer` static class exposed by the DLL. */
export async function getBusinessLayer(): Promise<DotnetAssembly> {
  const asm = await getAssembly();
  return asm.BusinessLayer;
}

/**
 * Converts a single .NET object returned by a BusinessLayer call into a
 * plain JS object/array, using the DLL's own `Function.ToJson` helper.
 */
export async function toJson<T = unknown>(dotnetObject: unknown): Promise<T> {
  const asm = await getAssembly();
  const json: string = asm.Function.ListToJson(dotnetObject);
  return JSON.parse(json) as T;
}

/**
 * Convenience helper for the common case: a BusinessLayer method returns a
 * .NET list/array, and every item needs to go through ToJson individually.
 */
export async function toJsonList<T = unknown>(dotnetList: unknown[] | null | undefined): Promise<T[]> {
  if (!dotnetList || dotnetList.length === 0) return [];
  return Promise.all(dotnetList.map((item) => toJson<T>(item)));
}
