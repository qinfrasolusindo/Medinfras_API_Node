import fs from 'fs';
import path from 'path';
import { BusinessLayerDefinition } from './types';


const DEFINITION_FILE_PATTERN = /\.definition\.(ts|js)$/;

/**
 * Membaca semua file definition secara recursive.
 *
 * Struktur folder bebas, misalnya:
 *   business-layers/setting-parameter.definition.ts
 *   business-layers/patient/get-history.definition.ts
 *   business-layers/payment/charge.definition.ts
 *
 * Struktur folder tidak memengaruhi route.
 * Route ditentukan dari `name` dan `route` di masing-masing definition.
 */
function walk(dir: string): string[] {
  const entries = fs.readdirSync(dir, { withFileTypes: true });
  const files: string[] = [];

  for (const entry of entries) {
    const fullPath = path.join(dir, entry.name);

    if (entry.isDirectory()) {
      files.push(...walk(fullPath));
    } else if (DEFINITION_FILE_PATTERN.test(entry.name)) {
      files.push(fullPath);
    }
  }

  return files;
}

function loadDefinitions(): BusinessLayerDefinition[] {
  const files = walk(__dirname);

  const definitions = files.map((file) => {
    // eslint-disable-next-line @typescript-eslint/no-var-requires
    const mod = require(file);
    return (mod.default ?? mod) as BusinessLayerDefinition;
  });

  assertNoDuplicateRoutes(definitions);

  return definitions;
}

// Pastikan tidak ada dua operation dengan route yang sama.
function assertNoDuplicateRoutes(
  definitions: BusinessLayerDefinition[]
): void {
  const seen = new Set<string>();

  for (const def of definitions) {
    for (const op of def.operations) {
      const url = `POST /medinfras/api/${def.name}/${op.route}`;

      if (seen.has(url)) {
        throw new Error(
          `Duplicate route detected: ${url}. Two definitions define the same group name + route.`
        );
      }

      seen.add(url);
    }
  }
}

/**
 * Semua file *.definition.ts / *.definition.js di folder ini
 * akan otomatis dimuat.
 *
 * Untuk menambah business layer, cukup buat file definition baru.
 */
export const businessLayers: BusinessLayerDefinition[] = loadDefinitions();

