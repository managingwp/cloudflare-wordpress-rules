// Rule builder tests: the generator must reproduce the rule set the bash
// pipeline deploys, so these tests compare against profiles/*.json directly.

import test from "node:test";
import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";

import {
  buildRules,
  normalizeOptions,
  validateOptions,
  DEFAULT_OPTIONS,
} from "../../website/static/generator/js/rules.js";
import { resolvePresets } from "../../website/static/generator/js/presets.js";

const readJson = async (relativePath) =>
  JSON.parse(await readFile(new URL(relativePath, import.meta.url), "utf8"));

const preset = async (name) => readJson(`../../website/static/generator/profiles/${name}.json`);

// Whitespace-collapse, drop repeated clauses and repeated IPs (the deployed
// profiles carry duplicated entries, e.g. "Infusionsoft" twice and
// 45.77.148.172 twice); everything else must match.
function canonical(expression) {
  const collapsed = expression.replace(/\s+/g, " ").trim();
  const seen = new Set();
  const clauses = [];
  for (const clause of collapsed.split(" or ")) {
    const key = clause.trim();
    if (seen.has(key)) continue;
    seen.add(key);
    clauses.push(key);
  }
  return clauses
    .map((clause) => {
      const match = /^\(ip\.src in \{ (.*) \}\)$/.exec(clause);
      if (!match) return clause;
      const ips = [...new Set(match[1].split(" ").filter(Boolean))];
      return `(ip.src in { ${ips.join(" ")} })`;
    })
    .join(" or ");
}

test("default preset reproduces the stable v207 rule set", async () => {
  const profile = await readJson("../../profiles/mwp-rules-v207.json");
  const base = await preset("default");
  const rules = buildRules(base.options);

  assert.equal(rules.length, profile.rules.length);
  profile.rules.forEach((expected, index) => {
    const actual = rules[index];
    assert.equal(actual.ref, `lmt-r${expected.rule_number}`);
    assert.equal(actual.action, expected.action, `R${expected.rule_number} action`);
    assert.equal(
      canonical(actual.expression),
      canonical(expected.expression),
      `R${expected.rule_number} expression`,
    );
  });
});

test("beta preset reproduces the beta profile", async () => {
  const profile = await readJson("../../profiles/mwp-rules-beta.json");
  const [resolved] = resolvePresets([await preset("beta"), await preset("default")])
    .filter((item) => item.name === "beta");
  const rules = buildRules(resolved.options);

  assert.equal(rules.length, profile.rules.length);
  profile.rules.forEach((expected, index) => {
    assert.equal(
      canonical(rules[index].expression),
      canonical(expected.expression),
      `R${expected.rule_number} expression`,
    );
  });
  assert.match(rules[0].expression, /Perplexity-User/);
  assert.match(rules[0].expression, /validate_2fa/);
});

test("rule order is skip, block, login challenge, geo challenge", async () => {
  const base = await preset("default");
  const rules = buildRules(base.options);
  assert.deepEqual(rules.map((rule) => rule.action), [
    "skip",
    "block",
    "managed_challenge",
    "js_challenge",
  ]);
  assert.deepEqual(rules.map((rule) => rule.ref), ["lmt-r1", "lmt-r2", "lmt-r3", "lmt-r4"]);
});

test("R1 starts with the IP clause and ends with the verified-bot clause", async () => {
  const base = await preset("default");
  const [r1] = buildRules(base.options);
  assert.ok(r1.expression.startsWith("(ip.src in { "), r1.expression.slice(0, 40));
  assert.ok(r1.expression.endsWith("(cf.client.bot)"), r1.expression.slice(-40));
});

test("IP list mode replaces the inline list", async () => {
  const base = await preset("default");
  const options = normalizeOptions({
    ...base.options,
    trustedIps: { inline: ["192.0.2.1"], ipList: { enabled: true, name: "trusted_sources" } },
  });
  const [r1] = buildRules(options);
  assert.ok(r1.expression.startsWith("(ip.src in $trusted_sources)"));
  assert.ok(!r1.expression.includes("192.0.2.1"));
  assert.deepEqual(validateOptions(options).errors, []);
});

test("geo countries are upper-cased, de-duplicated and sorted", () => {
  const rules = buildRules({
    ...DEFAULT_OPTIONS,
    geo: { enabled: true, action: "managed_challenge", allowedCountries: ["us", "CA", "US", "gb"] },
  });
  const geo = rules.find((rule) => rule.ref === "lmt-r4");
  assert.equal(geo.expression, '(not ip.geoip.country in {"CA" "GB" "US"})');
  assert.equal(geo.action, "managed_challenge");
});

test("rules with no clauses are omitted", () => {
  const rules = buildRules({
    trustedIps: { inline: [], ipList: { enabled: false, name: "" } },
    allowedQueryStrings: [],
    allowedUserAgents: [],
    allowVerifiedBots: false,
    allowTwoFactorActions: false,
    blockedPaths: [],
    blockXmlrpc: false,
    blockedAsns: [],
    challengeLoginAdmin: false,
    geo: { enabled: false, action: "js_challenge", allowedCountries: [] },
  });
  assert.deepEqual(rules, []);
});

test("individual toggles remove exactly one rule", async () => {
  const base = await preset("default");
  assert.ok(!buildRules({ ...base.options, geo: { ...base.options.geo, enabled: false } })
    .some((rule) => rule.ref === "lmt-r4"));
  assert.ok(!buildRules({ ...base.options, challengeLoginAdmin: false })
    .some((rule) => rule.ref === "lmt-r3"));
  const r2 = buildRules({ ...base.options, blockXmlrpc: false })
    .find((rule) => rule.ref === "lmt-r2");
  assert.ok(!r2.expression.includes("/xmlrpc.php"));
  assert.match(r2.expression, /ip\.src\.asnum/);
});

test("geo enabled with no countries drops R4", () => {
  const rules = buildRules({ ...DEFAULT_OPTIONS, geo: { enabled: true, action: "block", allowedCountries: [] } });
  assert.ok(!rules.some((rule) => rule.ref === "lmt-r4"));
});

test("duplicate paths and IPs collapse without reordering", () => {
  const rules = buildRules({
    ...DEFAULT_OPTIONS,
    trustedIps: { inline: ["192.0.2.2", "192.0.2.1", "192.0.2.2"], ipList: { enabled: false, name: "" } },
    blockedPaths: ["/a", "/b", "/a"],
    blockXmlrpc: false,
    blockedAsns: [],
    allowedUserAgents: [],
    allowedQueryStrings: [],
  });
  assert.ok(rules[0].expression.startsWith("(ip.src in { 192.0.2.2 192.0.2.1 })"));
  assert.equal(rules[1].expression, '(http.request.uri.path eq "/a") or (http.request.uri.path eq "/b")');
});

test("quotes in user agents are escaped, not injected", () => {
  const rules = buildRules({
    ...DEFAULT_OPTIONS,
    allowedUserAgents: ['Evil" ) or (cf.client.bot) or ("'],
    trustedIps: { inline: [], ipList: { enabled: false, name: "" } },
    allowedQueryStrings: [],
    geo: { enabled: false, action: "js_challenge", allowedCountries: [] },
    challengeLoginAdmin: false,
    blockXmlrpc: false,
    blockedPaths: [],
    allowVerifiedBots: false,
  });
  assert.equal(rules.length, 1);
  assert.ok(rules[0].expression.includes('\\"'));
});

test("validation reports invalid IPs, ASNs, list names and countries", () => {
  const { errors } = validateOptions({
    ...DEFAULT_OPTIONS,
    trustedIps: { inline: ["999.1.1.1", "192.0.2.1/33"], ipList: { enabled: true, name: "Bad Name" } },
    blockedAsns: ["0", "abc"],
    blockedPaths: ["no-slash"],
    geo: { enabled: true, action: "block", allowedCountries: ["USA"] },
  });
  const paths = errors.map((error) => error.path);
  for (const path of ["trustedIps.inline", "trustedIps.ipList.name", "blockedAsns", "blockedPaths", "geo.allowedCountries"]) {
    assert.ok(paths.includes(path), `expected an error for ${path}`);
  }
});

test("validation warns about spoofable user agents and ignored inline IPs", () => {
  const { warnings } = validateOptions({
    ...DEFAULT_OPTIONS,
    trustedIps: { inline: ["192.0.2.1"], ipList: { enabled: true, name: "trusted" } },
    allowedUserAgents: ["PerplexityBot"],
  });
  const paths = warnings.map((warning) => warning.path);
  assert.ok(paths.includes("allowedUserAgents"));
  assert.ok(paths.includes("trustedIps.ipList.enabled"));
});

test("IPv6 and CIDR ranges are accepted", () => {
  const { errors } = validateOptions({
    ...DEFAULT_OPTIONS,
    trustedIps: { inline: ["2001:db8::1", "2001:db8::/32", "192.0.2.0/24"], ipList: { enabled: false, name: "" } },
  });
  assert.deepEqual(errors, []);
});
