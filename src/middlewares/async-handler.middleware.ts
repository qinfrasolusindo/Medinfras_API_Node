import { NextFunction, Request, RequestHandler, Response } from 'express';

type AsyncRouteHandler = (req: Request, res: Response, next: NextFunction) => Promise<void>;

/**
 * Wraps an async controller so a rejected promise is forwarded to
 * next(err) automatically, instead of every controller repeating its own
 * try/catch. Use it like: router.post('/', asyncHandler(myController))
 */
export function asyncHandler(handler: AsyncRouteHandler): RequestHandler {
  return (req, res, next) => {
    handler(req, res, next).catch(next);
  };
}
