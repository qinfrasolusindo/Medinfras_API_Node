import { BusinessLayerDefinition } from "./types";

// INI CODE ADALAH SALAH SATU CONTOH DEFINISI BUSINESS LAYER UNTUK "patientHistory".

interface GetBody {
  mrn?: number;
  patientName?: string;
  dateFrom?: string;
  dateTo?: string;
  LastNVisits?: number;
}

const patientHistory: BusinessLayerDefinition = {
  name: "patientHistory",
  operations: [
    {
      route: "get",
      summary:
        "Get a patient's medical history using MRN or patient name, optionally filtered by visit date range or limited to the most recent visits.",
      example: { mrn: 123456, patientName: "John Doe", dateFrom: "2023-01-01", dateTo: "2023-12-31", LastNVisits: 5 },
      validate: (body: GetBody) => {
        if (!body?.mrn && !body?.patientName) {
          return 'At least one of "mrn" or "patientName" must be provided.';
        }
        if (body?.dateFrom && !/^\d{4}-\d{2}-\d{2}$/.test(body.dateFrom)) {
          return '"dateFrom" must use YYYY-MM-DD format.';
        }
        if (body?.dateTo && !/^\d{4}-\d{2}-\d{2}$/.test(body.dateTo)) {
          return '"dateTo" must use YYYY-MM-DD format.';
        }
        return null;
      },
      method: "GetSettingParameterDt",
      buildArgs: (body: GetBody) => [
        body.mrn ?? null,
        body.patientName ?? null,
        body.dateFrom ?? null,
        body.dateTo ?? null,
        body.LastNVisits ?? 0,
      ],
      resultShape: "object",
    },
  ],
};

export default patientHistory;
