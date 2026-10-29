// Free-plan limits for WAF custom rules. Cloudflare's Free plan allows five
// custom rules and expressions of roughly 4,096 characters (about 200 IPv4
// addresses inline). These are limits for warnings only — nothing here talks
// to Cloudflare.

export const MAX_CUSTOM_RULES = 5;
export const MAX_EXPRESSION_CHARS = 4096;
export const WARN_RATIO = 0.9;
export const IPV4_HINT = "~200 IPv4 addresses fit in one expression";

export function countRules(rules) {
  return Array.isArray(rules) ? rules.length : 0;
}

export function charsOf(expression) {
  return typeof expression === "string" ? expression.length : 0;
}

export function usageRatio(chars) {
  return Math.min(1, chars / MAX_EXPRESSION_CHARS);
}

export function isOverLimit(chars) {
  return chars > MAX_EXPRESSION_CHARS;
}

export function isNearLimit(chars) {
  return chars >= Math.ceil(MAX_EXPRESSION_CHARS * WARN_RATIO);
}

export function summarizeLimits(rules) {
  const perRule = rules.map((rule) => ({
    ref: rule.ref,
    chars: charsOf(rule.expression),
    over: isOverLimit(charsOf(rule.expression)),
    near: isNearLimit(charsOf(rule.expression)),
  }));

  return {
    rules: countRules(rules),
    rulesOver: countRules(rules) > MAX_CUSTOM_RULES,
    maxRules: MAX_CUSTOM_RULES,
    maxChars: MAX_EXPRESSION_CHARS,
    perRule,
    overLimit: perRule.some((item) => item.over),
    nearLimit: perRule.some((item) => item.near),
  };
}
