// Versions-manifest tests: the shape the page relies on, and the committed
// manifest agreeing with profiles/.

import test from "node:test";
import assert from "node:assert/strict";
import { readdir, readFile } from "node:fs/promises";

import {
  describeVersion,
  findVersion,
  isUsableVersion,
} from "../../website/static/generator/js/versions.js";

const readJson = async (relativePath) =>
  JSON.parse(await readFile(new URL(relativePath, import.meta.url), "utf8"));

const manifest = await readJson("../../website/static/generator/profiles/versions.json");
const defaultProfile = await readJson("../../profiles/default.json");

test("the committed manifest is generated and names the current release", () => {
  assert.equal(manifest.generatedBy, "bin/generate-versions.sh");
  assert.equal(manifest.current, defaultProfile.rules[0].rule_version);
  assert.ok(manifest.versions.length >= 2);
});

test("the manifest lists every release profile under profiles/", async () => {
  const files = await readdir(new URL("../../profiles/", import.meta.url));
  const expected = files
    .filter((name) => /^mwp-rules-(v.+|beta)\.json$/.test(name))
    .map((name) => name.replace(/^mwp-rules-/, "").replace(/^v/, "").replace(/\.json$/, ""))
    .sort();
  const actual = manifest.versions.map((entry) => entry.value).sort();
  assert.deepEqual(actual, expected);
});

test("every manifest entry carries rules and a source file", () => {
  for (const entry of manifest.versions) {
    assert.equal(isUsableVersion(entry), true, `${entry.value} is usable`);
    assert.match(entry.source, /^profiles\/mwp-rules-.+\.json$/, `${entry.value} source`);
    assert.equal(entry.rules.length, 4, `${entry.value} has four rules`);
  }
});

test("the manifest is ordered newest first, with beta last", () => {
  const values = manifest.versions.map((entry) => entry.value);
  assert.equal(values.at(-1), "beta");
  assert.equal(values.at(-2), "201-events");
  const numeric = values.filter((value) => /^[0-9]+$/.test(value)).map(Number);
  assert.deepEqual(numeric, [...numeric].sort((a, b) => b - a));
});

test("the current entry is exactly one, and it is the newest stable release", () => {
  const current = manifest.versions.filter((entry) => entry.current);
  assert.equal(current.length, 1);
  assert.equal(current[0].value, manifest.current);
});

test("entries without rules are not offered", () => {
  assert.equal(isUsableVersion({ value: "207", rules: [] }), false);
  assert.equal(isUsableVersion({ value: "", rules: [{}] }), false);
  assert.equal(isUsableVersion(null), false);
  assert.equal(isUsableVersion({ value: "207", rules: [{}] }), true);
});

test("findVersion only matches a real label", () => {
  assert.equal(findVersion(manifest.versions, "205").value, "205");
  assert.equal(findVersion(manifest.versions, " 205 ").value, "205");
  assert.equal(findVersion(manifest.versions, "999"), null);
  assert.equal(findVersion(manifest.versions, ""), null);
  assert.equal(findVersion(null, "207"), null);
});

test("describeVersion names the source and keeps the release note", () => {
  const beta = findVersion(manifest.versions, "beta");
  assert.match(describeVersion(beta), /^beta \(staging\) — staging channel \(profiles\/mwp-rules-beta\.json\)$/);

  const older = findVersion(manifest.versions, "205");
  assert.equal(describeVersion(older), "v205 (profiles/mwp-rules-v205.json)");

  assert.equal(describeVersion({ value: "x", rules: [] }), "");
});
