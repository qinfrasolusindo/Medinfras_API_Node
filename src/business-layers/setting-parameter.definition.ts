import { and, buildFilterExpression, cond } from '../core/filter-expression.util';
import { BusinessLayerDefinition } from './types';

// INI CODE ADALAH SALAH SATU CONTOH DEFINISI BUSINESS LAYER UNTUK "settingParameter".
interface SettingParameterRecord {
  HealthcareID: string;
  ParameterCode: string;
  [key: string]: unknown;
}

interface ListBody {
  healthcareId: string;
  parameterCodes: string[];
}

interface GetBody {
  healthcareId: string;
  parameterCode: string;
}

type DeleteBody = GetBody;

const settingParameter: BusinessLayerDefinition = {
  name: 'settingParameter',
  operations: [
    {
      route: 'list',
      summary: 'Get setting parameters filtered by healthcare ID and parameter codes',
      example: {
        healthcareId: '001',
        parameterCodes: ['FN0040', 'LB0001', 'IS0001', 'EM0063', 'EM0069', 'OP0016'],
      },
      validate: (body: ListBody) => {
        if (typeof body?.healthcareId !== 'string' || !body.healthcareId.trim()) {
          return '"healthcareId" is required and must be a non-empty string.';
        }
        if (!Array.isArray(body?.parameterCodes) || body.parameterCodes.length === 0) {
          return '"parameterCodes" is required and must be a non-empty array of strings.';
        }
        return null;
      },
      method: 'GetSettingParameterDtList',
      buildArgs: (body: ListBody) => [
        buildFilterExpression(
          and(
            cond('HealthcareID', '=', body.healthcareId),
            cond('ParameterCode', 'IN', body.parameterCodes)
          )
        ),
      ],
      resultShape: 'list',
    },

    {
      route: 'get',
      summary: 'Get a single setting parameter by exact healthcare ID + parameter code',
      example: { healthcareId: '001', parameterCode: 'FN0040' },
      validate: (body: GetBody) => {
        if (!body?.healthcareId) return '"healthcareId" is required.';
        if (!body?.parameterCode) return '"parameterCode" is required.';
        return null;
      },
      method: 'GetSettingParameterDt',
      buildArgs: (body: GetBody) => [body.healthcareId, body.parameterCode],
      resultShape: 'object',
    },

    {
      route: 'insert',
      summary: 'Insert a new setting parameter record',
      example: { HealthcareID: '001', ParameterCode: 'FN0040' },
      validate: (body: SettingParameterRecord) => {
        if (!body?.HealthcareID) return '"HealthcareID" is required.';
        if (!body?.ParameterCode) return '"ParameterCode" is required.';
        return null;
      },
      method: 'InsertSettingParameterDt',
      // NOTE: InsertSettingParameterDt(SettingParameterDt record) expects a
      // real .NET SettingParameterDt object. See the "record marshalling"
      // note in README section 4 - plain JS objects may not marshal
      // automatically depending on your node-api-dotnet version; you may
      // need to construct it via the assembly instead, e.g.:
      //   const asm = await getAssembly(); const rec = new asm.SettingParameterDt(); ...
      buildArgs: (body: SettingParameterRecord) => [body],
      resultShape: 'raw', // returns int (rows affected)
    },

    {
      route: 'update',
      summary: 'Update an existing setting parameter record',
      example: { HealthcareID: '001', ParameterCode: 'FN0040' },
      validate: (body: SettingParameterRecord) => {
        if (!body?.HealthcareID) return '"HealthcareID" is required.';
        if (!body?.ParameterCode) return '"ParameterCode" is required.';
        return null;
      },
      method: 'UpdateSettingParameterDt',
      // Same record-marshalling note as insert, above.
      buildArgs: (body: SettingParameterRecord) => [body],
      resultShape: 'raw', // returns int (rows affected)
    },

    {
      route: 'delete',
      summary: 'Delete a setting parameter by exact healthcare ID + parameter code',
      example: { healthcareId: '001', parameterCode: 'FN0040' },
      validate: (body: DeleteBody) => {
        if (!body?.healthcareId) return '"healthcareId" is required.';
        if (!body?.parameterCode) return '"parameterCode" is required.';
        return null;
      },
      method: 'DeleteSettingParameterDt',
      buildArgs: (body: DeleteBody) => [body.healthcareId, body.parameterCode],
      resultShape: 'raw', // returns int (rows affected)
    },
  ],
};

export default settingParameter;
