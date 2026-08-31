import { Response } from 'express';

export interface ApiSuccessBody<T> {
  success: true;
  message: string;
  data: T;
}

export interface ApiErrorBody {
  success: false;
  message: string;
}

/** Every endpoint in this project should respond through this helper so the response shape stays consistent. */
export function sendSuccess<T>(res: Response, data: T, message = 'OK', statusCode = 200): void {
  const body: ApiSuccessBody<T> = { success: true, message, data };
  res.status(statusCode).json(body);
}
