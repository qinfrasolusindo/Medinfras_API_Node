/**
 * Builds .NET-style filter-expression strings, e.g.:
 *   HealthcareID = '001' AND (ParameterCode IN ('FN0040','LB0001') OR ParameterCode LIKE 'EM%')
 *
 * Covers the range of cases business layers actually need:
 *   - a single condition                              -> cond(...)
 *   - AND of several conditions                        -> and(cond(...), cond(...))
 *   - OR, and AND/OR nested arbitrarily deep            -> and(cond(...), or(cond(...), cond(...)))
 *   - a hand-written fragment that don't want built      -> raw("HealthcareID = '001'")
 *   - no filter at all (method that takes "get everything") -> pass undefined/null, returns ''
 *
 * Every *value* still goes through quoting/escaping - only `raw()` bypasses
 * it, so use raw() only for fragments thats been trusted (e.g. constants in 
 * code), never directly on unescaped user input.
 */

export type FilterOperator = '=' | '!=' | '>' | '>=' | '<' | '<=' | 'IN' | 'LIKE';

export interface FilterCondition {
  field: string;
  operator: FilterOperator;
  value: string | number | Array<string | number>;
}

export type FilterNode =
  | { type: 'condition'; condition: FilterCondition }
  | { type: 'raw'; expression: string }
  | { type: 'group'; join: 'AND' | 'OR'; nodes: FilterNode[] };


export function cond(field: string, operator: FilterOperator, value: FilterCondition['value']): FilterNode {
  return { type: 'condition', condition: { field, operator, value } };
}


export function raw(expression: string): FilterNode {
  return { type: 'raw', expression };
}


export function and(...nodes: FilterNode[]): FilterNode {
  return { type: 'group', join: 'AND', nodes };
}

export function or(...nodes: FilterNode[]): FilterNode {
  return { type: 'group', join: 'OR', nodes };
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

function render(node: FilterNode): string {
  if (node.type === 'condition') {
    const { field, operator, value } = node.condition;
    return `${field} ${operator} ${formatValue(operator, value)}`;
  }

  if (node.type === 'raw') {
    return node.expression;
  }

  // group
  const parts = node.nodes.map(render).filter((part) => part.length > 0);
  if (parts.length === 0) return '';
  if (parts.length === 1) return parts[0];
  return `(${parts.join(` ${node.join} `)})`;
}

/**
 * Renders a filter tree to a string. Pass undefined/null (or an empty
 * and()/or()) for "no filter" -> returns ''. Also accepts a plain array of
 * conditions as shorthand for and(...conditions).
 */
export function buildFilterExpression(
  input: FilterNode | FilterCondition[] | undefined | null
): string {
  if (!input) return '';

  if (Array.isArray(input)) {
    return render(and(...input.map((c) => cond(c.field, c.operator, c.value))));
  }

  return render(input);
}
