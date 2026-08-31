# Medinfras API

A Node.js + TypeScript + Express REST gateway that exposes Medinfras .NET
business layers (loaded via [`node-api-dotnet`](https://github.com/microsoft/node-api-dotnet))
as HTTP endpoints, with auto-generated Swagger docs.

**Convention:** every business layer gets exactly one route, mounted at

```
POST /medinfras/api/{businessLayerName}
```

The included reference implementation is `settingParameter`, wrapping
`BusinessLayer.GetSettingParameterDtList` from your example code.

---

## 1. How it's organized

```
src/
  business-layers/
    types.ts                          # the BusinessLayerDefinition shape (shared, edit rarely)
    index.ts                          # auto-discovers every *.definition.ts file - don't edit this
    setting-parameter.definition.ts   # <-- ONE file = ONE business layer. This is what you write.
  core/
    dotnet-bridge.ts                  # the ONLY file that talks to node-api-dotnet
    app-error.ts                      # AppError(statusCode, message)
    response.util.ts                  # sendSuccess() - standard response envelope
    filter-expression.util.ts         # safely builds "Field = 'x' AND ..." strings
  middlewares/
    async-handler.middleware.ts       # forwards async errors to the error handler
    error-handler.middleware.ts       # turns any error into a JSON response
    not-found.middleware.ts           # 404 handler
  routes/
    business-layer.router.ts          # ONE generic router that reads the business-layers registry
  swagger/
    swagger.ts                        # builds OpenAPI docs from the registry
  app.ts                              # Express app assembly
  server.ts                           # entrypoint (app.listen)
```

There is **no controller/service/route split per business layer**. A
business layer is a single config object describing:
- what it's called (`name` → the route path),
- what .NET method it calls (`method`),
- how to validate the request body (`validate`),
- how to turn the request body into the .NET method's arguments (`buildArgs`).

`routes/business-layer.router.ts` reads every definition and generates the
matching Express route + handler automatically. `swagger/swagger.ts` reads
the same registry to generate docs. **You never touch either of those
files when adding a business layer.**

### Request/response conventions

- All business-layer endpoints are **`POST`** with a JSON body (chosen so
  complex filters — arrays, multiple fields — don't need to be crammed into
  a query string).
- All responses use the same envelope:
  ```json
  { "success": true, "message": "OK", "data": [...] }
  { "success": false, "message": "..." }
  ```
- Validation errors → `400`. Everything else (including .NET bridge
  failures) → `500`.
- Outside of production (`NODE_ENV != production`), error responses also
  include a `stack` field so you can debug straight from the HTTP response
  without digging through server logs. Production hides it.

---

## 2. Setup

```bash
npm install
cp .env.example .env
# then edit .env:
#   DOTNET_DLL_PATH=<absolute path to QIS.Medinfras.Data.Service.dll>
#   DOTNET_RUNTIME=net472   # must match the DLL's target framework
```

**Important:** `node-api-dotnet` requires the actual .NET runtime and DLL to
be present on the machine running this server (Windows, with .NET
Framework/.NET installed — same as your original example). The Express
layer, routing, validation, error handling, and Swagger docs have all been
verified end-to-end in a sandbox without that DLL — but the real
`BusinessLayer.*` calls could only be checked against the code contract in
your example, not executed. Test the bridge itself on your machine first.

### Run in development (auto-reload on file changes)

```bash
npm run dev
```

### Build & run in production

```bash
npm run build
npm start
```

### Docs

Once running: **http://localhost:3000/medinfras/api/docs**

Health check: **http://localhost:3000/medinfras/api/health**

---

## 3. Adding a new business layer (e.g. `getUser`, `getPatient`, `getMasterItem`)

This is the whole recipe — one file, nothing else:

1. Create `src/business-layers/user.definition.ts`.
2. Fill in the 4 things it needs:

```typescript
import { BusinessLayerDefinition } from './types';

interface GetUserBody {
  userId: string;
}

const user: BusinessLayerDefinition<GetUserBody> = {
  name: 'user',                 // -> POST /medinfras/api/user
  method: 'GetUserById',        // the .NET BusinessLayer method to call
  summary: 'Get a user by ID',
  example: { userId: 'U001' },

  validate: (body) => {
    if (!body?.userId) return '"userId" is required.';
    return null;
  },

  buildArgs: (body) => [body.userId],  // ordered args passed to the .NET method
};

export default user;
```

3. Save the file. That's it — no imports to add anywhere, no route file, no
   controller. `business-layers/index.ts` picks it up automatically (it
   scans the folder for `*.definition.ts` files), the router creates
   `POST /medinfras/api/user`, and Swagger documents it, all on the next
   restart.

If a .NET method returns a **single object** instead of a list, add
`returnsList: false` to the definition — everything else stays the same.

If a business layer genuinely needs **more than one operation** (e.g. both
`getUser` and `createUser`), that's the one case worth extra thought — see
"Notes for further development" below.

---

## 4. Notes for further development

- **A business layer with multiple operations.** The generic router assumes
  one POST route per definition. If a layer needs more than one operation,
  the simplest option is two definitions with distinct names
  (`getUser` / `createUser`), or extend `BusinessLayerDefinition` with a
  `subRoutes` array and loop over it in `business-layer.router.ts` — that's
  the one place you'd touch, once, for every layer that needs it going
  forward.
- **DTO typing.** Request body interfaces (`GetUserBody` etc.) are
  currently written by hand per definition. If that gets repetitive,
  consider `zod` schemas instead of the hand-rolled `validate` functions —
  `validate: (body) => schema.safeParse(body).success ? null : '...'`.
- **Filter expression builder.** `buildFilterExpression()` in
  `core/filter-expression.util.ts` currently supports `=`, `!=`, `>`, `>=`,
  `<`, `<=`, `IN`, `LIKE`. Extend it there (not per-definition) if the .NET
  filter parser supports more (`OR`, grouping, `BETWEEN`, ...).
- **Authentication.** Not included yet. Add a
  `middlewares/auth.middleware.ts` and apply it once in `app.ts` before the
  business layer router is mounted — it'll cover every current and future
  business layer automatically.
- **Multiple DLLs.** `core/dotnet-bridge.ts` currently loads one assembly
  and caches it. If a second business-layer DLL is ever needed, extend
  `loadAssembly()` to key the cache by DLL path instead of a single
  variable.
- **Testing.** No test runner included, to keep this minimal. For unit
  tests, mock `core/dotnet-bridge.ts` — it's the only place that touches
  the real .NET runtime, so definitions/router can be tested without a
  real DLL.
- **Logging.** Currently just `console.log`/`console.error`. Swap in
  `pino`/`winston` in `error-handler.middleware.ts` and `server.ts` if
  structured logs are needed later.
- **CORS.** Wide open (`cors()`) for development convenience — restrict the
  origin list in `app.ts` before this goes near production.

---

## 5. Example request

```bash
curl -X POST http://localhost:3000/medinfras/api/settingParameter \
  -H "Content-Type: application/json" \
  -d '{
    "healthcareId": "001",
    "parameterCodes": ["FN0040", "LB0001", "IS0001", "EM0063", "EM0069", "OP0016"]
  }'
```

```json
{
  "success": true,
  "message": "OK",
  "data": [
    { "HealthcareID": "001", "ParameterCode": "FN0040", "...": "..." }
  ]
}
```
