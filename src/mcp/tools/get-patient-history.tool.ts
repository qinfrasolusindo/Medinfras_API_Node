import { z } from "zod";
import { McpToolDefinition } from "../types";

const DOTNET_METHODS = {
  patientHistory: "GetPatientHistoryMCP",
};

interface GetPatientHistoryArgs {
  mrn?: number;
  patientName?: string;
  dateFrom?: string;
  dateTo?: string;
  LastNVisits?: number;
}

const getPatientHistory: McpToolDefinition<GetPatientHistoryArgs> = {
  name: "get_patient_history",

  description:
    "Retrieve a patient's medical history using MRN or patient name. " +
    "MRN and patient name are optional individually, but at least one must be provided. " +
    "The result can optionally be filtered by visit date range or limited to the most recent visits. " +
    "History is selected at the visit/header level first, then related clinical details are returned for those visits. " +
    "Use this tool to review diagnoses, symptoms, vital signs, laboratory results, medications, procedures, notes, discharge information, and other recorded visit details.",

  inputSchema: {
    mrn: z
      .number()
      .int()
      .positive()
      .optional()
      .describe(
        "Patient MRN. Prefer MRN when available because it uniquely identifies the patient.",
      ),

    patientName: z
      .string()
      .trim()
      .min(1)
      .optional()
      .describe(
        "Patient name. Use when MRN is not available. Partial name matching may be supported.",
      ),

    dateFrom: z
      .string()
      .regex(/^\d{4}-\d{2}-\d{2}$/, "Date must use YYYY-MM-DD format.")
      .optional()
      .describe(
        "Optional start date of the visit history period in YYYY-MM-DD format.",
      ),

    dateTo: z
      .string()
      .regex(/^\d{4}-\d{2}-\d{2}$/, "Date must use YYYY-MM-DD format.")
      .optional()
      .describe(
        "Optional end date of the visit history period in YYYY-MM-DD format.",
      ),

    LastNVisits: z
      .number()
      .int()
      .optional()
      .describe(
        "Optional number of most recent visits to retrieve. Example: 3 means the 3 most recent visits including their related details.",
      ),
  },

  handler: async (args, ctx) => {
    const { mrn, patientName, dateFrom, dateTo, LastNVisits } = args;

    // At least one patient identifier is required.
    if (mrn == null && !patientName) {
      throw new Error("Either MRN or patientName must be provided.");
    }

    const businessLayer = await ctx.getBusinessLayer();

    const method = businessLayer[DOTNET_METHODS.patientHistory];

    if (typeof method !== "function") {
      throw new Error(
        `.NET method "${DOTNET_METHODS.patientHistory}" was not found on BusinessLayer.`,
      );
    }

    const historyResult = method(
      mrn ?? null,
      patientName ?? "",
      dateFrom ?? null,
      dateTo ?? null,
      LastNVisits ?? 0,
    );

    const data = historyResult.map((item: { JsonResult: string }) => ({
      ...item,
      JsonResult: JSON.parse(item.JsonResult),
    }));

    return {
      historyResult: data,
    };
  },
};

export default getPatientHistory;
