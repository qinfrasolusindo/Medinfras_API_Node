import { Router } from 'express';
import { businessLayers } from '../business-layers';
import { BusinessLayerContext, BusinessLayerOperation } from '../business-layers/types';
import { AppError } from '../core/app-error';
import { getBusinessLayer, toJson, toJsonList } from '../core/dotnet-bridge';
import { sendSuccess } from '../core/response.util';
import { asyncHandler } from '../middlewares/async-handler.middleware';

export const router = Router();

const context: BusinessLayerContext = { getBusinessLayer, toJson, toJsonList };

async function runOperation(op: BusinessLayerOperation, body: unknown): Promise<unknown> {
  // Advanced mode: the operation fully controls how it calls .NET.
  if (op.handler) {
    return op.handler(body, context);
  }

  // Simple mode: call one .NET method and shape its result.
  if (!op.method || !op.buildArgs) {
    throw new AppError(
      500,
      `Operation "${op.route}" is misconfigured: it needs either "handler", or both "method" and "buildArgs".`
    );
  }

  const args = op.buildArgs(body);
  const businessLayer = await getBusinessLayer();
  const method = businessLayer[op.method];

  if (typeof method !== 'function') {
    throw new AppError(500, `.NET method "${op.method}" was not found on BusinessLayer.`);
  }

  const result = method(...args);

  switch (op.resultShape) {
    case 'object':
      return toJson(result);
    case 'raw':
      return result;
    case 'list':
    default:
      return toJsonList(result);
  }
}

for (const definition of businessLayers) {
  for (const operation of definition.operations) {
    router.post(
      `/${definition.name}/${operation.route}`,
      asyncHandler(async (req, res) => {
        const body = req.body ?? {};

        const validationError = operation.validate?.(body);
        if (validationError) {
          throw new AppError(400, validationError);
        }

        const data = await runOperation(operation, body);
        sendSuccess(res, data);
      })
    );
  }
}
