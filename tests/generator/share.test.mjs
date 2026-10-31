// Share-link and stored-state tests: the v2 payload round trip, the hand-edited
// rules it carries, and v1 links minted before the editor existed.

import test from "node:test";
import assert from "node:assert/strict";

import {
  decodePayload,
  encodePayload,
  manualRulesFor,
  readShareState,
} from "../../website/static/generator/js/share.js";

const OPTIONS = {
  trustedIps: { inline: ["203.0.113.10"], ipList: { enabled: false, name: "" } },
  allowedUserAgents: ["Zapier"],
  geo: { enabled: true, action: "js_challenge", allowedCountries: ["CA", "US"] },
};

test("a v2 payload survives encode and decode", () => {
  const payload = {
    k: "release",
    n: "205",
    v: "205",
    o: OPTIONS,
    m: [
      { ref: "lmt-r1", action: "skip", enabled: true, logging: true, expression: "(cf.client.bot)", ap: { ruleset: "current" } },
    ],
  };
  const state = readShareState(decodePayload(encodePayload(payload)));
  assert.equal(state.kind, "release");
  assert.equal(state.name, "205");
  assert.equal(state.version, "205");
  assert.deepEqual(state.options, OPTIONS);
  assert.equal(state.manual.length, 1);
  assert.equal(state.manual[0].expression, "(cf.client.bot)");
  assert.deepEqual(state.manual[0].ap, { ruleset: "current" });
});

test("a v1 payload (p, v, o) still decodes as a builder source", () => {
  const legacy = encodePayload({ p: "woocommerce", v: "207", o: OPTIONS });
  const state = readShareState(decodePayload(legacy));
  assert.equal(state.kind, "builder");
  assert.equal(state.name, "woocommerce");
  assert.equal(state.version, "207");
  assert.deepEqual(state.options, OPTIONS);
  assert.deepEqual(state.manual, []);
});

test("only hand-edited rules are carried", () => {
  const rules = [
    { ref: "lmt-r1", action: "skip", expression: "a", origin: "fields" },
    { ref: "lmt-r2", action: "block", expression: "b", origin: "loaded" },
    {
      ref: "lmt-r3",
      action: "managed_challenge",
      expression: "c",
      origin: "manual",
      enabled: false,
      logging: true,
    },
  ];
  const manual = manualRulesFor(rules);
  assert.deepEqual(manual.map((rule) => rule.ref), ["lmt-r3"]);
  assert.equal(manual[0].enabled, false);
  assert.equal(manual[0].logging, true);
});

test("garbage in, nothing out", () => {
  assert.equal(decodePayload("not base64 at all !!"), null);
  assert.equal(readShareState(null), null);
  assert.equal(readShareState({}), null);
  assert.equal(readShareState({ k: "nonsense", n: "x" }), null);
  assert.equal(readShareState({ k: "builder" }), null);
});

test("a payload with options but no source name is still readable", () => {
  const state = readShareState({ k: "builder", o: OPTIONS, m: [] });
  assert.equal(state.kind, "builder");
  assert.equal(state.name, "");
  assert.deepEqual(state.options, OPTIONS);
});

test("manual entries keep their shape even when fields are missing", () => {
  const state = readShareState({
    k: "builder",
    n: "default",
    v: "207",
    o: OPTIONS,
    m: [{ ref: "lmt-r1", expression: "(cf.client.bot)" }, null, 42],
  });
  assert.equal(state.manual.length, 1);
  assert.equal(state.manual[0].action, "block");
  assert.equal(state.manual[0].enabled, true);
  assert.equal(state.manual[0].logging, true);
});
