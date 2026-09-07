# Medinfras API

Node.js + TypeScript service that exposes Medinfras .NET Business Layers through a REST API and an MCP server.

The service provides a generic business-layer gateway for existing .NET assemblies while supporting MCP tools for AI/agent integrations.

## Features

* REST API gateway for Medinfras Business Layers
* MCP server with SSE transport
* Automatic discovery of business-layer definitions
* Automatic discovery of MCP tools
* Support for multiple operations within a single business-layer definition
* Flexible filter-expression builder with AND/OR nesting
* Direct argument mapping for exact-match operations
* Custom handlers for multi-step Business Layer operations
* Standardized API response format
* OpenAPI / Swagger documentation
* .NET Business Layer integration through `node-api-dotnet`

## Architecture

```text
                         ┌──────────────────────┐
                         │     REST Clients     │
                         └──────────┬───────────┘
                                    │
                                    ▼
                         ┌──────────────────────┐
                         │    REST API :3000   │
                         │   Generic Router     │
                         └──────────┬───────────┘
                                    │
                                    ▼
                         ┌──────────────────────┐
                         │ Business Layer       │
                         │ Registry / Definitions│
                         └──────────┬───────────┘
                                    │
                                    ▼
                         ┌──────────────────────┐
                         │    .NET Bridge       │
                         │  node-api-dotnet     │
                         └──────────┬───────────┘
                                    │
                                    ▼
                         ┌──────────────────────┐
                         │ Medinfras .NET DLL   │
                         └──────────────────────┘


                         ┌──────────────────────┐
                         │     MCP Clients      │
                         └──────────┬───────────┘
                                    │
                                    ▼
                         ┌──────────────────────┐
                         │    MCP Server :3100  │
                         │       SSE            │
                         └──────────┬───────────┘
                                    │
                                    ▼
                         ┌──────────────────────┐
                         │     MCP Tools        │
                         └──────────┬───────────┘
                                    │
                                    ▼
                         ┌──────────────────────┐
                         │    .NET Bridge       │
                         └──────────────────────┘
```

The REST API and MCP server run as separate processes, allowing them to be deployed and scaled independently.

## Project Structure

```text
src/
├── business-layers/
│   ├── types.ts
│   ├── index.ts
│   ├── setting-parameter.definition.ts
│   └── _examples/
│       └── join.example.ts
│
├── mcp/
│   ├── types.ts
│   ├── server.ts
│   └── tools/
│       ├── index.ts
│       └── get-patient-history.tool.ts
│
├── core/
│   ├── dotnet-bridge.ts
│   ├── app-error.ts
│   ├── response.util.ts
│   └── filter-expression.util.ts
│
├── middlewares/
│   ├── ...
│
├── routes/
│   └── business-layer.router.ts
│
├── swagger/
│   └── swagger.ts
│
├── app.ts
├── server.ts
└── mcp-server.ts
```

### Core Components

| Component                         | Description                                       |
| --------------------------------- | ------------------------------------------------- |
| `business-layers/types.ts`        | Shared Business Layer type definitions            |
| `business-layers/index.ts`        | Recursively discovers Business Layer definitions  |
| `*.definition.ts`                 | Defines a Business Layer group and its operations |
| `mcp/tools/index.ts`              | Automatically discovers MCP tools                 |
| `*.tool.ts`                       | Defines an individual MCP tool                    |
| `core/dotnet-bridge.ts`           | Central integration point with `node-api-dotnet`  |
| `core/filter-expression.util.ts`  | Builds .NET filter-expression strings             |
| `core/response.util.ts`           | Standard API response handling                    |
| `routes/business-layer.router.ts` | Generic REST router                               |
| `swagger/swagger.ts`              | Generates OpenAPI documentation                   |
| `app.ts`                          | Express application                               |
| `server.ts`                       | REST API entry point                              |
| `mcp-server.ts`                   | MCP server entry point                            |

## Business Layer Definitions

Each Business Layer group is defined through a `*.definition.ts` file.

Definitions can be organized either directly under `src/business-layers/` or inside subdirectories.

```text
src/business-layers/
├── setting-parameter.definition.ts
├── patient/
│   ├── get.definition.ts
│   └── history.definition.ts
└── payment/
    ├── charge.definition.ts
    └── void.definition.ts
```

The directory structure is only for organization. Routing is determined by the `name` and `route` properties defined inside each definition.

A single definition can contain multiple operations:

```text
settingParameter
├── list
├── get
├── insert
├── update
└── delete
```

This allows related operations to be grouped without requiring a separate file for every method.

## REST API Convention

All Business Layer operations follow the same endpoint convention:

```text
POST /medinfras/api/{groupName}/{operation}
```

For example:

```text
POST /medinfras/api/settingParameter/list
POST /medinfras/api/settingParameter/get
POST /medinfras/api/settingParameter/insert
POST /medinfras/api/settingParameter/update
POST /medinfras/api/settingParameter/delete
```

The generic router resolves the requested operation from the Business Layer registry.

## Operation Types

An operation can use either direct method mapping or a custom handler.

### Direct Method Mapping

For standard Business Layer methods:

```typescript
{
  route: 'get',
  summary: 'Get a setting parameter',
  method: 'GetSettingParameterDt',
  buildArgs: (body) => [
    body.healthcareId,
    body.parameterCode
  ],
  resultShape: 'object'
}
```

`buildArgs` maps the HTTP request body into the arguments expected by the .NET method.

### Custom Handler

For more complex workflows, an operation can define a `handler`.

```typescript
{
  route: 'custom',
  handler: async (body, ctx) => {
    const businessLayer = await ctx.getBusinessLayer();

    // Execute multiple Business Layer calls
    // Transform or join the results

    return result;
  }
}
```

The handler context provides:

* `getBusinessLayer()`
* `toJson()`
* `toJsonList()`

This supports workflows that require multiple .NET Business Layer calls, aggregation, transformation, or joining data from different sources.

## Filter Expression Builder

`core/filter-expression.util.ts` provides utilities for constructing filter-expression strings used by Business Layer list methods.

Supported operators include:

```text
=
!=
>
>=
<
<=
IN
LIKE
```

### AND

```typescript
buildFilterExpression(
  and(
    cond('HealthcareID', '=', '001'),
    cond('ParameterCode', 'IN', ['A', 'B'])
  )
);
```

Result:

```text
HealthcareID = '001' AND ParameterCode IN ('A', 'B')
```

### Nested AND / OR

```typescript
buildFilterExpression(
  and(
    cond('HealthcareID', '=', '001'),
    or(
      cond('ParameterCode', '=', 'A'),
      cond('ParameterCode', '=', 'B')
    )
  )
);
```

Result:

```text
HealthcareID = '001' AND (ParameterCode = 'A' OR ParameterCode = 'B')
```

### Raw Expressions

Trusted expressions can be passed directly:

```typescript
buildFilterExpression(
  raw("HealthcareID = '001'")
);
```

Raw expressions should only be used with trusted or constant values.

### No Filter

```typescript
buildFilterExpression(undefined);
```

Result:

```text
''
```

For methods that accept direct arguments rather than a `filterExpression`, the builder is not required.

Example:

```typescript
buildArgs: (body) => [
  body.healthcareId,
  body.parameterCode
]
```

## MCP Server

The project includes an MCP server implemented as a separate process.

### Development

```bash
npm run mcp:dev
```

### Production

```bash
npm run build
npm run mcp:start
```

### Endpoints

SSE connection:

```text
GET /medinfras/mcp/sse
```

MCP message endpoint:

```text
POST /medinfras/mcp/messages?sessionId=...
```

The MCP server automatically discovers tools from:

```text
src/mcp/tools/*.tool.ts
```

### MCP Tool Structure

Each MCP tool is defined in its own `*.tool.ts` file.

Example:

```text
src/mcp/tools/
└── get-patient-history.tool.ts
```

Tools can perform multiple Business Layer calls and combine the results into a single response.

## Patient History Tool

The `get_patient_history` tool retrieves patient history data through a multi-step Business Layer workflow.

The workflow consists of:

```text
vPreviousMedicalHistory
        │
        ├── GetvPastMedicalList
        │
        └── GetvVitalSignDtList
                │
                ▼
        Combined Patient History
```

The implementation supports:

1. Retrieving previous medical history records
2. Fetching related past medical data
3. Fetching related vital sign data
4. Joining the related records
5. Returning the combined result to the MCP client

The exact Business Layer method names and linking fields must match the target Medinfras assembly.

## Setup

### Requirements

* Node.js
* npm
* Windows environment
* Compatible .NET runtime
* Medinfras .NET Business Layer DLL
* `node-api-dotnet`

### Installation

```bash
npm install
```

Create the environment configuration:

```bash
cp .env.example .env
```

Configure:

```env
DOTNET_DLL_PATH=<absolute path to QIS.Medinfras.Data.Service.dll>
DOTNET_RUNTIME=net472
```

`DOTNET_RUNTIME` must match the target framework of the loaded DLL.

### Start REST API

Development:

```bash
npm run dev
```

Production:

```bash
npm run build
npm start
```

### Start MCP Server

Development:

```bash
npm run mcp:dev
```

Production:

```bash
npm run build
npm run mcp:start
```

## Local Endpoints

| Service            | Endpoint                                     |
| ------------------ | -------------------------------------------- |
| REST API           | `http://localhost:3000`                      |
| REST Documentation | `http://localhost:3000/medinfras/api/docs`   |
| REST Health Check  | `http://localhost:3000/medinfras/api/health` |
| MCP SSE            | `http://localhost:3100/medinfras/mcp/sse`    |

## Adding a Business Layer

Create a new definition anywhere under:

```text
src/business-layers/
```

Example:

```typescript
import { BusinessLayerDefinition } from '../types';

interface GetPatientBody {
  patientId: string;
}

const patient: BusinessLayerDefinition = {
  name: 'patient',

  operations: [
    {
      route: 'get',
      summary: 'Get a patient by ID',

      example: {
        patientId: 'P001'
      },

      validate: (body: GetPatientBody) =>
        !body?.patientId
          ? '"patientId" is required.'
          : null,

      method: 'GetPatientById',

      buildArgs: (body: GetPatientBody) => [
        body.patientId
      ],

      resultShape: 'object'
    }
  ]
};

export default patient;
```

This creates:

```text
POST /medinfras/api/patient/get
```

No additional router configuration is required.

The definition is automatically discovered when the application starts.

## Adding an MCP Tool

Create a new:

```text
*.tool.ts
```

file inside:

```text
src/mcp/tools/
```

The MCP tool registry automatically discovers the new tool on application startup.

Use the existing `get-patient-history.tool.ts` implementation as the structural reference for multi-step tools.

## API Examples

### List

```bash
curl -X POST http://localhost:3000/medinfras/api/settingParameter/list \
  -H "Content-Type: application/json" \
  -d '{
    "healthcareId": "001",
    "parameterCodes": [
      "FN0040",
      "LB0001"
    ]
  }'
```

### Get

```bash
curl -X POST http://localhost:3000/medinfras/api/settingParameter/get \
  -H "Content-Type: application/json" \
  -d '{
    "healthcareId": "001",
    "parameterCode": "FN0040"
  }'
```

### Delete

```bash
curl -X POST http://localhost:3000/medinfras/api/settingParameter/delete \
  -H "Content-Type: application/json" \
  -d '{
    "healthcareId": "001",
    "parameterCode": "FN0040"
  }'
```

## Development Notes

### .NET Object Marshalling

Insert and Update operations may require actual .NET objects rather than plain JavaScript objects.

For example:

```typescript
const asm = await getBusinessLayer();

const record = new asm.SettingParameterDt();

Object.assign(record, body);
```

Whether automatic marshalling works depends on the `node-api-dotnet` version and the target .NET assembly.

### Multiple Assemblies

The current .NET bridge loads and caches a single assembly.

If multiple DLLs are required, the cache should be keyed by DLL path.

### Authentication

Authentication is not included in the current implementation.

For REST, authentication can be applied globally through middleware in `app.ts`.

For MCP, authentication should be handled at the SSE/transport layer according to the deployment architecture.

### Testing

No test runner is currently included.

The .NET bridge is isolated in:

```text
core/dotnet-bridge.ts
```

This allows Business Layer definitions and MCP tools to be tested with a mocked bridge without requiring the actual .NET runtime or DLL.

### Logging

The current implementation uses:

```typescript
console.log
console.error
```

For structured production logging, a logger such as `pino` or `winston` can be introduced.

### CORS

CORS is currently enabled broadly for development:

```typescript
cors()
```

Production deployments should restrict allowed origins.

### MCP Transport

The current implementation uses the classic MCP SSE transport:

```text
GET  /sse
POST /messages
```

The MCP SDK also supports Streamable HTTP, which can be adopted later if a single-endpoint transport is preferred.
