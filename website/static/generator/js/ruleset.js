// Rule-set model: the page's rules come either from the options builder or
// from a release profile under profiles/. Both produce one shape so the UI,
// the renderers and the tests agree on what a rule is.
//
// Loading a release is a one-way import: expressions are kept exactly as the
// file wrote them (the character count and the description hash have to match
// what Cloudflare receives), while the envelope is normalised to the current
// v207 shape — `priority` is dropped, `logging` is defaulted on, and a `skip`
// rule keeps its action parameters or gains `{ ruleset: "current" }`.
//
// No network access, no DOM access.

import { REF_PREFIX, RULE_TITLES, buildRules, isValidTemplateVersion } from "./rules.js";

const KNOWN_ACTIONS = ["skip", "block", "managed_challenge", "js_challenge", "challenge", "log"];

/** Rules built from the option form, in the shared shape. */
export function rulesFromOptions(options) {
  return buildRules(options).map((rule) => ({
    ref: rule.ref,
    ruleNumber: rule.ruleNumber,
    action: rule.action,
    label: rule.label,
    expression: rule.expression,
    actionParameters: rule.actionParameters ? { ...rule.actionParameters } : undefined,
    enabled: true,
    logging: true,
    origin: "fields",
  }));
}

/**
 * Version label for a profile: its first rule's `rule_version` when that is a
 * usable stamp, otherwise the caller's fallback (the filename, for the
 * profiles that predate the field — mwp-rules-v201-events.json).
 */
export function versionFor(profile, fallback = "") {
  const rules = Array.isArray(profile?.rules) ? profile.rules : [];
  for (const rule of rules) {
    const value = String(rule?.rule_version ?? "").trim();
    if (value && isValidTemplateVersion(value)) return value;
  }
  return String(fallback || "").trim();
}

/**
 * Normalise one profile rule to the shared shape, in the current v207
 * envelope. Header fields the current format does not carry (`priority`) are
 * dropped on purpose: the profile export and the API body are always v207.
 */
export function normalizeRule(raw, index) {
  const number = String(raw?.rule_number ?? raw?.ruleNumber ?? index + 1).trim();
  const action = String(raw?.action ?? "").trim();
  const known = KNOWN_ACTIONS.includes(action);
  const rule = {
    ref: `${REF_PREFIX}r${number}`,
    ruleNumber: number,
    action: known ? action : "block",
    label: RULE_TITLES[number] || String(raw?.description ?? `Rule ${number}`).trim(),
    expression: String(raw?.expression ?? ""),
    enabled: raw?.enabled === undefined ? true : Boolean(raw.enabled),
    logging: raw?.logging?.enabled === undefined ? true : Boolean(raw.logging.enabled),
    origin: "loaded",
  };
  if (!known) rule.actionInvalid = action;
  if (rule.action === "skip") {
    const params = raw?.action_parameters;
    rule.actionParameters = params && typeof params === "object" ? { ...params } : { ruleset: "current" };
  }
  return rule;
}

/** Rules from a v3 profile, in the shared shape. */
export function rulesFromProfile(profile) {
  const list = Array.isArray(profile?.rules) ? profile.rules : [];
  return list.map((raw, index) => normalizeRule(raw, index));
}

/** Rebuild one rule from the options, leaving the rest of the set untouched. */
export function rebuildRule(rules, ref, options) {
  const fresh = rulesFromOptions(options).find((rule) => rule.ref === ref);
  return rules.map((rule) => {
    if (rule.ref !== ref) return rule;
    return fresh ? { ...fresh, origin: "fields" } : null;
  }).filter(Boolean);
}

/** True when a rule is no longer what the option fields would produce. */
export function isHandEdited(rule) {
  return rule.origin === "manual";
}
