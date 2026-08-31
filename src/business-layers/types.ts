/**
 * Describes one business layer as a plain config object — this is the
 * *entire* thing you write to expose a new .NET BusinessLayer method as an
 * HTTP endpoint. No controller/service/route files needed; the generic
 * router in routes/business-layer.router.ts reads this and does the rest.
 */
export interface BusinessLayerDefinition<TBody = any> {
  /** Route segment. Endpoint becomes POST /medinfras/api/{name} */
  name: string;

  /** The static method name to call on the .NET BusinessLayer class. */
  method: string;

  /** Short description shown in Swagger. */
  summary?: string;

  /** Example request body shown in Swagger's "Try it out". */
  example?: TBody;

  /**
   * Validates the request body before calling .NET.
   * Return an error message to reject with 400, or null/undefined if valid.
   */
  validate?: (body: TBody) => string | null | undefined;

  /** Maps the request body into the ordered arguments for the .NET method call. */
  buildArgs: (body: TBody) => unknown[];

  /**
   * Set to false if the .NET method returns a single object instead of a
   * list. Defaults to true (list), since that's the common case.
   */
  returnsList?: boolean;
}
