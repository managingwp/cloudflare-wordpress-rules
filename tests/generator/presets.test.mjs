// Preset manifest, schema and `extends` resolution tests.

import test from "node:test";
import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";

import {
  checkPreset,
  importPreset,
  resolvePresets,
  exportPreset,
} from "../../website/static/generator/js/presets.js";
import {
  DEFAULT_TEMPLATE_VERSION,
  normalizeOptions,
  validateOptions,
} from "../../website/static/generator/js/rules.js";

const readJson = async (relativePath) =>
  JSON.parse(await readFile(new URL(relativePath, import.meta.url), "utf8"));

const manifest = await readJson("../../website/static/generator/profiles/index.json");
const presets = await Promise.all(
  manifest.presets.map((name) => readJson(`../../website/static/generator/profiles/${name}.json`)),
);

test("manifest lists unique presets that each resolve to a file", () => {
  assert.equal(new Set(manifest.presets).size, manifest.presets.length);
  for (const preset of presets) {
    assert.equal(typeof preset.name, "string");
    assert.ok(manifest.presets.includes(preset.name), `${preset.name} is not in index.json`);
  }
});

test("every preset passes schema validation with no warnings", () => {
  for (const preset of presets) {
    const checked = checkPreset(preset, preset.name);
    assert.deepEqual(checked.errors, [], `${preset.name}: ${checked.errors.join("; ")}`);
    assert.deepEqual(checked.warnings, [], `${preset.name}: ${checked.warnings.join("; ")}`);
  }
});

test("every preset resolves and validates cleanly", () => {
  for (const preset of resolvePresets(presets)) {
    const options = normalizeOptions(preset.options);
    const { errors } = validateOptions(options);
    assert.deepEqual(errors, [], `${preset.name}: ${errors.map((error) => error.message).join("; ")}`);
    assert.ok(options.trustedIps.inline.length > 0 || options.trustedIps.ipList.enabled);
  }
});

test("default preset templateVersion tracks profiles/default.json", async () => {
  const profile = await readJson("../../profiles/default.json");
  assert.equal(DEFAULT_TEMPLATE_VERSION, String(profile.rules[0].rule_version));
  const base = presets.find((preset) => preset.name === "default");
  assert.equal(base.templateVersion, DEFAULT_TEMPLATE_VERSION);
});

test("extends inherits parent options and overrides only what it names", () => {
  const [beta] = resolvePresets(presets).filter((preset) => preset.name === "beta");
  const [base] = resolvePresets(presets).filter((preset) => preset.name === "default");

  assert.equal(beta.options.trustedIps.inline.length, base.options.trustedIps.inline.length);
  assert.ok(beta.options.allowedUserAgents.includes("PerplexityBot"));
  assert.ok(beta.options.allowedUserAgents.includes("Zapier"));
  assert.equal(beta.options.allowTwoFactorActions, true);
  assert.equal(base.options.allowTwoFactorActions, false);
});

test("presets differ where they are meant to differ", () => {
  const resolved = resolvePresets(presets);
  const byName = Object.fromEntries(resolved.map((preset) => [preset.name, preset]));

  assert.equal(byName["default"].options.geo.action, "js_challenge");
  assert.equal(byName["strict-geo"].options.geo.action, "block");
  assert.ok(byName["strict-geo"].options.allowedUserAgents.length < byName["default"].options.allowedUserAgents.length);
  assert.ok(byName["woocommerce"].options.allowedUserAgents.includes("Stripe/"));
  assert.equal(byName["woocommerce"].options.allowTwoFactorActions, true);
});

test("an extends cycle is rejected", () => {
  const cyclic = [
    { name: "a", label: "A", options: {}, extends: "b" },
    { name: "b", label: "B", options: {}, extends: "a" },
  ];
  assert.throws(() => resolvePresets(cyclic), /cycle/i);
});

test("an extends to an unknown preset is rejected", () => {
  assert.throws(
    () => resolvePresets([{ name: "a", label: "A", options: {}, extends: "nope" }]),
    /unknown preset/i,
  );
});

test("schema rejects a preset without options or with a bad name", () => {
  const missing = checkPreset({ name: "bad", label: "Bad" });
  assert.ok(missing.errors.some((error) => error.includes("options")));
  const upper = checkPreset({ name: "Bad Name", label: "Bad", options: {} });
  assert.ok(upper.errors.some((error) => error.includes("lowercase slug")));
});

test("unknown option keys warn instead of failing", () => {
  const { errors, warnings } = checkPreset({
    name: "extra",
    label: "Extra",
    options: { geo: { enabled: false, action: "log", allowedCountries: [] }, nonsense: true },
  });
  assert.deepEqual(errors, []);
  assert.ok(warnings.some((warning) => warning.includes("nonsense")));
});

test("import marks the preset and export round-trips it", async () => {
  const base = presets.find((preset) => preset.name === "default");
  const { preset } = importPreset(base, "default");
  assert.equal(preset.name, "default-imported");
  const roundTrip = JSON.parse(exportPreset(preset));
  assert.equal(roundTrip.templateVersion, base.templateVersion);
  assert.deepEqual(roundTrip.options.trustedIps.inline, base.options.trustedIps.inline);
  assert.equal(roundTrip.imported, undefined);
});
