// Output renderers: Cloudflare dashboard expressions, Rulesets API JSON, an
// upgrade manifest, and a v3 profile for cloudflare-wordpress-rules.sh.
//
// Descriptions carry the template version and a hash of the expression:
//   lmt-r1 | t207-3fa9c2d1 | Allow trusted IPs, ...
// A later upgrade run can therefore tell an untouched generated rule from one
// the account owner edited, and leave client-added rules alone.

import { PHASE, ENTRYPOINT_PATH, REF_PREFIX } from "./rules.js";

export const CLOUDFLARE_API_BASE = "https://api.cloudflare.com/client/v4";

/** FNV-1a (32-bit) as 8 lowercase hex characters — stable and dependency-free. */
export function fnv1a8(value) {
  let hash = 0x811c9dc5;
  for (let index = 0; index < value.length; index += 1) {
    hash ^= value.charCodeAt(index);
    hash = Math.imul(hash, 0x01000193) >>> 0;
  }
  return hash.toString(16).padStart(8, "0");
}

export function descriptionTag(rule, templateVersion) {
  return `t${templateVersion}-${fnv1a8(rule.expression)}`;
}

export function ruleDescription(rule, templateVersion) {
  return `${rule.ref} | ${descriptionTag(rule, templateVersion)} | ${rule.label}`;
}

export function toCloudflareRule(rule, templateVersion) {
  const output = { action: rule.action };
  if (rule.actionParameters) output.action_parameters = rule.actionParameters;
  output.description = ruleDescription(rule, templateVersion);
  output.enabled = true;
  output.expression = rule.expression;
  output.logging = { enabled: true };
  output.ref = rule.ref;
  return output;
}

/** Request body for PUT .../rulesets/phases/http_request_firewall_custom/entrypoint */
export function toApiBody(rules, templateVersion) {
  return { rules: rules.map((rule) => toCloudflareRule(rule, templateVersion)) };
}

export function entrypointUrl(zoneId = "{zone_id}") {
  return `${CLOUDFLARE_API_BASE}/zones/${zoneId}/${ENTRYPOINT_PATH}`;
}

export function toCurl(body, zoneId = "{zone_id}") {
  return [
    `curl -X PUT "${entrypointUrl(zoneId)}" \\`,
    '  -H "Authorization: Bearer $CF_API_TOKEN" \\',
    '  -H "Content-Type: application/json" \\',
    "  --data @ruleset.json",
  ].join("\n");
}

/** Small manifest an upgrade run can diff against the live ruleset. */
export function toManifest(rules, templateVersion) {
  return {
    templateVersion: String(templateVersion),
    refPrefix: REF_PREFIX,
    phase: PHASE,
    rules: rules.map((rule) => ({
      ref: rule.ref,
      hash: fnv1a8(rule.expression),
      action: rule.action,
      description: ruleDescription(rule, templateVersion),
    })),
  };
}

/**
 * Upgrade guidance encoded as data so the UI and docs cannot drift:
 * same ref + same hash = replace, same ref + other hash = client-modified
 * (preserve), unknown ref = client-added (preserve).
 */
export const UPGRADE_RULES = [
  {
    match: "ref starts with lmt- and hash equals the manifest",
    action: "Replace — the rule is untouched since it was generated.",
  },
  {
    match: "ref starts with lmt- and hash differs from the manifest",
    action: "Preserve and review — the account owner edited this rule.",
  },
  {
    match: "ref does not start with lmt- (or has none)",
    action: "Preserve — client-added rule, never part of the template.",
  },
];

/** v3 profile JSON, the format cloudflare-wordpress-rules.sh consumes. */
export function toV3Profile(profileName, description, rules, templateVersion) {
  return {
    name: profileName,
    description,
    rules: rules.map((rule) => {
      const entry = {
        rule_number: rule.ruleNumber,
        rule_version: String(templateVersion),
        description: ruleDescription(rule, templateVersion),
        expression: rule.expression,
        action: rule.action,
        enabled: true,
        logging: { enabled: true },
      };
      if (rule.actionParameters) entry.action_parameters = rule.actionParameters;
      return entry;
    }),
    version: 3,
    phase: PHASE,
    profiles_version: "3.1.0",
  };
}

export function slugify(value) {
  return String(value)
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, "-")
    .replace(/^-+|-+$/g, "") || "profile";
}
