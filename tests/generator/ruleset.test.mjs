// Rule-set model tests: every release profile under profiles/ loads into the
// shared rule shape, keeps its expressions byte for byte, and exports in the
// current v207 envelope.

import test from "node:test";
import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";

import {
  isHandEdited,
  normalizeRule,
  rebuildRule,
  rulesFromOptions,
  rulesFromProfile,
  versionFor,
} from "../../website/static/generator/js/ruleset.js";
import { toApiBody, toV3Profile } from "../../website/static/generator/js/format.js";
import { buildRules } from "../../website/static/generator/js/rules.js";

const readJson = async (relativePath) =>
  JSON.parse(await readFile(new URL(relativePath, import.meta.url), "utf8"));

const PROFILES = [
  { file: "../../profiles/mwp-rules-v207.json", version: "207" },
  { file: "../../profiles/mwp-rules-v205.json", version: "205" },
  { file: "../../profiles/mwp-rules-v204.json", version: "204" },
  { file: "../../profiles/mwp-rules-v203.json", version: "203" },
  { file: "../../profiles/mwp-rules-v201-events.json", version: "201-events" },
  { file: "../../profiles/mwp-rules-beta.json", version: "beta" },
];

const loaded = await Promise.all(
  PROFILES.map(async (entry) => ({ ...entry, profile: await readJson(entry.file) })),
);

test("every release profile loads four rules with byte-identical expressions", () => {
  for (const { file, profile } of loaded) {
    const rules = rulesFromProfile(profile);
    assert.equal(rules.length, 4, file);
    assert.deepEqual(
      rules.map((rule) => rule.expression),
      profile.rules.map((rule) => rule.expression),
      `${file}: expressions must survive loading untouched`,
    );
  }
});

test("the version label comes from the rules, or the filename for 201-events", () => {
  for (const { file, profile, version } of loaded) {
    assert.equal(versionFor(profile, version), version, file);
  }
  // 201-events predates the rule_version field.
  const events = loaded.find((entry) => entry.version === "201-events").profile;
  assert.equal(events.rules.every((rule) => rule.rule_version === undefined), true);
  assert.equal(versionFor(events, "201-events"), "201-events");
});

test("loading drops priority and defaults the current envelope", () => {
  for (const { file, profile } of loaded) {
    const rules = rulesFromProfile(profile);
    assert.equal(
      rules.some((rule) => Object.hasOwn(rule, "priority")),
      false,
      `${file}: priority must not survive normalisation`,
    );
    for (const rule of rules) {
      assert.equal(rule.enabled, true, `${file} ${rule.ref}: enabled`);
      assert.equal(rule.logging, true, `${file} ${rule.ref}: logging`);
      assert.equal(rule.origin, "loaded", `${file} ${rule.ref}: origin`);
    }
  }
});

test("skip rules keep their action parameters or gain the current ruleset", () => {
  const synthetic = normalizeRule({ rule_number: "1", action: "skip", expression: "(cf.client.bot)" }, 0);
  assert.deepEqual(synthetic.actionParameters, { ruleset: "current" });

  const kept = normalizeRule(
    {
      rule_number: "1",
      action: "skip",
      expression: "(cf.client.bot)",
      action_parameters: { ruleset: "previous" },
    },
    0,
  );
  assert.deepEqual(kept.actionParameters, { ruleset: "previous" });
});

test("an unknown rule action is reported rather than silently kept", () => {
  const rule = normalizeRule({ rule_number: "2", action: "bypass", expression: "(cf.client.bot)" }, 0);
  assert.equal(rule.action, "block");
  assert.equal(rule.actionInvalid, "bypass");
});

test("the exported API body is always the v207 shape", () => {
  for (const { file, profile, version } of loaded) {
    const body = toApiBody(rulesFromProfile(profile), version);
    const json = JSON.stringify(body);
    assert.equal(json.includes('"priority"'), false, `${file}: no priority in the API body`);
    for (const rule of body.rules) {
      assert.deepEqual(rule.logging, { enabled: true }, `${file}: logging`);
      assert.match(rule.description, new RegExp(`^lmt-r\\d \\| t${version.replace(/[.*+?^${}()|[\]\\]/g, "\\$&")}-`), `${file}: stamp`);
    }
  }
});

test("the v3 profile export carries the loaded expressions and the version", () => {
  for (const { profile, version } of loaded) {
    const rules = rulesFromProfile(profile);
    const exported = toV3Profile("test", "test", rules, version);
    assert.deepEqual(
      exported.rules.map((rule) => rule.expression),
      rules.map((rule) => rule.expression),
    );
    assert.equal(exported.rules.every((rule) => rule.rule_version === version), true);
  }
});

test("builder rules and loaded rules share one shape", () => {
  const profile = loaded.find((entry) => entry.version === "207").profile;
  const options = {
    trustedIps: { inline: ["203.0.113.10"], ipList: { enabled: false, name: "" } },
    allowedQueryStrings: [],
    allowedUserAgents: [],
    allowVerifiedBots: true,
    allowTwoFactorActions: false,
    blockedPaths: ["/xmlrpc.php"],
    blockXmlrpc: false,
    blockedAsns: [],
    challengeLoginAdmin: true,
    geo: { enabled: true, action: "js_challenge", allowedCountries: ["CA"] },
  };
  const built = rulesFromOptions(options);
  assert.deepEqual(built.map((rule) => rule.ref), buildRules(options).map((rule) => rule.ref));
  assert.equal(built.every((rule) => rule.origin === "fields"), true);

  const keys = (rules) => [...new Set(rules.flatMap((rule) => Object.keys(rule)))].sort();
  assert.deepEqual(
    keys(built),
    keys(rulesFromProfile(profile)).filter((key) => key !== "actionParameters" || built.some((rule) => "actionParameters" in rule)),
  );
});

test("rebuilding one rule from the fields leaves the others alone", () => {
  const profile = loaded.find((entry) => entry.version === "205").profile;
  const rules = rulesFromProfile(profile);
  const options = {
    trustedIps: { inline: ["203.0.113.10"], ipList: { enabled: false, name: "" } },
    allowedQueryStrings: [],
    allowedUserAgents: [],
    allowVerifiedBots: false,
    allowTwoFactorActions: false,
    blockedPaths: [],
    blockXmlrpc: false,
    blockedAsns: [],
    challengeLoginAdmin: false,
    geo: { enabled: false, action: "js_challenge", allowedCountries: [] },
  };

  const rebuilt = rebuildRule(rules, "lmt-r1", options);
  assert.equal(rebuilt.find((rule) => rule.ref === "lmt-r1").origin, "fields");
  assert.equal(
    rebuilt.find((rule) => rule.ref === "lmt-r1").expression,
    "(ip.src in { 203.0.113.10 })",
  );
  for (const ref of ["lmt-r2", "lmt-r3", "lmt-r4"]) {
    assert.deepEqual(
      rebuilt.find((rule) => rule.ref === ref),
      rules.find((rule) => rule.ref === ref),
      `${ref} must not change`,
    );
  }
});

test("a rule the fields no longer produce is removed, not left behind", () => {
  const rules = rulesFromProfile(loaded.find((entry) => entry.version === "207").profile);
  const options = {
    trustedIps: { inline: ["203.0.113.10"], ipList: { enabled: false, name: "" } },
    allowedQueryStrings: [],
    allowedUserAgents: [],
    allowVerifiedBots: false,
    allowTwoFactorActions: false,
    blockedPaths: [],
    blockXmlrpc: false,
    blockedAsns: [],
    challengeLoginAdmin: false,
    geo: { enabled: false, action: "js_challenge", allowedCountries: [] },
  };
  const rebuilt = rebuildRule(rules, "lmt-r4", options);
  assert.equal(rebuilt.some((rule) => rule.ref === "lmt-r4"), false);
});

test("hand-edited is a rule-level state, not a page-level one", () => {
  const rules = rulesFromProfile(loaded.find((entry) => entry.version === "207").profile);
  const edited = rules.map((rule) =>
    rule.ref === "lmt-r2" ? { ...rule, expression: "(cf.client.bot)", origin: "manual" } : rule,
  );
  assert.deepEqual(edited.filter(isHandEdited).map((rule) => rule.ref), ["lmt-r2"]);
});
