/**
 * REFERENCE EXAMPLE - not auto-mounted (filename ends in .example.ts, not
 * .definition.ts, so business-layers/index.ts skips it).
 *
 * Shows the pattern for joining two business layers in one endpoint, e.g.
 * ConsultVisit + Registration. Copy this file to
 * `consult-visit.definition.ts` (or wherever makes sense), rename the
 * export, and replace the placeholder method/field names with the real
 * ones from your DLL.
 *
 * Whenever an operation needs more than one .NET call - a join, a
 * multi-step lookup, custom shaping - reach for `handler` instead of
 * `method` + `buildArgs`. The router calls it with (body, ctx), where ctx
 * gives you the same getBusinessLayer()/toJson()/toJsonList() helpers every
 * simple operation uses internally.
 */

import { and, buildFilterExpression, cond } from '../../core/filter-expression.util';
import { BusinessLayerDefinition } from '../types';

interface ConsultVisitJoinBody {
  registrationId: string;
}

const consultVisitJoinExample: BusinessLayerDefinition = {
  name: 'consultVisit',
  operations: [
    {
      route: 'withRegistration',
      summary: 'Get a consult visit joined with its registration record',
      example: { registrationId: 'REG0001' },

      validate: (body: ConsultVisitJoinBody) => {
        if (!body?.registrationId) return '"registrationId" is required.';
        return null;
      },

      // Advanced mode: no `method`/`buildArgs` here - `handler` does everything.
      handler: async (body: ConsultVisitJoinBody, ctx) => {
        const businessLayer = await ctx.getBusinessLayer();

        // 1) Fetch the consult visit(s) for this registration.
        //    Replace 'GetvConsultVisitList' / field names with the real ones.
        const consultVisitFilter = buildFilterExpression(
          and(cond('RegistrationID', '=', body.registrationId))
        );
        const consultVisitsResult = businessLayer.GetvConsultVisitList(consultVisitFilter);
        const consultVisits = await ctx.toJsonList<Record<string, unknown>>(consultVisitsResult);

        // 2) Fetch the matching registration record.
        //    Replace 'GetRegistration' with the real single-record method.
        const registrationResult = businessLayer.GetRegistration(body.registrationId);
        const registration = await ctx.toJson<Record<string, unknown>>(registrationResult);

        // 3) Join them into one payload however the consumer needs it.
        return {
          registration,
          consultVisits,
        };
      },
    },
  ],
};

export default consultVisitJoinExample;
