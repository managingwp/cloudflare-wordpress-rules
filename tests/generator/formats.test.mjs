// Output renderer tests: refs, description version/hash, API body, manifest,
// v3 profile export and the Free-plan limit helpers.

import test from "node:test";
import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";

import { buildRules, REF_PREFIX } from "../../website/static/generator/js/rules.js";
import {
  entrypointUrl,
  fnv1a8,
  ruleDescription,
  slugify,
  toApiBody,
  toCurl,
  toManifest,
  toV3Profile,
} from "../../website/static/generator/js/format.js";
import {
  MAX_CUSTOM_RULES,
  MAX_EXPRESSION_CHARS,
  charsOf,
  isNearLimit,
  isOverLimit,
  summarizeLimits,
} from "../../website/static/generator/js/limits.js";

const readJson = async (relativePath) =>
  JSON.parse(await readFile(new URL(relativePath, import.meta.url), "utf8"));

const base = await readJson("../../website/static/generator/profiles/default.json");
const rules = buildRules(base.options);
const version = base.templateVersion;

test("refs are stable and prefixed", () => {
  assert.deepEqual(rules.map((rule) => rule.ref), ["lmt-r1", "lmt-r2", "lmt-r3", "lmt-r4"]);
  for (const rule of rules) assert.ok(rule.ref.startsWith(REF_PREFIX));
});

test("hash is deterministic, 8 hex characters, and expression-specific", () => {
  assert.equal(fnv1a8("abc"), fnv1a8("abc"));
  assert.match(fnv1a8("abc"), /^[0-9a-f]{8}$/);
  assert.notEqual(fnv1a8("abc"), fnv1a8("abd"));
});

test("description carries ref, template version and hash", () => {
  for (const rule of rules) {
    const description = ruleDescription(rule, version);
    assert.match(description, new RegExp(`^${rule.ref} \\| t${version}-[0-9a-f]{8} \\| `));
    assert.ok(description.length <= 200, description);
  }
});

test("changing one expression changes only that rule's hash", () => {
  const before = new Map(rules.map((rule) => [rule.ref, fnv1a8(rule.expression)]));
  const edited = buildRules({ ...base.options, blockedPaths: [...base.options.blockedPaths, "/extra"] });
  const after = new Map(edited.map((rule) => [rule.ref, fnv1a8(rule.expression)]));
  assert.notEqual(before.get("lmt-r2"), after.get("lmt-r2"));
  assert.equal(before.get("lmt-r1"), after.get("lmt-r1"));
});

test("API body is a valid PUT entrypoint payload", () => {
  const body = toApiBody(rules, version);
  assert.equal(body.rules.length, rules.length);
  for (const rule of body.rules) {
    assert.ok(["skip", "block", "managed_challenge", "js_challenge"].includes(rule.action));
    assert.equal(rule.enabled, true);
    assert.deepEqual(rule.logging, { enabled: true });
    assert.equal(typeof rule.expression, "string");
    assert.match(rule.ref, /^lmt-r[0-9]+$/);
    if (rule.action === "skip") assert.deepEqual(rule.action_parameters, { ruleset: "current" });
    else assert.equal(rule.action_parameters, undefined);
  }
  assert.deepEqual(JSON.parse(JSON.stringify(body)), body);
  assert.ok(entrypointUrl().endsWith("/rulesets/phases/http_request_firewall_custom/entrypoint"));
  assert.match(toCurl(body), /-X PUT/);
});

test("manifest lists every rule with ref, hash and action", () => {
  const manifest = toManifest(rules, version);
  assert.equal(manifest.templateVersion, String(version));
  assert.equal(manifest.refPrefix, "lmt-");
  assert.equal(manifest.rules.length, rules.length);
  for (const entry of manifest.rules) {
    assert.match(entry.hash, /^[0-9a-f]{8}$/);
    assert.equal(entry.hash, fnv1a8(rules.find((rule) => rule.ref === entry.ref).expression));
  }
});

test("v3 profile export matches the profile schema the bash script reads", () => {
  const profile = toV3Profile("default-export", "Exported from the generator", rules, version);
  assert.equal(profile.version, 3);
  assert.equal(profile.phase, "http_request_firewall_custom");
  assert.equal(profile.rules.length, rules.length);
  profile.rules.forEach((entry, index) => {
    assert.equal(entry.rule_number, String(index + 1));
    assert.equal(entry.rule_version, String(version));
    assert.equal(entry.action, rules[index].action);
    assert.equal(entry.expression, rules[index].expression);
    assert.equal(entry.enabled, true);
    assert.deepEqual(entry.logging, { enabled: true });
  });
  assert.deepEqual(profile.rules[0].action_parameters, { ruleset: "current" });
});

test("slugify produces a valid profile file name", () => {
  assert.equal(slugify("WordPress default"), "wordpress-default");
  assert.equal(slugify("!!!"), "profile");
});

test("limit helpers mirror the Free plan", () => {
  assert.equal(MAX_CUSTOM_RULES, 5);
  assert.equal(MAX_EXPRESSION_CHARS, 4096);
  assert.equal(charsOf(undefined), 0);
  assert.equal(charsOf(rules[0].expression), rules[0].expression.length);
  assert.equal(isOverLimit(4096), false);
  assert.equal(isOverLimit(4097), true);
  const warnAt = Math.ceil(MAX_EXPRESSION_CHARS * 0.9);
  assert.equal(isNearLimit(warnAt), true);
  assert.equal(isNearLimit(warnAt - 1), false);
});

test("summarizeLimits reports the bundled rule set inside every limit", () => {
  const summary = summarizeLimits(rules);
  assert.equal(summary.rules, rules.length);
  assert.equal(summary.rulesOver, false);
  assert.equal(summary.overLimit, false);
  assert.equal(summary.perRule.length, rules.length);
  assert.ok(summary.perRule.every((entry) => entry.chars < MAX_EXPRESSION_CHARS));
});

test("summarizeLimits flags an over-limit expression and too many rules", () => {
  const padding = " or ".repeat(2000);
  const summary = summarizeLimits([
    { ref: "lmt-r1", expression: `(cf.client.bot)${padding}` },
    { ref: "lmt-r2", expression: "(cf.client.bot)" },
    { ref: "lmt-r3", expression: "(cf.client.bot)" },
    { ref: "lmt-r4", expression: "(cf.client.bot)" },
    { ref: "lmt-r5", expression: "(cf.client.bot)" },
    { ref: "lmt-r6", expression: "(cf.client.bot)" },
  ]);
  assert.equal(summary.overLimit, true);
  assert.equal(summary.rulesOver, true);
  assert.equal(summary.perRule[0].over, true);
});
