import { buildFilterExpression } from '../core/filter-expression.util';
import { BusinessLayerDefinition } from './types';

interface SettingParameterBody {
  healthcareId: string;
  parameterCodes: string[];
}

const settingParameter: BusinessLayerDefinition<SettingParameterBody> = {
  name: 'settingParameter',
  method: 'GetSettingParameterDtList',
  summary: 'Get setting parameters filtered by healthcare ID and parameter codes',
  example: {
    healthcareId: '001',
    parameterCodes: ['FN0040', 'LB0001', 'IS0001', 'EM0063', 'EM0069', 'OP0016'],
  },

  validate: (body) => {
    if (typeof body?.healthcareId !== 'string' || !body.healthcareId.trim()) {
      return '"healthcareId" is required and must be a non-empty string.';
    }
    if (!Array.isArray(body?.parameterCodes) || body.parameterCodes.length === 0) {
      return '"parameterCodes" is required and must be a non-empty array of strings.';
    }
    return null;
  },

  buildArgs: (body) => [
    buildFilterExpression([
      { field: 'HealthcareID', operator: '=', value: body.healthcareId },
      { field: 'ParameterCode', operator: 'IN', value: body.parameterCodes },
    ]),
  ],
};

export default settingParameter;
