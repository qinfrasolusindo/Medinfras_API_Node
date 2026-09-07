# Medinfras API

A Node.js + TypeScript + Express REST gateway (plus an MCP/SSE server) that
exposes Medinfras .NET business layers, loaded via
[`node-api-dotnet`](https://github.com/microsoft/node-api-dotnet), as HTTP
and MCP endpoints.

**Convention:** every business-layer operation is mounted at

```
POST /medinfras/api/{groupName}/{operation}
```

The included reference implementation is `settingParameter`, with 5
operations (`list`, `get`, `insert`, `update`, `delete`) matching the 5
overloads in your screenshot.

---

## 1. How it's organized

```
src/
  business-layers/
    types.ts                          # shared shapes (edit rarely)
    index.ts                          # auto-discovers every *.definition.ts, recursively - don't edit
    setting-parameter.definition.ts   # <-- ONE file = ONE group of operations
    _examples/
      join.example.ts                 # reference: joining 2 business layers in one endpoint
  mcp/
    types.ts                          # shared shape for MCP tools
    server.ts                         # builds McpServer, registers every tool
    tools/
      index.ts                        # auto-discovers every *.tool.ts - don't edit
      get-patient-history.tool.ts     # <-- ONE file = ONE MCP tool
  core/
    dotnet-bridge.ts                  # the ONLY file that talks to node-api-dotnet
    app-error.ts                      # AppError(statusCode, message)
    response.util.ts                  # sendSuccess() - standard response envelope
    filter-expression.util.ts         # AND/OR/nested/raw filter-expression builder
  middlewares/                        # async handler wrapper, error handler, 404
  routes/
    business-layer.router.ts          # ONE generic router, reads the business-layers registry
  swagger/
    swagger.ts                        # builds OpenAPI docs from the same registry
  app.ts, server.ts                   # REST API (port 3000 by default)
  mcp-server.ts                       # MCP over SSE (port 3100 by default) - separate process
```

---

## 2. Answers to what you asked

### Q1 — Can a `.definition.ts` grouped/organized in its own folder still be detected?

Yes. `business-layers/index.ts` now scans **recursively**, so this all
works, purely for your own organization (folder structure has zero effect
on routing — only `name` + `route` inside the file decide the URL):

```
src/business-layers/setting-parameter.definition.ts
src/business-layers/patient/get.definition.ts
src/business-layers/patient/history.definition.ts
src/business-layers/payment/charge.definition.ts
src/business-layers/payment/void.definition.ts
```

Also new: **one definition file can group multiple operations** (see
`setting-parameter.definition.ts` — one file, 5 operations: list / get /
insert / update / delete). That's the direct fix for "too many files":
you decide per business area whether it's one file with several operations,
or several files — both are auto-discovered the same way.

### Q2 — More flexible filter-expression builder (AND, OR, raw, no filter, exact-match)

`core/filter-expression.util.ts` now supports all of these:

```typescript
import { cond, and, or, raw, buildFilterExpression } from '../core/filter-expression.util';

// AND (same as before)
buildFilterExpression(and(cond('HealthcareID', '=', '001'), cond('ParameterCode', 'IN', ['A', 'B'])));
// -> HealthcareID = '001' AND ParameterCode IN ('A', 'B')

// OR, nested inside AND
buildFilterExpression(
  and(cond('HealthcareID', '=', '001'), or(cond('ParameterCode', '=', 'A'), cond('ParameterCode', '=', 'B')))
);
// -> HealthcareID = '001' AND (ParameterCode = 'A' OR ParameterCode = 'B')

// A hand-written fragment, inserted as-is (only use with trusted/constant strings)
buildFilterExpression(raw("HealthcareID = '001'"));

// No filter at all
buildFilterExpression(undefined); // -> ''
```

For the **exact-match case** in your screenshot
(`GetSettingParameterDt(HealthcareID, ParameterCode)` — no filter string,
just two plain arguments), you don't need the builder at all — see the
`get` and `delete` operations in `setting-parameter.definition.ts`:
`buildArgs: (body) => [body.healthcareId, body.parameterCode]`. The
builder is only for the `*List` methods that take a `filterExpression`
string; plain-argument overloads just pass the arguments straight through.

### Q3 — Calling 2 business layers and joining them (e.g. vConsultVisit + Registration)

New **advanced mode** on operations: instead of `method` + `buildArgs`, give
an operation a `handler` function. It receives the request body plus a
`ctx` with the same `getBusinessLayer()` / `toJson()` / `toJsonList()`
helpers every simple operation uses — call .NET as many times as you need
and return whatever shape you want.

See `business-layers/_examples/join.example.ts` for a full worked example
(fetches a consult-visit list + a registration record, returns them
joined). It's named `.example.ts` (not `.definition.ts`) so it isn't
auto-mounted — copy it to a real `.definition.ts` file and swap in the real
method/field names to use it.

### Q4 — MCP (SSE) server, initial `get_patient_history` tool

Added as a **separate process** from the REST API (own port, own
entrypoint) so the two can be deployed/scaled independently:

```bash
npm run mcp:dev      # development
npm run build && npm run mcp:start   # production
```

- `GET  http://localhost:3100/medinfras/mcp/sse` — MCP clients connect here
- `POST http://localhost:3100/medinfras/mcp/messages?sessionId=...` — used internally by the SDK/client

`mcp/tools/get-patient-history.tool.ts` implements exactly the chain you
described: fetch `vPreviousMedicalHistory`, then for each row fetch
`GetvPastMedicalList` + `GetvVitalSignDtList` by that row's id, and join
everything into one JSON result per patient.

**This one needs your input before it's real** — I built the full
plumbing (list → fan-out → per-item calls → join → return to MCP client)
and verified the MCP handshake itself works, but I had to guess three
things about the actual DLL, all isolated at the top of the file as named
constants so they're a one-line fix each:

```typescript
const DOTNET_METHODS = {
  previousHistoryList: 'GetvPreviousMedicalHistoryList', // <- confirm real method name
  pastMedicalList: 'GetvPastMedicalList',
  vitalSignList: 'GetvVitalSignDtList',
};
const PATIENT_FILTER_FIELD = 'PatientID';   // <- field used to filter vPreviousMedicalHistory by patient
const HISTORY_ID_FIELD = 'VisitID';         // <- id field on each history row
const LINKING_FILTER_FIELD = 'VisitID';     // <- field used to filter PastMedical/VitalSign by that id
```

Tell me (or just edit these 5 lines yourself, they're all in one place):
1. Does `GetvPreviousMedicalHistoryList` take a `filterExpression` string
   (like `GetSettingParameterDtList`), or a plain `patientId` argument?
2. What's the actual column name that identifies a history row (used to
   then query PastMedical/VitalSign)?
3. Do `GetvPastMedicalList` / `GetvVitalSignDtList` take a filter
   expression, or the id directly as a plain argument?

Once I know these, I can also add more tools the same way (search doctor,
etc.) — same `*.tool.ts` pattern.

---

## 3. Setup

```bash
npm install
cp .env.example .env
# then edit .env:
#   DOTNET_DLL_PATH=<absolute path to QIS.Medinfras.Data.Service.dll>
#   DOTNET_RUNTIME=net472   # must match the DLL's target framework
```

**Important:** `node-api-dotnet` requires the actual .NET runtime and DLL
on the machine running this (Windows, .NET Framework/.NET installed). The
Express/MCP layers, routing, validation, error handling, and Swagger docs
have all been verified end-to-end in a sandbox without that DLL — the real
`BusinessLayer.*` calls could only be checked against the code contract
you shared, not executed. Test the bridge on your machine first.

```bash
npm run dev          # REST API, dev mode (auto-reload)
npm run mcp:dev       # MCP/SSE server, dev mode (separate terminal)

npm run build         # compile both
npm start              # REST API, production
npm run mcp:start      # MCP server, production
```

- REST docs: **http://localhost:3000/medinfras/api/docs**
- REST health: **http://localhost:3000/medinfras/api/health**
- MCP SSE endpoint: **http://localhost:3100/medinfras/mcp/sse**

---

## 4. Adding a new business layer / operation

**Adding an operation to an existing group** — edit its `operations` array,
add one object like the ones already there.

**Adding a whole new group** (e.g. `patient`, `payment`, `doctor`):

```typescript
// src/business-layers/patient/patient.definition.ts
import { BusinessLayerDefinition } from '../types';

interface GetPatientBody {
  patientId: string;
}

const patient: BusinessLayerDefinition = {
  name: 'patient', // -> POST /medinfras/api/patient/{route}
  operations: [
    {
      route: 'get', // -> POST /medinfras/api/patient/get
      summary: 'Get a patient by ID',
      example: { patientId: 'P001' },
      validate: (body: GetPatientBody) => (!body?.patientId ? '"patientId" is required.' : null),
      method: 'GetPatientById',
      buildArgs: (body: GetPatientBody) => [body.patientId],
      resultShape: 'object',
    },
    // add more operations here (list, insert, update, delete, ...)
  ],
};

export default patient;
```

Save it anywhere under `src/business-layers/` (flat or in a subfolder) —
it's picked up automatically on the next restart. Nothing else to touch.

**Adding an MCP tool:** same idea, drop a `*.tool.ts` file in `mcp/tools/`
following `get-patient-history.tool.ts` as a template.

---

## 5. Notes for further development

- **Record marshalling for Insert/Update.** `InsertSettingParameterDt` /
  `UpdateSettingParameterDt` expect a real .NET `SettingParameterDt`
  object, not a plain JS object. Depending on your `node-api-dotnet`
  version, passing a plain JS object with matching property names may or
  may not marshal automatically. If it doesn't, construct the .NET object
  explicitly inside `buildArgs`/`handler` via the assembly, e.g.
  `const asm = await getBusinessLayer(); const rec = new asm.SettingParameterDt(); Object.assign(rec, body);`
  — worth a quick test on your machine before relying on the current
  pass-through version.
- **Filter expression builder.** Currently supports `=`, `!=`, `>`, `>=`,
  `<`, `<=`, `IN`, `LIKE`, plus AND/OR nesting and raw fragments. Extend
  `formatValue`/`FilterOperator` in `core/filter-expression.util.ts` if the
  .NET parser needs more (e.g. `BETWEEN`).
- **Authentication.** Not included yet. Add
  `middlewares/auth.middleware.ts` and apply it once in `app.ts` (REST) —
  it'll cover every current and future business-layer group automatically.
  For MCP, auth typically happens at the SSE connection / transport layer.
- **Multiple DLLs.** `core/dotnet-bridge.ts` loads one assembly and caches
  it. For a second DLL, key the cache by DLL path instead of a single
  variable.
- **Testing.** No test runner included. Mock `core/dotnet-bridge.ts` (the
  only place touching the real .NET runtime) to unit-test definitions/
  tools without a real DLL.
- **Logging.** Currently `console.log`/`console.error`. Swap in
  `pino`/`winston` if structured logs are needed.
- **CORS.** Wide open (`cors()`) for development convenience — restrict
  before production.
- **MCP transport.** This uses the classic SSE transport (`GET /sse` +
  `POST /messages`), matching what you asked for. The MCP SDK also has a
  newer "Streamable HTTP" transport if you ever want a single-endpoint
  alternative — same `mcp/server.ts` (`createMcpServer()`) would be reused,
  only `mcp-server.ts`'s transport wiring would change.

---

## 6. Example requests

```bash
# List
curl -X POST http://localhost:3000/medinfras/api/settingParameter/list \
  -H "Content-Type: application/json" \
  -d '{"healthcareId":"001","parameterCodes":["FN0040","LB0001"]}'

# Exact get
curl -X POST http://localhost:3000/medinfras/api/settingParameter/get \
  -H "Content-Type: application/json" \
  -d '{"healthcareId":"001","parameterCode":"FN0040"}'

# Delete
curl -X POST http://localhost:3000/medinfras/api/settingParameter/delete \
  -H "Content-Type: application/json" \
  -d '{"healthcareId":"001","parameterCode":"FN0040"}'
```
