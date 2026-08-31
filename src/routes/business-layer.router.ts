import { Router } from 'express';
import { businessLayers } from '../business-layers';
import { AppError } from '../core/app-error';
import { getBusinessLayer, ListToJson, toJsonList } from '../core/dotnet-bridge';
import { sendSuccess } from '../core/response.util';
import { asyncHandler } from '../middlewares/async-handler.middleware';

export const router = Router();

for (const definition of businessLayers) {
  router.post(
    `/${definition.name}`,
    asyncHandler(async (req, res) => {
      const validationError = definition.validate?.(req.body);
      if (validationError) {
        throw new AppError(400, validationError);
      }

      const args = definition.buildArgs(req.body ?? {});
      const businessLayer = await getBusinessLayer();
      const method = businessLayer[definition.method];

      if (typeof method !== 'function') {
        throw new AppError(500, `.NET method "${definition.method}" was not found on BusinessLayer.`);
      }

      const result = method(...args);
      const data = definition.returnsList === false ? await ListToJson(result) : await toJsonList(result);

      sendSuccess(res, data);
    })
  );
}
