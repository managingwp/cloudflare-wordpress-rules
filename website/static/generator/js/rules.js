// Pure rule builder for the Cloudflare WordPress WAF rule set (R1–R4).
//
// This module is the single source of truth for rule expressions. It runs
// unchanged in the browser and under Node (see tests/generator/*.test.mjs),
// which is what keeps the static generator and profiles/*.json in step.
//
// No network access, no DOM access.

export const PHASE = "http_request_firewall_custom";
export const ENTRYPOINT_PATH =
  "rulesets/phases/http_request_firewall_custom/entrypoint";
export const REF_PREFIX = "lmt-";

// Rules version the bundled presets reproduce. Kept in step with
// profiles/default.json by tests/generator/presets.test.mjs.
export const DEFAULT_TEMPLATE_VERSION = "207";

export const RULE_TITLES = {
  1: "Allow trusted IPs, query strings, user agents and verified bots",
  2: "Block abusive paths and ASNs",
  3: "Challenge login and admin",
  4: "Challenge outside allowed countries",
};

export const GEO_ACTIONS = ["js_challenge", "managed_challenge", "challenge", "block", "log"];

export const DEFAULT_OPTIONS = {
  trustedIps: {
    inline: [],
    ipList: { enabled: false, name: "" },
  },
  allowedQueryStrings: [],
  allowedUserAgents: [],
  allowVerifiedBots: true,
  allowTwoFactorActions: false,
  blockedPaths: [],
  blockXmlrpc: true,
  blockedAsns: [],
  challengeLoginAdmin: true,
  geo: { enabled: true, action: "js_challenge", allowedCountries: ["CA", "US"] },
};

const OPTION_KEYS = Object.keys(DEFAULT_OPTIONS);
const GEO_KEYS = Object.keys(DEFAULT_OPTIONS.geo);
const TRUSTED_IP_KEYS = Object.keys(DEFAULT_OPTIONS.trustedIps);
const IP_LIST_KEYS = Object.keys(DEFAULT_OPTIONS.trustedIps.ipList);

// -- helpers ---------------------------------------------------------------

export function cloneOptions(options) {
  return JSON.parse(JSON.stringify(options));
}

export function unique(values) {
  const seen = new Set();
  const out = [];
  for (const value of values) {
    const key = value.toLowerCase();
    if (seen.has(key)) continue;
    seen.add(key);
    out.push(value);
  }
  return out;
}

/** Split a textarea value into cleaned entries: one per line or comma. */
export function splitList(text) {
  if (typeof text !== "string") return [];
  return text
    .split(/[\n,]+/)
    .map((item) => item.trim())
    .filter((item) => item.length > 0);
}

export function escapeValue(value) {
  return String(value).replace(/\\/g, "\\\\").replace(/"/g, '\\"');
}

export function isValidIpv4(value) {
  const match = /^(\d{1,3})\.(\d{1,3})\.(\d{1,3})\.(\d{1,3})(?:\/(\d{1,2}))?$/.exec(value);
  if (!match) return false;
  for (let i = 1; i <= 4; i += 1) {
    if (Number(match[i]) > 255) return false;
  }
  if (match[5] !== undefined && Number(match[5]) > 32) return false;
  return true;
}

export function isValidIpv6(value) {
  const [address, prefix] = value.split("/");
  if (prefix !== undefined && !/^\d{1,3}$/.test(prefix)) return false;
  if (prefix !== undefined && Number(prefix) > 128) return false;
  if (!/^[0-9A-Fa-f:]+$/.test(address)) return false;
  if ((address.match(/::/g) || []).length > 1) return false;
  const parts = address.split("::");
  const head = parts[0] ? parts[0].split(":") : [];
  const tail = parts[1] ? parts[1].split(":") : [];
  if (parts.length === 2) {
    if (head.length + tail.length > 7) return false;
  } else if (head.length !== 8) {
    return false;
  }
  return [...head, ...tail].every((group) => /^[0-9A-Fa-f]{1,4}$/.test(group));
}

export function isValidIp(value) {
  return isValidIpv4(value) || isValidIpv6(value);
}

export function isValidListName(value) {
  return /^[a-z0-9_]{1,64}$/.test(value);
}

export function isValidAsn(value) {
  return /^\d{1,10}$/.test(value) && Number(value) >= 1 && Number(value) <= 4294967295;
}

export function isValidPath(value) {
  return /^\/[^\s"{}]*$/.test(value);
}

export function isValidCountry(value) {
  return /^[A-Z]{2}$/.test(value);
}

export function isValidUserAgent(value) {
  return value.length > 0 && value.length <= 200 && !/[\u0000-\u001f]/.test(value);
}

export function isValidQueryString(value) {
  return value.length > 0 && value.length <= 200 && !/[\u0000-\u001f]/.test(value);
}

export function isValidTemplateVersion(value) {
  return /^[0-9]{1,6}$/.test(value) || /^[a-zA-Z0-9._-]{1,16}$/.test(value);
}

// -- options ---------------------------------------------------------------

export function mergeOptions(base, override = {}) {
  const out = cloneOptions(base);
  for (const key of Object.keys(override)) {
    if (!OPTION_KEYS.includes(key)) continue;
    const value = override[key];
    if (key === "trustedIps") {
      const trusted = value || {};
      if (Array.isArray(trusted.inline)) out.trustedIps.inline = [...trusted.inline];
      if (trusted.ipList) {
        if (typeof trusted.ipList.enabled === "boolean") {
          out.trustedIps.ipList.enabled = trusted.ipList.enabled;
        }
        if (typeof trusted.ipList.name === "string") {
          out.trustedIps.ipList.name = trusted.ipList.name;
        }
      }
    } else if (key === "geo") {
      const geo = value || {};
      for (const geoKey of GEO_KEYS) {
        if (geo[geoKey] === undefined) continue;
        out.geo[geoKey] = Array.isArray(geo[geoKey]) ? [...geo[geoKey]] : geo[geoKey];
      }
    } else if (Array.isArray(value)) {
      out[key] = [...value];
    } else if (value !== undefined) {
      out[key] = value;
    }
  }
  return out;
}

export function normalizeOptions(options) {
  const merged = mergeOptions(DEFAULT_OPTIONS, options || {});
  return {
    trustedIps: {
      inline: unique(merged.trustedIps.inline.map((ip) => String(ip).trim()).filter(Boolean)),
      ipList: {
        enabled: Boolean(merged.trustedIps.ipList.enabled),
        name: String(merged.trustedIps.ipList.name || "").trim().toLowerCase(),
      },
    },
    allowedQueryStrings: unique(
      merged.allowedQueryStrings.map((value) => String(value).trim()).filter(Boolean),
    ),
    allowedUserAgents: unique(
      merged.allowedUserAgents.map((value) => String(value).trim()).filter(Boolean),
    ),
    allowVerifiedBots: Boolean(merged.allowVerifiedBots),
    allowTwoFactorActions: Boolean(merged.allowTwoFactorActions),
    blockedPaths: unique(
      merged.blockedPaths.map((value) => String(value).trim()).filter(Boolean),
    ),
    blockXmlrpc: Boolean(merged.blockXmlrpc),
    blockedAsns: unique(
      merged.blockedAsns.map((value) => String(value).trim()).filter(Boolean),
    ),
    challengeLoginAdmin: Boolean(merged.challengeLoginAdmin),
    geo: {
      enabled: Boolean(merged.geo.enabled),
      action: GEO_ACTIONS.includes(merged.geo.action) ? merged.geo.action : "js_challenge",
      allowedCountries: unique(
        merged.geo.allowedCountries
          .map((value) => String(value).trim().toUpperCase())
          .filter(Boolean),
      ).sort(),
    },
  };
}

/**
 * Validate options, returning field-level errors and warnings.
 * Paths use dotted notation so the UI can attach messages to controls.
 */
export function validateOptions(options) {
  const opts = normalizeOptions(options);
  const errors = [];
  const warnings = [];

  for (const ip of opts.trustedIps.inline) {
    if (!isValidIp(ip)) errors.push({ path: "trustedIps.inline", message: `Not a valid IP or CIDR range: ${ip}` });
  }
  if (opts.trustedIps.ipList.enabled) {
    if (!isValidListName(opts.trustedIps.ipList.name)) {
      errors.push({
        path: "trustedIps.ipList.name",
        message: "List name must be lowercase letters, digits or underscores (1-64 characters).",
      });
    }
    if (opts.trustedIps.inline.length > 0) {
      warnings.push({
        path: "trustedIps.ipList.enabled",
        message: "IP list mode is on, so the inline addresses are ignored.",
      });
    }
  }

  for (const value of opts.allowedQueryStrings) {
    if (!isValidQueryString(value)) {
      errors.push({ path: "allowedQueryStrings", message: `Invalid query string entry: ${value}` });
    }
  }
  for (const value of opts.allowedUserAgents) {
    if (!isValidUserAgent(value)) {
      errors.push({ path: "allowedUserAgents", message: `Invalid user agent entry: ${value}` });
    }
  }
  for (const value of opts.blockedPaths) {
    if (!isValidPath(value)) {
      errors.push({ path: "blockedPaths", message: `Path must start with "/" and contain no spaces: ${value}` });
    }
  }
  for (const value of opts.blockedAsns) {
    if (!isValidAsn(value)) errors.push({ path: "blockedAsns", message: `Not a valid ASN: ${value}` });
  }
  for (const value of opts.geo.allowedCountries) {
    if (!isValidCountry(value)) {
      errors.push({ path: "geo.allowedCountries", message: `Country code must be two letters: ${value}` });
    }
  }
  if (opts.geo.enabled && opts.geo.allowedCountries.length === 0) {
    warnings.push({
      path: "geo.allowedCountries",
      message: "No allowed countries selected, so the geo challenge rule is skipped.",
    });
  }
  if (opts.allowedUserAgents.length > 0) {
    warnings.push({
      path: "allowedUserAgents",
      message: "User-agent matches are spoofable: any client sending that string skips the rules below.",
    });
  }

  return { errors, warnings, options: opts };
}

// -- rule construction -----------------------------------------------------

function clausePrefix(index) {
  return index === 0 ? "" : " or ";
}

function joinClauses(clauses) {
  return clauses
    .map((clause, index) => `${clausePrefix(index)}${clause}`)
    .join("");
}

function buildR1(opts) {
  const clauses = [];

  if (opts.trustedIps.ipList.enabled && isValidListName(opts.trustedIps.ipList.name)) {
    clauses.push(`(ip.src in $${opts.trustedIps.ipList.name})`);
  } else if (opts.trustedIps.inline.length > 0) {
    clauses.push(`(ip.src in { ${opts.trustedIps.inline.join(" ")} })`);
  }

  for (const query of opts.allowedQueryStrings) {
    clauses.push(`(http.request.uri.query contains "${escapeValue(query)}")`);
  }
  for (const userAgent of opts.allowedUserAgents) {
    clauses.push(`(http.user_agent contains "${escapeValue(userAgent)}")`);
  }
  if (opts.allowVerifiedBots) {
    clauses.push("(cf.client.bot)");
  }
  if (opts.allowTwoFactorActions) {
    clauses.push(
      '(http.request.uri.path eq "/wp-login.php" and any(http.request.uri.args["action"][*] in {"validate_2fa" "backup_2fa" "grace_2fa"}))',
    );
  }

  if (clauses.length === 0) return null;
  return {
    ref: `${REF_PREFIX}r1`,
    ruleNumber: "1",
    action: "skip",
    actionParameters: { ruleset: "current" },
    expression: joinClauses(clauses),
    label: RULE_TITLES[1],
  };
}

function buildR2(opts) {
  const clauses = [];
  const paths = [...opts.blockedPaths];
  if (opts.blockXmlrpc && !paths.includes("/xmlrpc.php")) {
    paths.push("/xmlrpc.php");
  }

  for (const path of paths) {
    clauses.push(`(http.request.uri.path eq "${escapeValue(path)}")`);
  }
  if (opts.blockedAsns.length > 0) {
    clauses.push(`(ip.src.asnum in {${opts.blockedAsns.join(" ")}})`);
  }

  if (clauses.length === 0) return null;
  return {
    ref: `${REF_PREFIX}r2`,
    ruleNumber: "2",
    action: "block",
    expression: joinClauses(clauses),
    label: RULE_TITLES[2],
  };
}

function buildR3(opts) {
  if (!opts.challengeLoginAdmin) return null;
  return {
    ref: `${REF_PREFIX}r3`,
    ruleNumber: "3",
    action: "managed_challenge",
    expression:
      '(http.request.uri.path contains "/wp-login.php") or (http.request.uri.path contains "/wp-admin/" and http.request.uri.path ne "/wp-admin/admin-ajax.php" and not http.request.uri.path contains "/wp-admin/js/password-strength-meter.min.js")',
    label: RULE_TITLES[3],
  };
}

function buildR4(opts) {
  if (!opts.geo.enabled) return null;
  const countries = opts.geo.allowedCountries.filter(isValidCountry);
  if (countries.length === 0) return null;
  return {
    ref: `${REF_PREFIX}r4`,
    ruleNumber: "4",
    action: opts.geo.action,
    expression: `(not ip.geoip.country in {${countries.map((code) => `"${code}"`).join(" ")}})`,
    label: RULE_TITLES[4],
  };
}

/**
 * Build the rule set for the given options.
 * Rule order is R1 (skip), R2 (block), R3 (challenge login), R4 (geo).
 * Rules whose expression would be empty are omitted.
 */
export function buildRules(options) {
  const opts = normalizeOptions(options);
  const rules = [buildR1(opts), buildR2(opts), buildR3(opts), buildR4(opts)];
  return rules.filter(Boolean);
}
