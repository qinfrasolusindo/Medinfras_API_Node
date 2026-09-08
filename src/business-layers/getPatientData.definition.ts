import { BusinessLayerDefinition } from "./types";

// INI CODE ADALAH SALAH SATU CONTOH DEFINISI BUSINESS LAYER UNTUK "patientData".

interface GetBody {
  limit?: number;
  lastVisitID?: number;
}

const ExtractPatientData: BusinessLayerDefinition = {
  name: "ExtractPatientData",
  operations: [
    {
      route: "get",
      summary:
        "Get patient data with optional limit and last visit ID for RAG data extraction.",
      example: {
        limit: 100,
        lastVisitID: 123,
      },
      validate: (body: GetBody) => {
        if (
          body.limit !== undefined &&
          (typeof body.limit !== "number" || body.limit <= 0)
        ) {
          return '"limit" must be a positive number if provided.';
        }
        if (
          body.lastVisitID !== undefined &&
          typeof body.lastVisitID !== "number"
        ) {
          return '"lastVisitID" must be a positive number if provided.';
        }
        return null;
      },
      handler: async (body: GetBody, ctx) => {
        const businessLayer = await ctx.getBusinessLayer();
        const method = businessLayer["GetPatientDataMAIA"];

        if (typeof method !== "function") {
          throw new Error(
            '.NET method "GetPatientDataMAIA" was not found on BusinessLayer.',
          );
        }

        const patientData = method(body.limit ?? null, body.lastVisitID ?? 0);

        const data = patientData.flatMap((item: { JsonResult: string }) =>
          JSON.parse(item.JsonResult),
        );

        return data;
      },
    },
  ],
};

export default ExtractPatientData;
