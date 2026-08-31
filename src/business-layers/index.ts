import fs from 'fs';
import path from 'path';
import { BusinessLayerDefinition } from './types';

// Matches setting-parameter.definition.ts (dev, via ts-node) and
// setting-parameter.definition.js (production, after `npm run build`).
const DEFINITION_FILE_PATTERN = /\.definition\.(ts|js)$/;

function loadDefinitions(): BusinessLayerDefinition[] {
  const files = fs.readdirSync(__dirname).filter((file) => DEFINITION_FILE_PATTERN.test(file));

  return files.map((file) => {
    // eslint-disable-next-line @typescript-eslint/no-var-requires
    const mod = require(path.join(__dirname, file));
    return (mod.default ?? mod) as BusinessLayerDefinition;
  });
}

/**
 * Every *.definition.ts file in this folder, loaded automatically.
 * To add a new business layer: drop a new `<name>.definition.ts` file next
 * to this one. Nothing else needs to change.
 */
export const businessLayers: BusinessLayerDefinition[] = loadDefinitions();
