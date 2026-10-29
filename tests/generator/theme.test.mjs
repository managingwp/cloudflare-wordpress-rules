// Colour-theme tests: Auto follows the operating system, an explicit choice
// wins, and the pre-paint boot script agrees with the module it pairs with.

import test from "node:test";
import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";

import { THEME_PREFERENCES, resolveTheme } from "../../website/static/generator/js/theme.js";

const read = (relativePath) => readFile(new URL(relativePath, import.meta.url), "utf8");

test("auto follows the operating system", () => {
  assert.equal(resolveTheme("auto", true), "dark");
  assert.equal(resolveTheme("auto", false), "light");
});

test("an explicit choice ignores the operating system", () => {
  assert.equal(resolveTheme("light", true), "light");
  assert.equal(resolveTheme("dark", false), "dark");
});

test("unknown or missing preferences fall back to auto", () => {
  for (const value of [undefined, null, "", "sepia", 42]) {
    assert.equal(resolveTheme(value, true), "dark");
    assert.equal(resolveTheme(value, false), "light");
  }
});

test("preference values are exactly auto, light and dark", () => {
  assert.deepEqual(THEME_PREFERENCES, ["auto", "light", "dark"]);
});

test("boot script and module share the storage key and preference values", async () => {
  const [boot, module] = await Promise.all([
    read("../../website/static/generator/js/theme-boot.js"),
    read("../../website/static/generator/js/theme.js"),
  ]);

  const key = /"cfwpr\.generator\.theme\.v1"/;
  assert.match(boot, key);
  assert.match(module, key);

  for (const preference of THEME_PREFERENCES) {
    assert.match(boot, new RegExp(`"${preference}"`));
    assert.match(module, new RegExp(`"${preference}"`));
  }
});

test("boot script resolves the theme before setting both attributes", async () => {
  const boot = await read("../../website/static/generator/js/theme-boot.js");
  assert.match(boot, /setAttribute\("data-theme",/);
  assert.match(boot, /setAttribute\("data-theme-preference",/);
});
