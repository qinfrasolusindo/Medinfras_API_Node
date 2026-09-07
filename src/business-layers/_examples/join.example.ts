import {
  and,
  buildFilterExpression,
  cond,
} from "../../core/filter-expression.util";
import { BusinessLayerDefinition } from "../types";

// kalau misal harus lebih dari 1 kali join, bisa bikin beberapa business layer definition,
// misal: consultVisit.definition.ts, registration.definition.ts, dll. Lalu di file join.example.ts
// ini kita bisa import dan gabungkan sesuai kebutuhan.
interface ConsultVisitJoinBody {
  registrationId: string;
}

const consultVisitJoinExample: BusinessLayerDefinition = {
  name: "consultVisit",
  operations: [
    {
      route: "withRegistration",
      summary: "Get a consult visit joined with its registration record",
      example: { registrationId: "REG0001" },

      validate: (body: ConsultVisitJoinBody) => {
        if (!body?.registrationId) return '"registrationId" is required.';
        return null;
      },

      handler: async (body: ConsultVisitJoinBody, ctx) => {
        const businessLayer = await ctx.getBusinessLayer();

        const consultVisitFilter = buildFilterExpression(
          and(cond("RegistrationID", "=", body.registrationId)),
        );
        const consultVisitsResult =
          businessLayer.GetvConsultVisitList(consultVisitFilter);
        const consultVisits =
          await ctx.toJsonList<Record<string, unknown>>(consultVisitsResult);

        const registrationResult = businessLayer.GetRegistration(
          body.registrationId,
        );
        const registration =
          await ctx.toJson<Record<string, unknown>>(registrationResult);
        return {
          registration,
          consultVisits,
        };
      },
    },
  ],
};

export default consultVisitJoinExample;
