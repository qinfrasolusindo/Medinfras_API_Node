import { NextFunction, Request, Response } from 'express';
import { env } from '../config/env';
import { AppError } from '../core/app-error';
import { ApiErrorBody } from '../core/response.util';

/**
 * Last middleware in the chain. Any error passed to next(err) anywhere in
 * the app (including from asyncHandler) ends up here, so this is the only
 * place that needs to know how to turn an error into an HTTP response.
 */
// eslint-disable-next-line @typescript-eslint/no-unused-vars
export function errorHandler(err: unknown, _req: Request, res: Response, _next: NextFunction): void {
  const isAppError = err instanceof AppError;
  const statusCode = isAppError ? err.statusCode : 500;
  const message = err instanceof Error ? err.message : 'Internal server error';

  if (!isAppError) {
    // Unexpected errors (bugs, .NET bridge crashes, etc.) are worth logging
    // with the full stack; expected AppErrors are just normal control flow.
    // eslint-disable-next-line no-console
    console.error(err);
  }

  // This is what NODE_ENV is actually for in this project: outside of
  // production, include the stack trace in the response so you can see
  // exactly what failed without digging through server logs. In
  // production, only the message goes out - never internal stack details.
  const body: ApiErrorBody & { stack?: string } = { success: false, message };
  if (env.NODE_ENV !== 'production' && err instanceof Error) {
    body.stack = err.stack;
  }

  res.status(statusCode).json(body);
}
