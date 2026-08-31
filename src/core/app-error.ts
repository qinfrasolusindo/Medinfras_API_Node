/**
 * An error with an HTTP status code attached, so the central error handler
 * middleware knows what status to respond with. Throw this (instead of a
 * plain Error) anywhere in a controller/service when you know the right
 * HTTP status for the failure (validation, not found, upstream failure...).
 */
export class AppError extends Error {
  public readonly statusCode: number;

  constructor(statusCode: number, message: string) {
    super(message);
    this.name = 'AppError';
    this.statusCode = statusCode;
    Object.setPrototypeOf(this, AppError.prototype);
  }
}
