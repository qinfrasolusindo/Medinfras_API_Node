/**
 * Builds filter-expression strings like:
 *   HealthcareID = '001' AND ParameterCode IN ('FN0040', 'LB0001')
 *
 * This exists so individual services never hand-concatenate strings from
 * request input (which is how you get injection-style bugs in the .NET
 * filter parser). Every business-layer service that needs a filter
 * expression should build it through this helper.
 */

export type FilterOperator = '=' | '!=' | '>' | '>=' | '<' | '<=' | 'IN' | 'LIKE';

export interface FilterCondition {
  field: string;
  operator: FilterOperator;
  value: string | number | Array<string | number>;
}

function escapeStringValue(value: string | number): string {
  return String(value).replace(/'/g, "''");
}

function formatValue(operator: FilterOperator, value: FilterCondition['value']): string {
  if (operator === 'IN') {
    const values = Array.isArray(value) ? value : [value];
    return `(${values.map((v) => `'${escapeStringValue(v)}'`).join(', ')})`;
  }

  if (typeof value === 'number') {
    return `${value}`;
  }

  return `'${escapeStringValue(value as string)}'`;
}

export function buildFilterExpression(conditions: FilterCondition[]): string {
  return conditions
    .map((condition) => `${condition.field} ${condition.operator} ${formatValue(condition.operator, condition.value)}`)
    .join(' AND ');
}
